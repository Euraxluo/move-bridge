/// Bridge Validator 类型模块
/// 本模块定义了跨链验证器系统中使用的所有核心数据结构和类型
/// 包括验证器集合、质押管理、奖励池、跨链消息等基础组件
#[allow(lint_allow_modules_with_public_structs)]
module bridge_validator::types {
    use sui::object::{Self, ID, UID};
    use sui::table::{Self, Table};
    use sui::vec_set::{Self, VecSet};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer::{Self};
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use std::option::Option;
    use std::vector;

    // === 错误码定义 ===
    /// 当设置的阈值无效时抛出
    const EINVALID_THRESHOLD: u64 = 1;
    /// 当验证器权重设置无效时抛出
    const EINVALID_WEIGHT: u64 = 2;
    /// 当金额设置无效时抛出
    const EINVALID_AMOUNT: u64 = 3;
    /// 当验证器地址无效时抛出
    const EINVALID_VALIDATOR: u64 = 4;

    // === 核心数据结构 ===
    /// 验证器集合
    /// 存储所有活跃验证器的信息，包括地址、权重、公钥等
    public struct ValidatorSet has key {
        id: UID,
        /// 验证器地址集合
        validators: VecSet<address>,
        /// 验证器权重映射表
        weights: Table<address, u64>,
        /// 验证器公钥映射表
        public_keys: Table<address, vector<u8>>,
        /// 验证阈值：需要达到多少权重才能通过验证
        threshold: u64,
        /// 管理员地址
        admin: address,
        /// 是否暂停系统
        paused: bool,
        /// 合约版本号
        contract_version: u64,
        // === 系统配置参数 ===
        /// 最小质押量: 1 SUI = 1000000000
        min_stake: u64,
        /// 奖励率: 5%
        reward_rate: u64,
        /// 惩罚率: 10%
        slash_rate: u64
    }

    /// 质押管理器
    /// 管理验证器的质押、解质押和相关的性能评分
    public struct StakeManager has key {
        id: UID,
        /// 最小质押量: 1 SUI = 1000000000
        min_stake: u64,
        /// 总质押量
        total_stake: u64,
        /// 验证器质押信息映射表
        stakes: Table<address, StakeInfo>,
        /// 验证器性能评分映射表
        performance_scores: Table<address, u64>,
        /// 质押金库
        vault: Balance<SUI>
    }

    /// 质押信息
    public struct StakeInfo has store {
        /// 质押数量
        amount: u64,
        /// 性能评分
        performance_score: u64,
        /// 是否处于活跃状态
        is_active: bool,
        /// 最后更新时间
        last_update: u64
    }

    /// 奖励池
    /// 管理验证器的奖励分配
    public struct RewardPool has key, store {
        id: UID,
        /// 验证器奖励映射表
        rewards: Table<address, u64>,
        /// 总奖励量
        total_rewards: u64,
        /// 上次分配时间
        last_distribution: u64,
        /// 奖励率: 5%
        reward_rate: u64,
        /// 惩罚率: 10%
        slash_rate: u64,
        /// 奖励金库
        vault: Balance<SUI>
    }

    public struct CrossChainMessage has key, store {
        id: UID,
        source_tx_id: ID,
        locked_asset_id: Option<ID>,
        sequence: u64,
        payload: vector<u8>,
        verified: bool,
        timestamp: u64
    }

    public struct MessageVerification has key {
        id: UID,
        message_id: ID,
        validator_signatures: Table<address, vector<u8>>,
        verification_count: u64
    }

    public struct Proposal has key, store {
        id: UID,
        proposer: address,
        proposal_type: u8,
        params: vector<u8>,
        votes: Table<address, bool>,
        vote_count: u64,
        executed: bool,
        creation_time: u64
    }

    public struct TimeLock has key {
        id: UID,
        target: address,
        unlock_time: u64,
        action_type: u8
    }

    // === 事件结构 ===
    public struct ValidatorAddedEvent has copy, drop {
        validator: address,
        weight: u64,
        stake_amount: u64
    }

    public struct ValidatorRemovedEvent has copy, drop {
        validator: address
    }

    public struct StakeUpdatedEvent has copy, drop {
        validator: address,
        new_amount: u64,
        total_stake: u64
    }

    public struct MessageVerifiedEvent has copy, drop {
        message_id: ID,
        validator: address,
        sequence: u64
    }

    public struct RewardDistributedEvent has copy, drop {
        validator: address,
        amount: u64,
        timestamp: u64
    }

    // === 公共函数 ===
    /// 创建新的验证器集合
    public fun new_validator_set(
        admin: address,
        ctx: &mut TxContext
    ) {
        let validator_set = ValidatorSet {
            id: object::new(ctx),
            validators: vec_set::empty(),
            weights: table::new(ctx),
            public_keys: table::new(ctx),
            threshold: 0,
            admin,
            paused: false,
            contract_version: 1,
            min_stake: 1000000000, // 1 SUI = 1_000_000_000 (9个0)
            reward_rate: 5, // 5% 年化奖励率
            slash_rate: 10 // 10% 惩罚率
        };
        transfer::share_object(validator_set);
    }

    /// 创建新的质押管理器
    public fun new_stake_manager(ctx: &mut TxContext) {
        let stake_manager = StakeManager {
            id: object::new(ctx),
            min_stake: 1000000000, // 1 SUI = 1_000_000_000 (9个0)
            total_stake: 0,
            stakes: table::new<address, StakeInfo>(ctx),
            performance_scores: table::new<address, u64>(ctx),
            vault: balance::zero<SUI>()
        };
        transfer::share_object(stake_manager)
    }

    /// 创建新的奖励池
    public fun new_reward_pool(ctx: &mut TxContext) {
        let reward_pool = RewardPool {
            id: object::new(ctx),
            rewards: table::new(ctx),
            total_rewards: 0,
            last_distribution: 0,
            reward_rate: 5, // 5% 年化奖励率
            slash_rate: 10,  // 10% 惩罚率
            vault: balance::zero<SUI>()
        };
        transfer::share_object(reward_pool)
    }

    // === Proposal 相关函数 ===
    public fun new_proposal(
        proposer: address,
        proposal_type: u8,
        params: vector<u8>,
        ctx: &mut TxContext
    ): Proposal {
        Proposal {
            id: object::new(ctx),
            proposer,
            proposal_type,
            params,
            votes: table::new(ctx),
            vote_count: 0,
            executed: false,
            creation_time: tx_context::epoch(ctx)
        }
    }

    public fun add_vote(proposal: &mut Proposal, validator: address, vote: bool) {
        if (!table::contains(&proposal.votes, validator)) {
            table::add(&mut proposal.votes, validator, vote);
            if (vote) {
                proposal.vote_count = proposal.vote_count + 1;
            };
        };
    }

    public fun get_vote_count(proposal: &Proposal): u64 {
        proposal.vote_count
    }

    public fun get_proposal_type(proposal: &Proposal): u8 {
        proposal.proposal_type
    }

    public fun get_proposal_params(proposal: &Proposal): vector<u8> {
        proposal.params
    }

    public fun get_proposal_creation_time(proposal: &Proposal): u64 {
        proposal.creation_time
    }

    public fun is_proposal_executed(proposal: &Proposal): bool {
        proposal.executed
    }

    public fun set_proposal_executed(proposal: &mut Proposal, executed: bool) {
        proposal.executed = executed;
    }

    // === ValidatorSet 相关函数 ===
    public fun get_validator_count(validator_set: &ValidatorSet): u64 {
        vec_set::size(&validator_set.validators)
    }

    public fun update_min_stake(validator_set: &mut ValidatorSet, new_min_stake: u64) {
        assert!(new_min_stake > 0, EINVALID_AMOUNT);
        validator_set.min_stake = new_min_stake;
    }

    public fun update_reward_rate(validator_set: &mut ValidatorSet, new_rate: u64) {
        assert!(new_rate <= 100, EINVALID_AMOUNT); // 确保奖励率不超过100%
        validator_set.reward_rate = new_rate;
    }

    public fun update_slash_rate(validator_set: &mut ValidatorSet, new_rate: u64) {
        assert!(new_rate <= MAX_SLASH_PERCENTAGE, EINVALID_AMOUNT);
        validator_set.slash_rate = new_rate;
    }

    public fun update_threshold(validator_set: &mut ValidatorSet, new_threshold: u64) {
        let total_weight = get_total_validator_weight(validator_set);
        assert!(new_threshold <= total_weight, EINVALID_THRESHOLD);
        validator_set.threshold = new_threshold;
    }

    public fun trigger_contract_upgrade(validator_set: &mut ValidatorSet, _upgrade_data: vector<u8>) {
        assert!(!vector::is_empty(&_upgrade_data), EINVALID_AMOUNT);
        validator_set.contract_version = validator_set.contract_version + 1;
    }

    public fun update_system_config(validator_set: &mut ValidatorSet, config_data: vector<u8>) {
        assert!(!vector::is_empty(&config_data), EINVALID_AMOUNT);
        // 从 config_data 中解析配置参数
        // 第一个字节表示参数类型：
        // 1 = min_stake
        // 2 = reward_rate
        // 3 = slash_rate
        let config_len = vector::length(&config_data);
        if (config_len >= 9) { // 1字节类型 + 8字节值
            let param_type = *vector::borrow(&config_data, 0);
            let mut value = 0u64;
            let mut i = 1;
            while (i < 9) {
                value = (value << 8) + (*vector::borrow(&config_data, i) as u64);
                i = i + 1;
            };
            
            if (param_type == 1) {
                assert!(value > 0, EINVALID_AMOUNT);
                validator_set.min_stake = value;
            } else if (param_type == 2) {
                assert!(value <= 100, EINVALID_AMOUNT);
                validator_set.reward_rate = value;
            } else if (param_type == 3) {
                assert!(value <= MAX_SLASH_PERCENTAGE, EINVALID_AMOUNT);
                validator_set.slash_rate = value;
            };
        }
    }

    public fun emergency_pause(validator_set: &mut ValidatorSet) {
        validator_set.paused = true;
    }

    public fun emergency_unpause(validator_set: &mut ValidatorSet) {
        validator_set.paused = false;
    }

    public fun emergency_remove_validator(validator_set: &mut ValidatorSet, validator: address) {
        if (vec_set::contains(&validator_set.validators, &validator)) {
            vec_set::remove(&mut validator_set.validators, &validator);
            if (table::contains(&validator_set.weights, validator)) {
                table::remove(&mut validator_set.weights, validator);
            };
        };
    }

    // === 访问器函数 ===
    public fun get_validator_weight(
        validator_set: &ValidatorSet,
        validator: address
    ): u64 {
        if (table::contains(&validator_set.weights, validator)) {
            *table::borrow(&validator_set.weights, validator)
        } else {
            0
        }
    }

    public fun get_stake_info(
        stake_manager: &StakeManager,
        validator: address
    ): (u64, u64, bool) {
        let info = table::borrow(&stake_manager.stakes, validator);
        (info.amount, info.performance_score, info.is_active)
    }

    public fun is_message_verified(message: &CrossChainMessage): bool {
        message.verified
    }

    public fun get_admin(validator_set: &ValidatorSet): address {
        validator_set.admin
    }

    public fun is_validator(validator_set: &ValidatorSet, addr: address): bool {
        vec_set::contains(&validator_set.validators, &addr)
    }

    // === TimeLock 相关函数 ===
    public fun new_timelock(
        target: address,
        action_type: u8,
        unlock_time: u64,
        ctx: &mut TxContext
    ): TimeLock {
        TimeLock {
            id: object::new(ctx),
            target,
            unlock_time,
            action_type
        }
    }

    public fun get_timelock_unlock_time(lock: &TimeLock): u64 {
        lock.unlock_time
    }

    public fun get_timelock_target(lock: &TimeLock): address {
        lock.target
    }

    public fun get_timelock_action_type(lock: &TimeLock): u8 {
        lock.action_type
    }

    public fun is_timelock_expired(lock: &TimeLock, ctx: &TxContext): bool {
        tx_context::epoch(ctx) >= lock.unlock_time
    }

    // === StakeManager 相关函数 ===
    public fun get_min_stake(stake_manager: &StakeManager): u64 {
        stake_manager.min_stake
    }

    public fun get_total_stake(manager: &StakeManager): u64 {
        manager.total_stake
    }

    public fun increase_total_stake(manager: &mut StakeManager, amount: u64) {
        manager.total_stake = manager.total_stake + amount;
    }

    public fun decrease_total_stake(manager: &mut StakeManager, amount: u64): u64 {
        let current_total = manager.total_stake;
        manager.total_stake = current_total - amount;
        manager.total_stake
    }

    public fun contains_stake(manager: &StakeManager, validator: address): bool {
        table::contains(&manager.stakes, validator)
    }

    public fun borrow_stake_mut(manager: &mut StakeManager, validator: address): &mut StakeInfo {
        table::borrow_mut(&mut manager.stakes, validator)
    }

    public fun borrow_stake(manager: &StakeManager, validator: address): &StakeInfo {
        table::borrow(&manager.stakes, validator)
    }

    public fun add_stake(manager: &mut StakeManager, validator: address, stake_info: StakeInfo) {
        table::add(&mut manager.stakes, validator, stake_info)
    }

    // === StakeInfo 相关函数 ===
    public fun new_stake_info(
        amount: u64,
        performance_score: u64,
        is_active: bool,
        last_update: u64,
    ): StakeInfo {
        StakeInfo {
            amount,
            performance_score,
            is_active,
            last_update
        }
    }

    public fun get_stake_amount(info: &StakeInfo): u64 {
        info.amount
    }

    public fun set_stake_amount(info: &mut StakeInfo, amount: u64) {
        info.amount = amount;
    }

    public fun get_performance_score(info: &StakeInfo): u64 {
        info.performance_score
    }

    public fun set_performance_score(info: &mut StakeInfo, score: u64) {
        info.performance_score = score;
    }

    public fun is_stake_active(info: &StakeInfo): bool {
        info.is_active
    }

    public fun set_stake_active(info: &mut StakeInfo, active: bool) {
        info.is_active = active;
    }

    public fun get_last_update(info: &StakeInfo): u64 {
        info.last_update
    }

    public fun set_last_update(info: &mut StakeInfo, time: u64) {
        info.last_update = time;
    }

    // === 事件创建函数 ===
    public fun new_stake_updated_event(
        validator: address,
        new_amount: u64,
        total_stake: u64
    ): StakeUpdatedEvent {
        StakeUpdatedEvent {
            validator,
            new_amount,
            total_stake
        }
    }

    #[test_only]
    public fun delete_timelock(lock: TimeLock) {
        let TimeLock { id, target: _, action_type: _, unlock_time: _ } = lock;
        object::delete(id);
    }

    // === Vault 相关函数 ===
    public(package) fun deposit_to_vault(manager: &mut StakeManager, coin: Coin<SUI>) {
        let balance = coin::into_balance(coin);
        balance::join(&mut manager.vault, balance);
    }

    public(package) fun withdraw_from_vault(manager: &mut StakeManager, amount: u64, ctx: &mut TxContext): Coin<SUI> {
        coin::from_balance(balance::split(&mut manager.vault, amount), ctx)
    }

    // === ValidatorSet 相关函数 ===
    public fun add_validator_with_weight(
        validator_set: &mut ValidatorSet,
        validator: address,
        weight: u64
    ) {
        vec_set::insert(&mut validator_set.validators, validator);
        table::add(&mut validator_set.weights, validator, weight);
    }

    public fun remove_validator_weight(
        validator_set: &mut ValidatorSet,
        validator: address
    ) {
        if (table::contains(&validator_set.weights, validator)) {
            table::remove(&mut validator_set.weights, validator);
        };
    }

    public fun update_validator_weight(
        validator_set: &mut ValidatorSet,
        validator: address,
        weight: u64
    ) {
        if (table::contains(&validator_set.weights, validator)) {
            *table::borrow_mut(&mut validator_set.weights, validator) = weight;
        };
    }

    public fun get_total_validator_weight(validator_set: &ValidatorSet): u64 {
        let mut total_weight = 0u64;
        let validators = &validator_set.validators;
        let weights = &validator_set.weights;
        let validator_keys = vec_set::keys(validators);
        let mut i = 0;
        while (i < vector::length(validator_keys)) {
            let validator = vector::borrow(validator_keys, i);
            if (table::contains(weights, *validator)) {
                total_weight = total_weight + *table::borrow(weights, *validator);
            };
            i = i + 1;
        };
        total_weight
    }

    public fun get_active_validators(validator_set: &ValidatorSet): vector<address> {
        let keys = vec_set::keys(&validator_set.validators);
        vector::map_ref!(keys, |addr| *addr)
    }

    // === RewardPool 相关函数 ===
    public fun add_total_rewards(pool: &mut RewardPool, amount: u64) {
        pool.total_rewards = pool.total_rewards + amount;
    }

    public fun get_total_rewards(pool: &RewardPool): u64 {
        pool.total_rewards
    }

    public fun get_last_distribution(pool: &RewardPool): u64 {
        pool.last_distribution
    }

    public fun update_last_distribution(pool: &mut RewardPool, time: u64) {
        pool.last_distribution = time;
    }

    public fun get_validator_rewards(pool: &RewardPool, validator: address): u64 {
        if (table::contains(&pool.rewards, validator)) {
            *table::borrow(&pool.rewards, validator)
        } else {
            0
        }
    }

    public fun update_validator_rewards(pool: &mut RewardPool, validator: address, amount: u64) {
        if (!table::contains(&pool.rewards, validator)) {
            table::add(&mut pool.rewards, validator, amount);
        } else {
            let current_reward = table::borrow_mut(&mut pool.rewards, validator);
            *current_reward = *current_reward + amount;
        }
    }

    public fun clear_validator_rewards(pool: &mut RewardPool, validator: address) {
        if (table::contains(&pool.rewards, validator)) {
            table::remove(&mut pool.rewards, validator);
        }
    }

    // === 新增访问器函数 ===
    public fun get_reward_rate(validator_set: &ValidatorSet): u64 {
        validator_set.reward_rate
    }

    public fun get_slash_rate(validator_set: &ValidatorSet): u64 {
        validator_set.slash_rate
    }

    public fun get_contract_version(validator_set: &ValidatorSet): u64 {
        validator_set.contract_version
    }

    // === 常量 ===
    const MAX_SLASH_PERCENTAGE: u64 = 30; // 最大惩罚比例 30%
    const MIN_PERFORMANCE_SCORE: u64 = 50; // 最低性能分数 50%

    // === 性能分数相关函数 ===
    public fun get_min_performance_score(): u64 {
        MIN_PERFORMANCE_SCORE
    }

    // === 奖励池相关函数 ===
    public fun add_rewards_balance(pool: &mut RewardPool, balance: Balance<SUI>) {
        let amount = balance::value(&balance);
        pool.total_rewards = pool.total_rewards + amount;
        balance::join(&mut pool.vault, balance);
    }

    public fun withdraw_rewards(pool: &mut RewardPool, amount: u64): Balance<SUI> {
        assert!(amount <= pool.total_rewards, EINVALID_AMOUNT);
        pool.total_rewards = pool.total_rewards - amount;
        balance::split(&mut pool.vault, amount)
    }

    public fun add_validator_with_weight_and_key(
        validator_set: &mut ValidatorSet,
        validator: address,
        weight: u64,
        public_key: vector<u8>
    ) {
        vec_set::insert(&mut validator_set.validators, validator);
        table::add(&mut validator_set.weights, validator, weight);
        table::add(&mut validator_set.public_keys, validator, public_key);
    }

    public fun get_validator_public_key(validator_set: &ValidatorSet, validator: address): vector<u8> {
        assert!(vec_set::contains(&validator_set.validators, &validator), EINVALID_VALIDATOR);
        *table::borrow(&validator_set.public_keys, validator)
    }
} 