/// 质押管理模块测试
/// 本测试模块验证质押管理系统的核心功能，包括：
/// 1. 质押生命周期管理（质押、解质押）
/// 2. 性能分数管理
/// 3. 多验证器场景下的质押管理
#[test_only]
module bridge_validator::stake_tests {
    use sui::test_scenario::{Self, Scenario};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use bridge_validator::stake;
    use bridge_validator::types::{Self, StakeManager};
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

    // === 测试辅助函数 ===
    /// 初始化测试环境
    /// 创建质押管理器
    /// 返回：初始化后的测试场景
    fun setup_test(): Scenario {
        let mut scenario = test_scenario::begin(ADMIN);
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            // 初始化质押管理器
            stake::init_for_test(test_scenario::ctx(&mut scenario));
        };
        scenario
    }

    /// 测试质押的完整生命周期
    /// 验证质押、更新性能分数和解质押的流程
    #[test]
    fun test_stake_lifecycle() {
        let mut scenario = setup_test();
        
        // 第一步：质押测试
        // VALIDATOR1质押1000 SUI
        test_scenario::next_tx(&mut scenario, VALIDATOR1);
        {
            let mut stake_manager = test_scenario::take_shared<StakeManager>(&scenario);
            let stake_coin = coin::mint_for_testing<SUI>(MIN_STAKE, test_scenario::ctx(&mut scenario));
            
            stake::stake(&mut stake_manager, stake_coin, test_scenario::ctx(&mut scenario));
            
            assert!(stake::is_active(&stake_manager, VALIDATOR1), 0); // 验证质押状态为活跃
            let (amount, score, active, _) = stake::get_stake(&stake_manager, VALIDATOR1);
            assert!(amount == MIN_STAKE, 1); // 验证质押金额正确
            assert!(score == stake::get_default_performance_score(), 2); // 验证初始性能分数
            assert!(active == true, 3); // 验证活跃状态
            
            test_scenario::return_shared(stake_manager);
        };
        
        // 第二步：性能更新测试
        // 将VALIDATOR1的性能分数更新为70
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut stake_manager = test_scenario::take_shared<StakeManager>(&scenario);
            
            stake::update_performance(
                &mut stake_manager,
                VALIDATOR1,
                70, // 新的性能分数（范围0-100）
                test_scenario::ctx(&mut scenario)
            );
            
            let (_, score, _, _) = stake::get_stake(&stake_manager, VALIDATOR1);
            assert!(score == 70, 4); // 验证性能分数已更新
            
            test_scenario::return_shared(stake_manager);
        };
        
        // 第三步：解质押测试
        // VALIDATOR1解质押500 SUI（一半的质押金额）
        test_scenario::next_tx(&mut scenario, VALIDATOR1);
        {
            let mut stake_manager = test_scenario::take_shared<StakeManager>(&scenario);
            let timelock = security::create_timelock(
                VALIDATOR1,
                security::get_unstake_action_type(),
                test_scenario::ctx(&mut scenario)
            );
            
            // 等待时间锁过期（3个epoch）
            test_scenario::next_epoch(&mut scenario, VALIDATOR1);
            test_scenario::next_epoch(&mut scenario, VALIDATOR1);
            test_scenario::next_epoch(&mut scenario, VALIDATOR1);
            
            stake::unstake(
                &mut stake_manager,
                MIN_STAKE / 2, // 解质押一半的金额
                &timelock,
                test_scenario::ctx(&mut scenario)
            );
            
            let (amount, _, active, _) = stake::get_stake(&stake_manager, VALIDATOR1);
            assert!(amount == MIN_STAKE / 2, 5); // 验证剩余质押金额
            assert!(!active, 6); // 验证状态变为非活跃（因为低于最小质押要求）
            
            test_scenario::return_shared(stake_manager);
            types::delete_timelock(timelock); // 清理时间锁对象
        };
        
        test_scenario::end(scenario);
    }

    /// 测试多验证器场景
    /// 验证多个验证器同时质押和性能更新的情况
    #[test]
    fun test_multiple_validators() {
        let mut scenario = setup_test();
        
        // 第一步：多个验证器质押
        // VALIDATOR1质押2000 SUI
        test_scenario::next_tx(&mut scenario, VALIDATOR1);
        {
            let mut stake_manager = test_scenario::take_shared<StakeManager>(&scenario);
            let stake_coin = coin::mint_for_testing<SUI>(MIN_STAKE * 2, test_scenario::ctx(&mut scenario));
            stake::stake(&mut stake_manager, stake_coin, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(stake_manager);
        };
        
        // VALIDATOR2质押1000 SUI
        test_scenario::next_tx(&mut scenario, VALIDATOR2);
        {
            let mut stake_manager = test_scenario::take_shared<StakeManager>(&scenario);
            let stake_coin = coin::mint_for_testing<SUI>(MIN_STAKE, test_scenario::ctx(&mut scenario));
            stake::stake(&mut stake_manager, stake_coin, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(stake_manager);
        };
        
        // 第二步：验证总质押量
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let stake_manager = test_scenario::take_shared<StakeManager>(&scenario);
            assert!(stake::get_total_stake(&stake_manager) == MIN_STAKE * 3, 7); // 验证总质押量为3000 SUI
            test_scenario::return_shared(stake_manager);
        };
        
        // 第三步：批量更新性能分数
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut stake_manager = test_scenario::take_shared<StakeManager>(&scenario);
            
            stake::update_performance(&mut stake_manager, VALIDATOR1, 90, test_scenario::ctx(&mut scenario)); // 优秀表现
            stake::update_performance(&mut stake_manager, VALIDATOR2, 55, test_scenario::ctx(&mut scenario)); // 较差表现
            
            assert!(stake::is_active(&stake_manager, VALIDATOR1), 8); // VALIDATOR1应保持活跃
            assert!(!stake::is_active(&stake_manager, VALIDATOR2), 9); // VALIDATOR2应变为非活跃（性能分数过低）
            
            test_scenario::return_shared(stake_manager);
        };
        
        test_scenario::end(scenario);
    }

    /// 测试质押金额不足的情况
    /// 验证系统正确拒绝低于最小要求的质押
    #[test]
    #[expected_failure(abort_code = stake::EINVALID_STAKE_AMOUNT)]
    fun test_insufficient_stake() {
        let mut scenario = setup_test();
        
        test_scenario::next_tx(&mut scenario, VALIDATOR1);
        {
            let mut stake_manager = test_scenario::take_shared<StakeManager>(&scenario);
            let stake_coin = coin::mint_for_testing<SUI>(MIN_STAKE / 2, test_scenario::ctx(&mut scenario)); // 500 SUI
            
            // 尝试质押500 SUI（应该失败，因为低于最小要求1000 SUI）
            stake::stake(&mut stake_manager, stake_coin, test_scenario::ctx(&mut scenario));
            
            test_scenario::return_shared(stake_manager);
        };
        
        test_scenario::end(scenario);
    }

    /// 测试无效的性能分数
    /// 验证系统正确拒绝超出范围的性能分数
    #[test]
    #[expected_failure(abort_code = stake::EINVALID_PERFORMANCE_SCORE)]
    fun test_invalid_performance_score() {
        let mut scenario = setup_test();
        
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut stake_manager = test_scenario::take_shared<StakeManager>(&scenario);
            
            // 尝试设置101分的性能分数（应该失败，因为超出0-100的范围）
            stake::update_performance(&mut stake_manager, VALIDATOR1, 101, test_scenario::ctx(&mut scenario));
            
            test_scenario::return_shared(stake_manager);
        };
        
        test_scenario::end(scenario);
    }
} 