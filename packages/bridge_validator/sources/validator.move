/// 验证器管理模块
/// 本模块负责管理验证器的生命周期，包括添加、移除验证器，
/// 更新验证器权重，以及处理验证器共识相关的操作
module bridge_validator::validator {
    use sui::object::{Self, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::event;
    use bridge_validator::types::{Self, ValidatorSet, StakeManager};
    use sui::table::{Self, Table};
    use std::vector;

    // === 错误码定义 ===
    /// 当操作的验证器地址无效时抛出
    const EINVALID_VALIDATOR: u64 = 1;
    /// 当设置的验证器权重无效时抛出
    const EINVALID_WEIGHT: u64 = 2;
    /// 当非管理员尝试执行管理员操作时抛出
    const EINVALID_ADMIN: u64 = 3;
    /// 当验证器质押金额不满足要求时抛出
    const EINVALID_STAKE: u64 = 4;
    /// 当验证器公钥格式无效时抛出
    const EINVALID_PUBLIC_KEY: u64 = 5;

    // === 初始化函数 ===
    /// 初始化验证器集合
    /// 创建一个新的验证器集合，并将调用者设置为管理员
    fun init(ctx: &mut TxContext) {
        types::new_validator_set(tx_context::sender(ctx), ctx)
    }

    #[test_only]
    public fun init_for_test(ctx: &mut TxContext) {
        init(ctx)
    }
    // === 验证者管理函数 ===
    /// 添加新的验证器
    /// * `validator_set` - 验证器集合
    /// * `stake_manager` - 质押管理器
    /// * `validator` - 要添加的验证器地址
    /// * `public_key` - 验证器的32字节公钥
    public fun add_validator(
        validator_set: &mut ValidatorSet,
        stake_manager: &StakeManager,
        validator: address,
        public_key: vector<u8>,
        ctx: &mut TxContext
    ) {
        // 验证调用者是管理员
        assert!(types::get_admin(validator_set) == tx_context::sender(ctx), EINVALID_ADMIN);
        
        // 验证公钥长度为32字节(ed25519公钥标准长度)
        assert!(vector::length(&public_key) == 32, EINVALID_PUBLIC_KEY);
        
        // 验证质押金额
        assert!(types::contains_stake(stake_manager, validator), EINVALID_STAKE);
        let stake_info = types::borrow_stake(stake_manager, validator);
        let stake_amount = types::get_stake_amount(stake_info);
        let is_active = types::is_stake_active(stake_info);
        assert!(is_active, EINVALID_STAKE);

        // 添加验证者并计算初始权重
        let weight = calculate_weight(stake_amount);
        types::add_validator_with_weight_and_key(validator_set, validator, weight, public_key);
    }

    /// 移除验证器
    /// * `validator_set` - 验证器集合
    /// * `validator` - 要移除的验证器地址
    public fun remove_validator(
        validator_set: &mut ValidatorSet,
        _stake_manager: &StakeManager,
        validator: address,
        ctx: &mut TxContext
    ) {
        // 验证调用者是管理员
        assert!(types::get_admin(validator_set) == tx_context::sender(ctx), EINVALID_ADMIN);
        
        // 验证是否是验证者
        assert!(types::is_validator(validator_set, validator), EINVALID_VALIDATOR);

        // 紧急移除验证者
        types::emergency_remove_validator(validator_set, validator);
    }

    /// 更新验证器权重
    /// * `validator_set` - 验证器集合
    /// * `validator` - 目标验证器地址
    /// * `weight` - 新的权重值
    public fun update_validator_weight(
        validator_set: &mut ValidatorSet,
        _stake_manager: &StakeManager,
        validator: address,
        weight: u64,
        ctx: &mut TxContext
    ) {
        // 验证调用者是管理员
        assert!(types::get_admin(validator_set) == tx_context::sender(ctx), EINVALID_ADMIN);
        
        // 验证是否是验证者
        assert!(types::is_validator(validator_set, validator), EINVALID_VALIDATOR);

        // 更新权重
        types::update_validator_weight(validator_set, validator, weight);
    }

    // === 共识相关函数 ===
    /// 记录验证器对消息的验证
    /// * `validator_set` - 验证器集合
    /// * `validator` - 执行验证的验证器地址
    /// * `msg_hash` - 被验证的消息哈希
    public fun record_validation(
        validator_set: &mut ValidatorSet,
        validator: address,
        _msg_hash: &vector<u8>
    ) {
        // 验证是否是验证者
        assert!(types::is_validator(validator_set, validator), EINVALID_VALIDATOR);
    }

    /// 检查是否达到共识
    /// * `validator_set` - 验证器集合
    /// * `msg_hash` - 消息哈希
    /// 返回：是否达到共识要求
    public fun has_consensus(
        validator_set: &ValidatorSet,
        _msg_hash: &vector<u8>
    ): bool {
        // 简单实现：至少需要2个验证器才能达成共识
        types::get_validator_count(validator_set) >= 2
    }

    // === 权限检查函数 ===
    /// 检查账户是否有暂停系统的权限
    public fun can_pause(validator_set: &ValidatorSet, account: address): bool {
        types::get_admin(validator_set) == account
    }

    /// 检查账户是否有更新权重的权限
    public fun can_update_weight(
        validator_set: &ValidatorSet,
        account: address,
        _target: address
    ): bool {
        types::get_admin(validator_set) == account
    }

    // === 查询函数 ===
    /// 检查地址是否是验证器
    public fun is_validator(validator_set: &ValidatorSet, validator: address): bool {
        types::is_validator(validator_set, validator)
    }

    /// 获取验证器总数
    public fun get_validator_count(validator_set: &ValidatorSet): u64 {
        types::get_validator_count(validator_set)
    }

    /// 获取验证器的权重
    public fun get_validator_weight(validator_set: &ValidatorSet, validator: address): u64 {
        types::get_validator_weight(validator_set, validator)
    }

    /// 获取共识所需的阈值
    /// 返回：达成共识所需的最小总权重(总权重的2/3)
    public fun get_threshold(validator_set: &ValidatorSet): u64 {
        // 返回2/3多数要求的阈值
        let total_weight = get_total_weight(validator_set);
        if (total_weight == 0) {
            0
        } else {
            ((total_weight * 2) / 3) // 需要2/3的权重才能达成共识
        }
    }

    /// 获取所有验证器的总权重
    public fun get_total_weight(validator_set: &ValidatorSet): u64 {
        types::get_total_validator_weight(validator_set)
    }

    /// 获取验证器的公钥
    public fun get_validator_public_key(validator_set: &ValidatorSet, validator: address): vector<u8> {
        types::get_validator_public_key(validator_set, validator)
    }

    // === 内部函数 ===
    /// 根据质押金额计算验证器权重
    /// * `stake_amount` - 质押的SUI代币数量
    /// 返回：计算得出的权重值
    fun calculate_weight(stake_amount: u64): u64 {
        // 权重计算规则：每1000 SUI(1000_000_000_000 MIST)对应1个权重点
        stake_amount / 1000_000_000 // 1000 SUI = 1 权重点
    }
} 