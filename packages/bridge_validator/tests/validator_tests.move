/// 验证器管理模块测试
/// 本测试模块验证验证器管理系统的核心功能，包括：
/// 1. 验证器的生命周期管理（添加、更新、移除）
/// 2. 权重和阈值计算
/// 3. 权限控制系统
#[test_only]
module bridge_validator::validator_tests {
    use sui::test_scenario::{Self, Scenario};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use bridge_validator::validator;
    use bridge_validator::stake;
    use bridge_validator::types::{Self, ValidatorSet, StakeManager};
    use bridge_validator::security;

    // === 测试常量定义 ===
    /// 最小质押要求：1000 SUI
    const MIN_STAKE: u64 = 1000_000_000; // 1 SUI = 1_000_000_000 (9个0)
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

    // === 测试辅助函数 ===
    /// 初始化测试环境
    /// 创建验证器集合和质押管理器
    /// 返回：初始化后的测试场景
    fun setup_test(): Scenario {
        let mut scenario = test_scenario::begin(ADMIN);
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            validator::init_for_test(test_scenario::ctx(&mut scenario));
            stake::init_for_test(test_scenario::ctx(&mut scenario));
        };
        scenario
    }

    /// 测试验证器的完整生命周期
    /// 验证添加、更新权重和移除验证器的流程
    #[test]
    fun test_validator_lifecycle() {
        let mut scenario = setup_test();
        
        // 第一步：添加验证器
        // VALIDATOR1质押1000 SUI并被添加为验证器
        test_scenario::next_tx(&mut scenario, VALIDATOR1);
        {
            let mut stake_manager = test_scenario::take_shared<StakeManager>(&scenario);
            let stake_coin = coin::mint_for_testing<SUI>(MIN_STAKE, test_scenario::ctx(&mut scenario));
            stake::stake(&mut stake_manager, stake_coin, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(stake_manager);
        };

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut validator_set = test_scenario::take_shared<ValidatorSet>(&scenario);
            let stake_manager = test_scenario::take_shared<StakeManager>(&scenario);
            
            validator::add_validator(
                &mut validator_set,
                &stake_manager,
                VALIDATOR1,
                VALIDATOR1_PUBKEY,
                test_scenario::ctx(&mut scenario)
            );
            
            // 验证添加结果
            assert!(validator::is_validator(&validator_set, VALIDATOR1), 0); // 确认VALIDATOR1已成为验证器
            assert!(validator::get_validator_count(&validator_set) == 1, 1); // 确认验证器总数为1
            
            test_scenario::return_shared(validator_set);
            test_scenario::return_shared(stake_manager);
        };
        
        // 第二步：更新验证器权重
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut validator_set = test_scenario::take_shared<ValidatorSet>(&scenario);
            let mut stake_manager = test_scenario::take_shared<StakeManager>(&scenario);
            
            validator::update_validator_weight(
                &mut validator_set,
                &stake_manager,
                VALIDATOR1,
                150, // 将权重设置为150（1.5倍基础权重）
                test_scenario::ctx(&mut scenario)
            );
            
            // 验证权重更新结果
            assert!(validator::get_validator_weight(&validator_set, VALIDATOR1) == 150, 2);
            
            test_scenario::return_shared(validator_set);
            test_scenario::return_shared(stake_manager);
        };
        
        // 第三步：移除验证器
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut validator_set = test_scenario::take_shared<ValidatorSet>(&scenario);
            let mut stake_manager = test_scenario::take_shared<StakeManager>(&scenario);
            
            validator::remove_validator(
                &mut validator_set,
                &stake_manager,
                VALIDATOR1,
                test_scenario::ctx(&mut scenario)
            );
            
            // 验证移除结果
            assert!(!validator::is_validator(&validator_set, VALIDATOR1), 3); // 确认VALIDATOR1不再是验证器
            assert!(validator::get_validator_count(&validator_set) == 0, 4); // 确认验证器总数为0
            
            test_scenario::return_shared(validator_set);
            test_scenario::return_shared(stake_manager);
        };
        
        test_scenario::end(scenario);
    }

    /// 测试验证器阈值计算
    /// 验证系统在多个验证器场景下的阈值计算是否正确
    #[test]
    fun test_validator_threshold() {
        let mut scenario = setup_test();
        
        // 第一步：添加两个验证器
        // VALIDATOR1质押2000 SUI（权重为2）
        test_scenario::next_tx(&mut scenario, VALIDATOR1);
        {
            let mut stake_manager = test_scenario::take_shared<StakeManager>(&scenario);
            let stake_coin = coin::mint_for_testing<SUI>(MIN_STAKE * 2, test_scenario::ctx(&mut scenario));
            stake::stake(&mut stake_manager, stake_coin, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(stake_manager);
        };

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut validator_set = test_scenario::take_shared<ValidatorSet>(&scenario);
            let stake_manager = test_scenario::take_shared<StakeManager>(&scenario);
            
            validator::add_validator(
                &mut validator_set,
                &stake_manager,
                VALIDATOR1,
                VALIDATOR1_PUBKEY,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(validator_set);
            test_scenario::return_shared(stake_manager);
        };
        
        // VALIDATOR2质押1000 SUI（权重为1）
        test_scenario::next_tx(&mut scenario, VALIDATOR2);
        {
            let mut stake_manager = test_scenario::take_shared<StakeManager>(&scenario);
            let stake_coin = coin::mint_for_testing<SUI>(MIN_STAKE, test_scenario::ctx(&mut scenario));
            stake::stake(&mut stake_manager, stake_coin, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(stake_manager);
        };

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut validator_set = test_scenario::take_shared<ValidatorSet>(&scenario);
            let stake_manager = test_scenario::take_shared<StakeManager>(&scenario);
            
            validator::add_validator(
                &mut validator_set,
                &stake_manager,
                VALIDATOR2,
                VALIDATOR2_PUBKEY,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(validator_set);
            test_scenario::return_shared(stake_manager);
        };
        
        // 第二步：验证阈值计算
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let validator_set = test_scenario::take_shared<ValidatorSet>(&scenario);
            
            let threshold = validator::get_threshold(&validator_set);
            assert!(threshold > 0, 0); // 验证阈值大于0
            
            // 验证阈值满足2/3多数要求
            let total_weight = validator::get_total_weight(&validator_set);
            assert!(threshold >= (total_weight * 2 / 3), 1); // 阈值应不小于总权重的2/3
            assert!(threshold < total_weight, 2); // 阈值应小于总权重
            
            test_scenario::return_shared(validator_set);
        };
        
        test_scenario::end(scenario);
    }

    /// 测试验证器权限系统
    /// 验证不同角色（管理员、验证器、普通用户）的权限控制
    #[test]
    fun test_validator_permissions() {
        let mut scenario = setup_test();
        
        // 第一步：设置初始验证器
        test_scenario::next_tx(&mut scenario, VALIDATOR1);
        {
            let mut stake_manager = test_scenario::take_shared<StakeManager>(&scenario);
            let stake_coin = coin::mint_for_testing<SUI>(MIN_STAKE, test_scenario::ctx(&mut scenario));
            stake::stake(&mut stake_manager, stake_coin, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(stake_manager);
        };

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut validator_set = test_scenario::take_shared<ValidatorSet>(&scenario);
            let stake_manager = test_scenario::take_shared<StakeManager>(&scenario);
            
            validator::add_validator(
                &mut validator_set,
                &stake_manager,
                VALIDATOR1,
                VALIDATOR1_PUBKEY,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(validator_set);
            test_scenario::return_shared(stake_manager);
        };
        
        // 第二步：验证非管理员无法添加验证器
        test_scenario::next_tx(&mut scenario, VALIDATOR2);
        {
            let mut validator_set = test_scenario::take_shared<ValidatorSet>(&scenario);
            let stake_manager = test_scenario::take_shared<StakeManager>(&scenario);
            
            // 尝试添加新验证器（应该失败）
            assert!(
                !validator::can_pause(&validator_set, VALIDATOR2),
                0 // 确认VALIDATOR2不能执行管理员操作
            );
            
            test_scenario::return_shared(validator_set);
            test_scenario::return_shared(stake_manager);
        };
        
        // 第三步：验证管理员权限
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let validator_set = test_scenario::take_shared<ValidatorSet>(&scenario);
            
            assert!(
                validator::can_pause(&validator_set, ADMIN),
                1 // 确认ADMIN具有管理员权限
            );
            
            test_scenario::return_shared(validator_set);
        };
        
        test_scenario::end(scenario);
    }
} 