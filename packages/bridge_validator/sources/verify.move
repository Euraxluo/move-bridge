/// 消息验证模块
/// 本模块负责处理跨链消息的验证逻辑，包括：
/// 1. 验证者对消息的签名验证
/// 2. 验证记录的管理
/// 3. 验证状态的追踪
#[allow(lint_allow_modules_with_public_structs)]
module bridge_validator::verify {
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::event;
    use sui::table::{Self, Table};
    use sui::hash::blake2b256;
    use bridge_validator::types::{Self, ValidatorSet};
    use bridge_validator::validator;
    use std::vector;
    use sui::ed25519;

    // === 错误码定义 ===
    /// 当消息格式无效或内容不合法时抛出
    const EINVALID_MESSAGE: u64 = 1;
    /// 当验证者提供的签名无效时抛出
    const EINVALID_SIGNATURE: u64 = 2;
    /// 当非验证者尝试进行验证操作时抛出
    const EINVALID_VALIDATOR: u64 = 3;
    /// 当尝试重复验证已验证的消息时抛出
    const EMESSAGE_ALREADY_VERIFIED: u64 = 4;

    // === 核心数据结构 ===
    /// 消息验证记录
    /// 存储跨链消息的验证状态和验证者签名信息
    public struct MessageVerification has key, store {
        id: UID,
        /// 消息的Blake2b-256哈希值
        message_hash: vector<u8>,
        /// 源链ID
        source_chain: u64,
        /// 目标链ID
        target_chain: u64,
        /// 消息是否已被完全验证
        verified: bool,
        /// 验证者签名映射表
        validator_signatures: Table<address, vector<u8>>,
        /// 已收集的验证数量
        verification_count: u64,
    }

    // === 事件定义 ===
    /// 消息验证事件
    /// 当验证者成功验证一个消息时触发
    public struct MessageVerifiedEvent has copy, drop {
        /// 被验证消息的哈希值
        message_hash: vector<u8>,
        /// 消息的源链ID
        source_chain: u64,
        /// 消息的目标链ID
        target_chain: u64,
        /// 执行验证的验证者地址
        validator: address,
    }

    /// 验证跨链消息
    /// * `validator_set` - 验证器集合
    /// * `message` - 待验证的原始消息
    /// * `signature` - 验证者对消息的ED25519签名
    /// * `source_chain` - 消息的源链ID
    /// * `target_chain` - 消息的目标链ID
    /// 返回：消息是否通过验证（是否达到权重阈值）
    public fun verify_message(
        validator_set: &ValidatorSet,
        message: vector<u8>,
        signature: vector<u8>,
        source_chain: u64,
        target_chain: u64,
        ctx: &mut TxContext
    ): bool {
        let validator = tx_context::sender(ctx);
        
        // 检查是否为有效验证者
        assert!(validator::is_validator(validator_set, validator), EINVALID_VALIDATOR);
        
        // 计算消息的Blake2b-256哈希值
        let message_hash = blake2b256(&message);
        
        // 使用验证者的ED25519公钥验证签名
        let public_key = validator::get_validator_public_key(validator_set, validator);
        assert!(ed25519::ed25519_verify(&signature, &public_key, &message), EINVALID_SIGNATURE);
        
        // 创建验证记录并存储验证者签名
        let mut validator_signatures = table::new(ctx);
        table::add(&mut validator_signatures, validator, signature);
        
        // 检查是否达到验证阈值
        let validator_weight = validator::get_validator_weight(validator_set, validator);
        let threshold = validator::get_threshold(validator_set);
        let threshold_met = validator_weight >= threshold;
        
        // 创建验证记录对象
        let verification = MessageVerification {
            id: object::new(ctx),
            message_hash: copy message_hash,
            source_chain,
            target_chain,
            verified: threshold_met,
            validator_signatures,
            verification_count: 1,
        };
        
        // 发送消息验证事件
        event::emit(MessageVerifiedEvent {
            message_hash: copy message_hash,
            source_chain,
            target_chain,
            validator,
        });
        
        // 共享验证记录对象
        transfer::share_object(verification);
        threshold_met
    }

    /// 检查消息是否已被完全验证
    /// * `verification` - 消息验证记录
    /// 返回：消息是否已被验证通过
    public fun is_message_verified(verification: &MessageVerification): bool {
        verification.verified
    }

    /// 获取消息的验证次数
    /// * `verification` - 消息验证记录
    /// 返回：已收集的验证数量
    public fun get_verification_count(verification: &MessageVerification): u64 {
        verification.verification_count
    }
} 