/// 奖励管理模块测试
/// 本测试模块验证奖励管理系统的核心功能，包括：
/// 1. 奖励分配机制
/// 2. 奖励领取流程
/// 3. 惩罚机制与奖励池管理
#[test_only]
module bridge_validator::reward_tests {
    use sui::test_scenario::{Self, Scenario};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use bridge_validator::reward;
    use bridge_validator::stake;
    use bridge_validator::validator;
    use bridge_validator::types::{Self, RewardPool, StakeManager, ValidatorSet};

    // === 测试常量定义 ===
    /// 最小质押要求：1000 SUI
    const MIN_STAKE: u64 = 1000_000_000; // 1 SUI = 1_000_000_000 (9个0)
    /// 奖励金额：100 SUI
    const REWARD_AMOUNT: u64 = 100_000_000; // 1 SUI = 1_000_000_000 (9个0)
    /// 系统管理员地址
    const ADMIN: address = @0xAD;
    /// 测试验证器1地址
    const VALIDATOR1: address = @0x1;
    /// 测试验证器2地址
    const VALIDATOR2: address = @0x2;
    /// 测试验证器3地址
    const VALIDATOR3: address = @0x3;

    // === 测试公钥数据 ===
    /// 验证器1的Ed25519公钥（32字节）
    const VALIDATOR1_PUBKEY: vector<u8> = vector[
        182, 47, 109, 177, 21, 56, 131, 42, 202, 138, 249, 242, 16, 3, 5, 205,
        244, 227, 116, 217, 98, 53, 120, 118, 24, 119, 37, 98, 158, 119, 33, 162
    ];
    /// 验证器2的Ed25519公钥（32字节）
    const VALIDATOR2_PUBKEY: vector<u8> = vector[
        20, 154, 147, 13, 4, 64, 166, 200, 159, 179, 194, 235, 205, 176, 117, 6,
        154, 152, 127, 161, 216, 8, 233, 60, 193, 12, 130, 131, 227, 60, 82, 35
    ];
    /// 验证器3的Ed25519公钥（32字节）
    const VALIDATOR3_PUBKEY: vector<u8> = vector[
        237, 70, 123, 179, 76, 65, 106, 77, 118, 197, 19, 209, 132, 43, 20, 146,
        24, 129, 18, 51, 132, 234, 150, 38, 47, 206, 121, 141, 49, 134, 145, 31
    ];

    /// 测试奖励分配流程
    /// 验证奖励的添加、分配和领取机制
    #[test]
    fun test_reward_distribution() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // 第一步：初始化系统组件
        {
            let ctx = test_scenario::ctx(&mut scenario);
            stake::init_for_test(ctx);
            validator::init_for_test(ctx);
            reward::init_for_test(ctx);
        };

        // 第二步：设置验证器
        // VALIDATOR1质押2000 SUI
        test_scenario::next_tx(&mut scenario, VALIDATOR1);
        {
            let mut stake_manager = test_scenario::take_shared<StakeManager>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);
            
            let stake_coin = coin::mint_for_testing<SUI>(MIN_STAKE * 2, ctx);
            stake::stake(&mut stake_manager, stake_coin, ctx);
            
            test_scenario::return_shared(stake_manager);
        };

        // 管理员添加VALIDATOR1
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut validator_set = test_scenario::take_shared<ValidatorSet>(&scenario);
            let stake_manager = test_scenario::take_shared<StakeManager>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);
            
            validator::add_validator(
                &mut validator_set,
                &stake_manager,
                VALIDATOR1,
                VALIDATOR1_PUBKEY,
                ctx
            );
            
            test_scenario::return_shared(validator_set);
            test_scenario::return_shared(stake_manager);
        };

        // VALIDATOR2质押1000 SUI
        test_scenario::next_tx(&mut scenario, VALIDATOR2);
        {
            let mut stake_manager = test_scenario::take_shared<StakeManager>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);
            
            let stake_coin = coin::mint_for_testing<SUI>(MIN_STAKE, ctx);
            stake::stake(&mut stake_manager, stake_coin, ctx);
            
            test_scenario::return_shared(stake_manager);
        };

        // 管理员添加VALIDATOR2
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut validator_set = test_scenario::take_shared<ValidatorSet>(&scenario);
            let stake_manager = test_scenario::take_shared<StakeManager>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);
            
            validator::add_validator(
                &mut validator_set,
                &stake_manager,
                VALIDATOR2,
                VALIDATOR2_PUBKEY,
                ctx
            );
            
            test_scenario::return_shared(validator_set);
            test_scenario::return_shared(stake_manager);
        };
        
        // 第三步：添加奖励
        // 向奖励池添加100 SUI的奖励
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut reward_pool = test_scenario::take_shared<RewardPool>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);
            let reward_coin = coin::mint_for_testing<SUI>(REWARD_AMOUNT, ctx);
            
            reward::add_rewards(&mut reward_pool, reward_coin, ctx);
            test_scenario::return_shared(reward_pool);
        };
        
        // 第四步：等待奖励分配周期
        test_scenario::next_tx(&mut scenario, ADMIN);
        // 模拟等待10个epoch的奖励分配周期
        let mut i = 0;
        while (i < 10) {
            test_scenario::next_epoch(&mut scenario, ADMIN);
            i = i + 1;
        };

        // 第五步：分配奖励
        {
            let mut reward_pool = test_scenario::take_shared<RewardPool>(&scenario);
            let stake_manager = test_scenario::take_shared<StakeManager>(&scenario);
            let validator_set = test_scenario::take_shared<ValidatorSet>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);
            
            reward::distribute_rewards(
                &mut reward_pool,
                &stake_manager,
                &validator_set,
                ctx
            );
            
            // 验证奖励分配结果
            let v1_reward = reward::get_pending_rewards(&reward_pool, VALIDATOR1);
            let v2_reward = reward::get_pending_rewards(&reward_pool, VALIDATOR2);
            
            assert!(v1_reward > v2_reward, 1); // 验证VALIDATOR1获得更多奖励（因为质押更多）
            assert!(v1_reward + v2_reward <= REWARD_AMOUNT, 2); // 验证总奖励不超过奖励池金额
            
            test_scenario::return_shared(reward_pool);
            test_scenario::return_shared(stake_manager);
            test_scenario::return_shared(validator_set);
        };
        
        // 第六步：领取奖励
        // VALIDATOR1领取其奖励
        test_scenario::next_tx(&mut scenario, VALIDATOR1);
        {
            let mut reward_pool = test_scenario::take_shared<RewardPool>(&scenario);
            let validator_set = test_scenario::take_shared<ValidatorSet>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);
            
            let pending_reward = reward::get_pending_rewards(&reward_pool, VALIDATOR1);
            let reward_coin = reward::claim_rewards(
                &mut reward_pool,
                &validator_set,
                ctx
            );
            
            assert!(coin::value(&reward_coin) == pending_reward, 3); // 验证领取的奖励金额正确
            assert!(reward::get_pending_rewards(&reward_pool, VALIDATOR1) == 0, 4); // 验证待领取奖励已清零
            
            coin::burn_for_testing(reward_coin); // 清理测试币
            test_scenario::return_shared(reward_pool);
            test_scenario::return_shared(validator_set);
        };
        
        test_scenario::end(scenario);
    }

    /// 测试惩罚机制与奖励池
    /// 验证验证器的惩罚机制和惩罚金进入奖励池的流程
    #[test]
    fun test_slash_and_reward() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // 第一步：初始化系统组件
        {
            let ctx = test_scenario::ctx(&mut scenario);
            stake::init_for_test(ctx);
            validator::init_for_test(ctx);
            reward::init_for_test(ctx);
        };

        // 第二步：设置验证器
        // VALIDATOR1质押2000 SUI
        test_scenario::next_tx(&mut scenario, VALIDATOR1);
        {
            let mut stake_manager = test_scenario::take_shared<StakeManager>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);
            
            let stake_coin = coin::mint_for_testing<SUI>(MIN_STAKE * 2, ctx);
            stake::stake(&mut stake_manager, stake_coin, ctx);
            
            test_scenario::return_shared(stake_manager);
        };

        // 管理员添加VALIDATOR1
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut validator_set = test_scenario::take_shared<ValidatorSet>(&scenario);
            let stake_manager = test_scenario::take_shared<StakeManager>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);
            
            validator::add_validator(
                &mut validator_set,
                &stake_manager,
                VALIDATOR1,
                VALIDATOR1_PUBKEY,
                ctx
            );
            
            test_scenario::return_shared(validator_set);
            test_scenario::return_shared(stake_manager);
        };
        
        // 第三步：惩罚验证器
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut reward_pool = test_scenario::take_shared<RewardPool>(&scenario);
            let mut stake_manager = test_scenario::take_shared<StakeManager>(&scenario);
            let validator_set = test_scenario::take_shared<ValidatorSet>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);
            
            reward::slash_validator(
                &mut reward_pool,
                &mut stake_manager,
                &validator_set,
                VALIDATOR1,
                1, // 惩罚原因：离线（SLASH_REASON_OFFLINE）
                ctx
            );
            
            // 验证惩罚结果
            assert!(!stake::is_active(&stake_manager, VALIDATOR1), 1); // 验证VALIDATOR1变为非活跃状态
            
            test_scenario::return_shared(reward_pool);
            test_scenario::return_shared(stake_manager);
            test_scenario::return_shared(validator_set);
        };
        
        // 第四步：验证惩罚金
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let reward_pool = test_scenario::take_shared<RewardPool>(&scenario);
            assert!(reward::get_total_rewards(&reward_pool) > 0, 2); // 验证惩罚金已进入奖励池
            test_scenario::return_shared(reward_pool);
        };
        
        test_scenario::end(scenario);
    }
} 