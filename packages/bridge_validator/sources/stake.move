/// 质押管理模块
/// 本模块负责管理验证器的质押操作，包括：
/// 1. 质押和解质押SUI代币
/// 2. 验证器性能评分管理
/// 3. 质押状态的维护和查询
#[test_only]
module bridge_validator::stake {
    use sui::object::{Self, UID};
    use sui::table;
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::event;
    use sui::transfer;
    use bridge_validator::types::{Self, StakeManager, StakeInfo};
    use bridge_validator::security;

    // === 错误码定义 ===
    /// 当质押金额小于最小要求时抛出
    const EINVALID_STAKE_AMOUNT: u64 = 1;
    /// 当解质押金额大于已质押金额时抛出
    const EINVALID_UNSTAKE_AMOUNT: u64 = 2;
    /// 当性能评分超出有效范围时抛出
    const EINVALID_PERFORMANCE_SCORE: u64 = 3;
    /// 当查询的质押记录不存在时抛出
    const ESTAKE_NOT_FOUND: u64 = 4;
    /// 当尝试重复创建质押记录时抛出
    const ESTAKE_ALREADY_EXISTS: u64 = 5;
    /// 当质押金额不足以执行操作时抛出
    const EINSUFFICIENT_STAKE: u64 = 6;

    // === 系统常量定义 ===
    /// 最低性能评分要求：60分
    const MIN_PERFORMANCE_SCORE: u64 = 60;
    /// 最高性能评分上限：100分
    const MAX_PERFORMANCE_SCORE: u64 = 100;
    /// 默认初始性能评分：80分
    const DEFAULT_PERFORMANCE_SCORE: u64 = 80;

    /// 获取默认性能评分（仅用于测试）
    #[test_only]
    public fun get_default_performance_score(): u64 {
        DEFAULT_PERFORMANCE_SCORE
    }

    // === 事件定义 ===
    /// 质押事件
    /// 当验证器进行质押或解质押操作时触发
    public struct StakeEvent has copy, drop {
        /// 验证器地址
        validator: address,
        /// 操作涉及的金额
        amount: u64,
        /// 操作后的总质押量
        total_stake: u64
    }

    // === 初始化函数 ===
    /// 初始化质押管理器
    /// 创建一个新的质押管理器实例
    fun init(ctx: &mut TxContext) {
        types::new_stake_manager(ctx)
    }

    #[test_only]
    public fun init_for_test(ctx: &mut TxContext) {
        init(ctx)
    }
    
    // === 质押管理函数 ===
    /// 质押SUI代币
    /// * `manager` - 质押管理器
    /// * `coin` - 要质押的SUI代币
    /// 验证器可以通过质押SUI代币来参与验证过程
    public fun stake(
        manager: &mut StakeManager,
        coin: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        let validator = tx_context::sender(ctx);
        let amount = coin::value(&coin);

        // 验证质押金额是否达到最小要求
        assert!(amount >= types::get_min_stake(manager), EINVALID_STAKE_AMOUNT);

        // 将SUI代币存入质押金库
        types::deposit_to_vault(manager, coin);

        // 更新或创建验证器的质押信息
        if (types::contains_stake(manager, validator)) {
            let stake_info = types::borrow_stake_mut(manager, validator);
            let current_amount = types::get_stake_amount(stake_info);
            types::set_stake_amount(stake_info, current_amount + amount);
            types::set_last_update(stake_info, tx_context::epoch(ctx));
        } else {
            // 创建新的质押信息，初始性能评分为80分
            let stake_info = types::new_stake_info(
                amount,
                DEFAULT_PERFORMANCE_SCORE, // 初始性能评分：80分
                true, // 初始状态为活跃
                tx_context::epoch(ctx)
            );
            types::add_stake(manager, validator, stake_info);
        };

        // 更新系统总质押量
        types::increase_total_stake(manager, amount);

        // 发出质押事件通知
        event::emit(StakeEvent {
            validator,
            amount,
            total_stake: types::get_total_stake(manager)
        });
    }

    /// 解质押SUI代币
    /// * `manager` - 质押管理器
    /// * `amount` - 要解质押的金额
    /// * `lock` - 时间锁定证明
    /// 验证器可以在满足时间锁定条件时取回质押的SUI代币
    public fun unstake(
        manager: &mut StakeManager,
        amount: u64,
        lock: &types::TimeLock,
        ctx: &mut TxContext
    ) {
        let validator = tx_context::sender(ctx);
        
        // 验证时间锁是否已到期且操作类型正确
        assert!(types::is_timelock_expired(lock, ctx), 0);
        assert!(types::get_timelock_action_type(lock) == security::get_unstake_action_type(), 0);
        
        // 验证质押记录是否存在
        assert!(types::contains_stake(manager, validator), ESTAKE_NOT_FOUND);
        
        // 获取系统最小质押要求
        let min_stake = types::get_min_stake(manager);
        
        // 验证并更新质押信息
        let current_stake = {
            let stake_info = types::borrow_stake_mut(manager, validator);
            let current_amount = types::get_stake_amount(stake_info);
            
            // 验证解质押金额不超过已质押金额
            assert!(amount <= current_amount, EINVALID_UNSTAKE_AMOUNT);
            
            // 更新质押信息
            types::set_stake_amount(stake_info, current_amount - amount);
            types::set_last_update(stake_info, tx_context::epoch(ctx));
            
            // 如果剩余质押金额低于最小要求，将状态设置为非活跃
            if (current_amount - amount < min_stake) {
                types::set_stake_active(stake_info, false);
            };

            current_amount - amount
        };
        
        // 更新系统总质押量
        let new_total_stake = types::decrease_total_stake(manager, amount);
        
        // 从质押金库提取SUI代币并转给验证器
        let unstake_coin = types::withdraw_from_vault(manager, amount, ctx);
        transfer::public_transfer(unstake_coin, validator);
        
        // 发出解质押事件通知
        event::emit(StakeEvent {
            validator,
            amount: current_stake,
            total_stake: new_total_stake
        });
    }

    // === 性能管理函数 ===
    /// 更新验证器的性能评分
    /// * `manager` - 质押管理器
    /// * `validator` - 目标验证器地址
    /// * `score` - 新的性能评分（0-100）
    public fun update_performance(
        manager: &mut StakeManager,
        validator: address,
        score: u64,
        ctx: &mut TxContext
    ) {
        // 验证性能评分不超过100分
        assert!(score <= MAX_PERFORMANCE_SCORE, EINVALID_PERFORMANCE_SCORE);
        
        // 更新验证器的性能评分
        if (types::contains_stake(manager, validator)) {
            let stake_info = types::borrow_stake_mut(manager, validator);
            types::set_performance_score(stake_info, score);
            types::set_last_update(stake_info, tx_context::epoch(ctx));
            
            // 如果性能评分低于60分，将状态设置为非活跃
            if (score < MIN_PERFORMANCE_SCORE) {
                types::set_stake_active(stake_info, false);
            };
        };
    }

    // === 查询函数 ===
    /// 获取验证器的质押信息
    /// * `manager` - 质押管理器
    /// * `validator` - 验证器地址
    /// 返回：(质押金额, 性能评分, 是否活跃, 最后更新时间)
    public fun get_stake(
        manager: &StakeManager,
        validator: address
    ): (u64, u64, bool, u64) {
        assert!(types::contains_stake(manager, validator), ESTAKE_NOT_FOUND);
        let info = types::borrow_stake(manager, validator);
        (
            types::get_stake_amount(info),
            types::get_performance_score(info),
            types::is_stake_active(info),
            types::get_last_update(info)
        )
    }

    /// 获取系统总质押量
    public fun get_total_stake(manager: &StakeManager): u64 {
        types::get_total_stake(manager)
    }

    /// 检查验证器是否处于活跃状态
    /// 验证器必须同时满足：
    /// 1. 质押状态为活跃
    /// 2. 质押金额不低于最小要求
    /// 3. 性能评分不低于60分
    public fun is_active(manager: &StakeManager, validator: address): bool {
        if (types::contains_stake(manager, validator)) {
            let info = types::borrow_stake(manager, validator);
            types::is_stake_active(info) && 
            types::get_stake_amount(info) >= types::get_min_stake(manager) && 
            types::get_performance_score(info) >= MIN_PERFORMANCE_SCORE
        } else {
            false
        }
    }
} 