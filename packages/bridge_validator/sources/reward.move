/// 奖励和惩罚管理模块
/// 本模块负责处理验证器的奖励和惩罚机制，包括：
/// 1. 奖励的分配和领取
/// 2. 验证器的惩罚机制
/// 3. 性能评分相关的奖惩
module bridge_validator::reward {
    use sui::object::{Self, UID};
    use sui::table;
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::event;
    use sui::transfer;
    use bridge_validator::types::{Self, RewardPool, StakeManager, ValidatorSet};
    use bridge_validator::security;
    use bridge_validator::stake;
    use std::vector;

    // === 错误码定义 ===
    /// 当奖励金额无效（为0或过大）时抛出
    const EINVALID_REWARD_AMOUNT: u64 = 1;
    /// 当奖励分配参数无效时抛出
    const EINVALID_DISTRIBUTION: u64 = 2;
    /// 当没有可用奖励时抛出
    const ENO_REWARDS: u64 = 3;
    /// 当操作的验证器无效时抛出
    const EINVALID_VALIDATOR: u64 = 4;
    /// 当奖励分配间隔过短时抛出
    const EDISTRIBUTION_TOO_FREQUENT: u64 = 5;
    /// 当惩罚金额无效时抛出
    const EINVALID_SLASH_AMOUNT: u64 = 6;
    /// 当惩罚比例超过最大限制时抛出
    const ESLASH_TOO_LARGE: u64 = 7;
    /// 当非管理员尝试执行管理员操作时抛出
    const ENOT_ADMIN: u64 = 8;

    // === 系统常量定义 ===
    /// 测试环境的最小分配间隔：10个epoch
    #[test_only]
    const MIN_DISTRIBUTION_INTERVAL: u64 = 10;
    /// 测试环境的最小分配间隔（用于测试）
    #[test_only]
    const TEST_MIN_DISTRIBUTION_INTERVAL: u64 = 10;
    /// 基础年化奖励率：5%
    const BASE_REWARD_RATE: u64 = 5;
    /// 性能奖励倍率：2%（基于基础奖励）
    const PERFORMANCE_BONUS_RATE: u64 = 2;
    /// 最大惩罚比例：30%（占质押金额）
    const MAX_SLASH_PERCENTAGE: u64 = 30;
    /// 离线惩罚比例：5%（占质押金额）
    const OFFLINE_SLASH_RATE: u64 = 5;
    /// 恶意行为惩罚比例：30%（占质押金额）
    const MALICIOUS_SLASH_RATE: u64 = 30;
    /// 错过验证惩罚比例：10%（占质押金额）
    const MISSED_VALIDATION_SLASH_RATE: u64 = 10;

    // === 惩罚原因定义 ===
    /// 验证器离线
    const SLASH_REASON_OFFLINE: u8 = 1;
    /// 验证器恶意行为
    const SLASH_REASON_MALICIOUS: u8 = 2;
    /// 验证器错过验证
    const SLASH_REASON_MISSED_VALIDATION: u8 = 3;

    // === 事件定义 ===
    /// 奖励分配事件
    /// 当验证器获得奖励时触发
    public struct RewardDistributedEvent has copy, drop {
        /// 获得奖励的验证器地址
        validator: address,
        /// 奖励金额
        amount: u64,
        /// 分配时间戳
        timestamp: u64
    }

    /// 验证器惩罚事件
    /// 当验证器被惩罚时触发
    public struct ValidatorSlashedEvent has copy, drop {
        /// 被惩罚的验证器地址
        validator: address,
        /// 惩罚金额
        amount: u64,
        /// 惩罚原因（1:离线, 2:恶意行为, 3:错过验证）
        reason: u8,
        /// 惩罚时间戳
        timestamp: u64
    }

    // === 初始化函数 ===
    /// 初始化奖励池
    /// 创建一个新的奖励池实例
    fun init(ctx: &mut TxContext) {
        types::new_reward_pool(ctx)
    }

    #[test_only]
    public fun init_for_test(ctx: &mut TxContext) {
        init(ctx)
    }

    // === 奖励管理函数 ===
    /// 向奖励池添加奖励
    /// * `pool` - 奖励池
    /// * `coin` - 要添加的SUI代币
    public fun add_rewards(
        pool: &mut RewardPool,
        coin: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        let amount = coin::value(&coin);
        assert!(amount > 0, EINVALID_REWARD_AMOUNT);

        // 将SUI代币转入奖励池
        let balance = coin::into_balance(coin);
        types::add_rewards_balance(pool, balance);
    }

    /// 分配奖励给验证器
    /// * `pool` - 奖励池
    /// * `stake_manager` - 质押管理器
    /// * `validator_set` - 验证器集合
    /// 根据质押量和性能评分计算并分配奖励
    public fun distribute_rewards(
        pool: &mut RewardPool,
        stake_manager: &StakeManager,
        validator_set: &ValidatorSet,
        ctx: &mut TxContext
    ) {
        // 验证调用者是否为管理员
        verify_admin(validator_set, ctx);
        
        // 检查距离上次分配是否达到最小间隔（10个epoch）
        let current_time = tx_context::epoch(ctx);
        assert!(
            current_time >= types::get_last_distribution(pool) + MIN_DISTRIBUTION_INTERVAL,
            EDISTRIBUTION_TOO_FREQUENT
        );
        
        // 确保奖励池中有可分配的奖励
        assert!(types::get_total_rewards(pool) > 0, ENO_REWARDS);
        
        // 确保系统中有质押的验证器
        let total_stake = types::get_total_stake(stake_manager);
        assert!(total_stake > 0, EINVALID_DISTRIBUTION);
        
        // 遍历所有活跃验证器分配奖励
        let validators = types::get_active_validators(validator_set);
        let mut i = 0;
        let len = vector::length(&validators);
        
        while (i < len) {
            let validator = *vector::borrow(&validators, i);
            
            // 计算验证器的奖励
            let (stake_amount, performance_score, is_active) = types::get_stake_info(stake_manager, validator);
            if (is_active) {
                // 基础奖励 = (质押量 * 总奖励 * 奖励率) / (总质押量 * 100)
                let reward_rate = types::get_reward_rate(validator_set);
                let base_reward = (stake_amount * types::get_total_rewards(pool) * reward_rate) / (total_stake * 100);
                // 性能奖励 = 基础奖励 * 性能评分 * 性能奖励率 / (100 * 100)
                let performance_bonus = (base_reward * performance_score * PERFORMANCE_BONUS_RATE) / (100 * 100);
                let total_reward = base_reward + performance_bonus;
                
                // 记录验证器的奖励
                types::update_validator_rewards(pool, validator, total_reward);
                
                // 发送奖励分配事件
                event::emit(RewardDistributedEvent {
                    validator,
                    amount: total_reward,
                    timestamp: current_time
                });
            };
            i = i + 1;
        };
        
        // 更新最后一次分配时间
        types::update_last_distribution(pool, current_time);
    }

    /// 领取验证器奖励
    /// * `pool` - 奖励池
    /// * `validator_set` - 验证器集合
    /// 返回：包含奖励的SUI代币
    public fun claim_rewards(
        pool: &mut RewardPool,
        validator_set: &ValidatorSet,
        ctx: &mut TxContext
    ): Coin<SUI> {
        let validator = tx_context::sender(ctx);
        
        // 验证调用者是否为验证器
        assert!(
            types::is_validator(validator_set, validator),
            EINVALID_VALIDATOR
        );
        
        // 检查是否有可领取的奖励
        let reward_amount = types::get_validator_rewards(pool, validator);
        assert!(reward_amount > 0, ENO_REWARDS);
        
        // 清除验证器的奖励记录
        types::clear_validator_rewards(pool, validator);
        
        // 从奖励池提取SUI代币
        let balance = types::withdraw_rewards(pool, reward_amount);
        coin::from_balance(balance, ctx)
    }

    // === 查询函数 ===
    /// 获取验证器待领取的奖励金额
    public fun get_pending_rewards(
        pool: &RewardPool,
        validator: address
    ): u64 {
        types::get_validator_rewards(pool, validator)
    }

    /// 获取奖励池中的总奖励金额
    public fun get_total_rewards(pool: &RewardPool): u64 {
        types::get_total_rewards(pool)
    }

    /// 获取上次奖励分配的时间
    public fun get_last_distribution(pool: &RewardPool): u64 {
        types::get_last_distribution(pool)
    }

    // === 惩罚管理函数 ===
    /// 惩罚验证器
    /// * `pool` - 奖励池
    /// * `stake_manager` - 质押管理器
    /// * `validator_set` - 验证器集合
    /// * `validator` - 要惩罚的验证器地址
    /// * `slash_reason` - 惩罚原因（1:离线, 2:恶意行为, 3:错过验证）
    public fun slash_validator(
        pool: &mut RewardPool,
        stake_manager: &mut StakeManager,
        validator_set: &ValidatorSet,
        validator: address,
        slash_reason: u8,
        ctx: &mut TxContext
    ) {
        // 验证调用者是否为管理员
        verify_admin(validator_set, ctx);
        
        // 验证目标验证器状态
        let (stake_amount, _, is_active) = types::get_stake_info(stake_manager, validator);
        assert!(is_active, EINVALID_VALIDATOR);
        
        // 根据惩罚原因确定惩罚比例
        let slash_rate = if (slash_reason == SLASH_REASON_OFFLINE) {
            OFFLINE_SLASH_RATE // 离线惩罚：5%
        } else if (slash_reason == SLASH_REASON_MALICIOUS) {
            MALICIOUS_SLASH_RATE // 恶意行为惩罚：30%
        } else if (slash_reason == SLASH_REASON_MISSED_VALIDATION) {
            MISSED_VALIDATION_SLASH_RATE // 错过验证惩罚：10%
        } else {
            abort EINVALID_SLASH_AMOUNT
        };
        
        // 验证惩罚比例不超过系统设置的最大值
        let max_slash_rate = types::get_slash_rate(validator_set);
        assert!(slash_rate <= max_slash_rate, ESLASH_TOO_LARGE);
        
        // 计算惩罚金额（惩罚比例 * 质押金额）
        let slash_amount = (stake_amount * slash_rate) / 100;
        assert!(slash_amount > 0, EINVALID_SLASH_AMOUNT);
        
        // 更新验证器的质押信息
        let stake_info = types::borrow_stake_mut(stake_manager, validator);
        types::set_stake_amount(stake_info, stake_amount - slash_amount);
        types::set_stake_active(stake_info, false); // 设置验证器为非活跃状态
        types::decrease_total_stake(stake_manager, slash_amount);
        
        // 将惩罚金额添加到奖励池
        types::add_total_rewards(pool, slash_amount);
        
        // 发送验证器惩罚事件
        event::emit(ValidatorSlashedEvent {
            validator,
            amount: slash_amount,
            reason: slash_reason,
            timestamp: tx_context::epoch(ctx)
        });
    }

    // === 性能惩罚函数 ===
    /// 处理性能过低的验证器
    /// * `pool` - 奖励池
    /// * `stake_manager` - 质押管理器
    /// * `validator_set` - 验证器集合
    /// * `validator` - 目标验证器地址
    public fun punish_low_performance(
        pool: &mut RewardPool,
        stake_manager: &mut StakeManager,
        validator_set: &ValidatorSet,
        validator: address,
        ctx: &mut TxContext
    ) {
        let (_, performance_score, is_active) = types::get_stake_info(stake_manager, validator);
        
        // 如果验证器活跃且性能评分低于最低要求，执行惩罚
        if (is_active && performance_score < types::get_min_performance_score()) {
            slash_validator(
                pool,
                stake_manager,
                validator_set,
                validator,
                SLASH_REASON_OFFLINE, // 使用离线惩罚率（5%）
                ctx
            );
        }
    }

    // === 批量惩罚函数 ===
    /// 批量惩罚验证器
    /// * `pool` - 奖励池
    /// * `stake_manager` - 质押管理器
    /// * `validator_set` - 验证器集合
    /// * `validators` - 要惩罚的验证器地址列表
    /// * `reasons` - 惩罚原因列表
    public fun batch_slash_validators(
        pool: &mut RewardPool,
        stake_manager: &mut StakeManager,
        validator_set: &ValidatorSet,
        validators: vector<address>,
        reasons: vector<u8>,
        ctx: &mut TxContext
    ) {
        let mut i = 0;
        let len = vector::length(&validators);
        assert!(len == vector::length(&reasons), EINVALID_SLASH_AMOUNT);
        
        while (i < len) {
            let validator = *vector::borrow(&validators, i);
            let reason = *vector::borrow(&reasons, i);
            
            if (stake::is_active(stake_manager, validator)) {
                slash_validator(
                    pool,
                    stake_manager,
                    validator_set,
                    validator,
                    reason,
                    ctx
                );
            };
            i = i + 1;
        }
    }

    // === 新增查询函数 ===
    public fun get_slash_rate(slash_reason: u8): u64 {
        if (slash_reason == SLASH_REASON_OFFLINE) {
            OFFLINE_SLASH_RATE
        } else if (slash_reason == SLASH_REASON_MALICIOUS) {
            MALICIOUS_SLASH_RATE
        } else if (slash_reason == SLASH_REASON_MISSED_VALIDATION) {
            MISSED_VALIDATION_SLASH_RATE
        } else {
            0
        }
    }

    // === 安全检查函数 ===
    fun verify_admin(validator_set: &ValidatorSet, ctx: &TxContext) {
        let sender = tx_context::sender(ctx);
        assert!(types::get_admin(validator_set) == sender, ENOT_ADMIN);
    }
} 