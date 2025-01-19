/// 治理模块
/// 本模块负责处理验证器系统的治理功能，包括：
/// 1. 提案的创建和投票
/// 2. 系统参数的更新
/// 3. 紧急操作的执行
/// 4. 合约升级的管理
module bridge_validator::governance {
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::event;
    use sui::address;
    use bridge_validator::types::{Self, ValidatorSet, StakeManager, RewardPool, Proposal};
    use std::vector;

    // === 错误码定义 ===
    /// 当提案无效或格式错误时抛出
    const EINVALID_PROPOSAL: u64 = 1;
    /// 当投票无效或重复投票时抛出
    const EINVALID_VOTE: u64 = 2;
    /// 当尝试执行已执行的提案时抛出
    const EPROPOSAL_ALREADY_EXECUTED: u64 = 3;
    /// 当提案未获得足够投票时抛出
    const EINSUFFICIENT_VOTES: u64 = 4;
    /// 当提案已过期时抛出
    const EPROPOSAL_EXPIRED: u64 = 5;

    // === 系统常量定义 ===
    /// 系统参数更新提案类型
    const PROPOSAL_TYPE_PARAMETER: u8 = 1;
    /// 合约升级提案类型
    const PROPOSAL_TYPE_UPGRADE: u8 = 2;
    /// 紧急操作提案类型
    const PROPOSAL_TYPE_EMERGENCY: u8 = 3;
    /// 提案有效期：7天（以秒为单位）
    const PROPOSAL_EXPIRATION_TIME: u64 = 7 * 24 * 60 * 60; // 7天 = 7 * 24小时 * 60分钟 * 60秒

    // === 事件定义 ===
    /// 提案创建事件
    /// 当新的提案被创建时触发
    public struct ProposalCreatedEvent has copy, drop {
        /// 提案的唯一标识符
        proposal_id: object::ID,
        /// 提案创建者地址
        proposer: address,
        /// 提案类型（1:参数更新, 2:合约升级, 3:紧急操作）
        proposal_type: u8
    }

    // === 公共函数 ===
    /// 创建新的提案
    /// * `validator_set` - 验证器集合
    /// * `proposal_type` - 提案类型（1:参数更新, 2:合约升级, 3:紧急操作）
    /// * `params` - 提案参数的字节序列
    public entry fun create_proposal(
        validator_set: &ValidatorSet,
        proposal_type: u8,
        params: vector<u8>,
        ctx: &mut TxContext
    ) {
        // 验证调用者是否为验证器
        assert!(types::is_validator(validator_set, tx_context::sender(ctx)), EINVALID_PROPOSAL);
        
        // 验证提案类型是否有效
        assert!(
            proposal_type == PROPOSAL_TYPE_PARAMETER || 
            proposal_type == PROPOSAL_TYPE_UPGRADE || 
            proposal_type == PROPOSAL_TYPE_EMERGENCY,
            EINVALID_PROPOSAL
        );
        
        // 通过types模块创建新提案
        let proposal = types::new_proposal(
            tx_context::sender(ctx),
            proposal_type,
            params,
            ctx
        );

        // 发送提案创建事件
        event::emit(ProposalCreatedEvent {
            proposal_id: object::id(&proposal),
            proposer: tx_context::sender(ctx),
            proposal_type
        });

        // 将提案对象转移给创建者
        sui::transfer::public_transfer(proposal, tx_context::sender(ctx));
    }

    /// 对提案进行投票
    /// * `validator_set` - 验证器集合
    /// * `proposal` - 提案对象
    /// * `vote` - 投票选择（true表示赞成，false表示反对）
    public entry fun vote_on_proposal(
        validator_set: &ValidatorSet,
        proposal: &mut Proposal,
        vote: bool,
        ctx: &mut TxContext
    ) {
        let validator = tx_context::sender(ctx);
        
        // 验证调用者是否为验证器
        assert!(types::is_validator(validator_set, validator), EINVALID_PROPOSAL);
        
        // 验证提案是否在有效期内
        assert!(!is_proposal_expired(proposal, ctx), EPROPOSAL_EXPIRED);
        
        // 添加投票记录
        types::add_vote(proposal, validator, vote);
    }

    /// 执行已通过的提案
    /// * `validator_set` - 验证器集合
    /// * `proposal` - 提案对象
    public entry fun execute_proposal(
        validator_set: &mut ValidatorSet,
        proposal: &mut Proposal,
        ctx: &mut TxContext
    ) {
        // 验证提案是否在有效期内
        assert!(!is_proposal_expired(proposal, ctx), EPROPOSAL_EXPIRED);
        
        // 验证提案是否已被执行
        assert!(!types::is_proposal_executed(proposal), EPROPOSAL_ALREADY_EXECUTED);

        // 计算所需的投票数（2/3多数+1）
        let total_validators = types::get_validator_count(validator_set);
        let required_votes = (total_validators * 2) / 3 + 1;
        
        // 验证是否获得足够的投票
        assert!(types::get_vote_count(proposal) >= required_votes, EINSUFFICIENT_VOTES);

        // 根据提案类型执行相应操作
        let proposal_type = types::get_proposal_type(proposal);
        let params = types::get_proposal_params(proposal);
        
        if (proposal_type == PROPOSAL_TYPE_PARAMETER) {
            execute_parameter_update(validator_set, params);
        } else if (proposal_type == PROPOSAL_TYPE_UPGRADE) {
            execute_upgrade(validator_set, params);
        } else if (proposal_type == PROPOSAL_TYPE_EMERGENCY) {
            execute_emergency_action(validator_set, params);
        };

        // 标记提案为已执行
        types::set_proposal_executed(proposal, true);
    }

    // === 内部函数 ===
    /// 检查提案是否已过期
    /// * `proposal` - 提案对象
    /// * `ctx` - 交易上下文
    /// 返回：如果提案已过期则返回true
    fun is_proposal_expired(proposal: &Proposal, ctx: &TxContext): bool {
        tx_context::epoch(ctx) > types::get_proposal_creation_time(proposal) + PROPOSAL_EXPIRATION_TIME
    }

    /// 执行参数更新提案
    /// * `validator_set` - 验证器集合
    /// * `params` - 参数更新的字节序列
    /// 参数格式：[参数类型(1字节), 参数值(8字节)]
    /// 参数类型：1=最小质押量, 2=奖励率, 3=惩罚率, 4=阈值
    fun execute_parameter_update(
        validator_set: &mut ValidatorSet,
        params: vector<u8>
    ) {
        // 验证参数长度（1字节类型 + 8字节值 = 9字节）
        assert!(vector::length(&params) == 9, EINVALID_PROPOSAL);
        
        // 获取参数类型（第1个字节）
        let param_type = *vector::borrow(&params, 0);
        
        // 获取参数值（后8个字节）
        let mut param_bytes = vector::empty();
        let mut i = 1;
        while (i < vector::length(&params)) {
            vector::push_back(&mut param_bytes, *vector::borrow(&params, i));
            i = i + 1;
        };
        let param_value = deserialize_u64(param_bytes);

        // 根据参数类型更新相应的系统参数
        if (param_type == 1) {
            types::update_min_stake(validator_set, param_value);
        } else if (param_type == 2) {
            types::update_reward_rate(validator_set, param_value);
        } else if (param_type == 3) {
            types::update_slash_rate(validator_set, param_value);
        } else if (param_type == 4) {
            types::update_threshold(validator_set, param_value);
        } else {
            assert!(false, EINVALID_PROPOSAL); // 无效的参数类型
        };
    }

    /// 执行合约升级提案
    /// * `validator_set` - 验证器集合
    /// * `params` - 升级参数的字节序列
    /// 参数格式：[升级类型(1字节), 升级数据(变长)]
    /// 升级类型：1=合约升级, 2=系统配置更新
    fun execute_upgrade(validator_set: &mut ValidatorSet, params: vector<u8>) {
        assert!(vector::length(&params) >= 1, EINVALID_PROPOSAL);
        let upgrade_type = *vector::borrow(&params, 0);
        let mut upgrade_bytes = vector::empty();
        let mut i = 1;
        while (i < vector::length(&params)) {
            vector::push_back(&mut upgrade_bytes, *vector::borrow(&params, i));
            i = i + 1;
        };

        if (upgrade_type == 1) {
            types::trigger_contract_upgrade(validator_set, upgrade_bytes);
        } else if (upgrade_type == 2) {
            types::update_system_config(validator_set, upgrade_bytes);
        };
    }

    /// 执行紧急操作提案
    /// * `validator_set` - 验证器集合
    /// * `params` - 操作参数的字节序列
    /// 参数格式：[操作类型(1字节), 操作数据(变长)]
    /// 操作类型：1=暂停系统, 2=恢复系统, 3=移除验证器
    fun execute_emergency_action(validator_set: &mut ValidatorSet, params: vector<u8>) {
        assert!(vector::length(&params) >= 1, EINVALID_PROPOSAL);
        let action_type = *vector::borrow(&params, 0);

        if (action_type == 1) {
            types::emergency_pause(validator_set);
        } else if (action_type == 2) {
            types::emergency_unpause(validator_set);
        } else if (action_type == 3) {
            // 验证参数长度（1字节操作类型 + 32字节验证器地址）
            assert!(vector::length(&params) == 33, EINVALID_PROPOSAL);
            let mut validator_bytes = vector::empty();
            let mut i = 1;
            while (i < vector::length(&params)) {
                vector::push_back(&mut validator_bytes, *vector::borrow(&params, i));
                i = i + 1;
            };
            let validator = address::from_bytes(validator_bytes);
            types::emergency_remove_validator(validator_set, validator);
        };
    }

    /// 将字节序列反序列化为u64类型（小端序）
    /// * `bytes` - 要反序列化的字节序列（必须是8字节）
    /// 返回：反序列化后的u64值
    fun deserialize_u64(bytes: vector<u8>): u64 {
        // 验证输入必须是8字节
        assert!(vector::length(&bytes) == 8, EINVALID_PROPOSAL);
        
        let mut value = 0u64;
        let mut i = 0;
        while (i < 8) {
            value = value | ((*vector::borrow(&bytes, i) as u64) << ((i * 8) as u8));
            i = i + 1;
        };
        value
    }
} 