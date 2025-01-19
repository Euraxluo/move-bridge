#[test_only]
module sui_bridge::control_tests {
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    use sui_bridge::control::{Self, ControlConfig};

    const ADMIN: address = @0xA;
    const USER: address = @0xB;
    const NEW_ADMIN: address = @0xC;

    fun test_scenario(): Scenario { test::begin(ADMIN) }

    #[test]
    fun test_pause_unpause() {
        let mut scenario = test_scenario();
        
        // 初始化
        next_tx(&mut scenario, ADMIN);
        {
            control::init_for_test(ctx(&mut scenario));
        };

        // 暂停桥
        next_tx(&mut scenario, ADMIN);
        {
            let mut config = test::take_shared<ControlConfig>(&mut scenario);
            assert!(!control::is_paused(&config), 0);
            
            control::pause_bridge(&mut config, ctx(&mut scenario));
            assert!(control::is_paused(&config), 0);

            test::return_shared(config);
        };

        // 恢复桥
        next_tx(&mut scenario, ADMIN);
        {
            let mut config = test::take_shared<ControlConfig>(&mut scenario);
            control::unpause_bridge(&mut config, ctx(&mut scenario));
            assert!(!control::is_paused(&config), 0);

            test::return_shared(config);
        };
        test::end(scenario);
    }

    #[test]
    fun test_admin_change() {
        let mut scenario = test_scenario();
        
        // 初始化
        next_tx(&mut scenario, ADMIN);
        {
            control::init_for_test(ctx(&mut scenario));
        };

        // 更改管理员
        next_tx(&mut scenario, ADMIN);
        {
            let mut config = test::take_shared<ControlConfig>(&mut scenario);
            assert!(control::get_admin(&config) == ADMIN, 0);
            
            control::set_admin(&mut config, NEW_ADMIN, ctx(&mut scenario));
            assert!(control::get_admin(&config) == NEW_ADMIN, 0);

            test::return_shared(config);
        };
        test::end(scenario);
    }

    #[test]
    fun test_fee_rate() {
        let mut scenario = test_scenario();
        
        // 初始化
        next_tx(&mut scenario, ADMIN);
        {
            control::init_for_test(ctx(&mut scenario));
        };

        // 设置费率
        next_tx(&mut scenario, ADMIN);
        {
            let mut config = test::take_shared<ControlConfig>(&mut scenario);
            assert!(control::get_fee_rate(&config) == 0, 0);
            
            let new_rate = 100; // 1%
            control::set_fee_rate(&mut config, new_rate, ctx(&mut scenario));
            assert!(control::get_fee_rate(&config) == new_rate, 0);

            // 测试费用计算
            let amount = 10000;
            let fee = control::calculate_fee(&config, amount);
            assert!(fee == 100, 0); // 1% of 10000

            test::return_shared(config);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1)]
    fun test_unauthorized_admin_change() {
        let mut scenario = test_scenario();
        
        // 初始化
        next_tx(&mut scenario, ADMIN);
        {
            control::init_for_test(ctx(&mut scenario));
        };

        // 非管理员尝试更改管理员
        next_tx(&mut scenario, USER);
        {
            let mut config = test::take_shared<ControlConfig>(&mut scenario);
            control::set_admin(&mut config, NEW_ADMIN, ctx(&mut scenario));
            test::return_shared(config);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 2)]
    fun test_invalid_fee_rate() {
        let mut scenario = test_scenario();
        
        // 初始化
        next_tx(&mut scenario, ADMIN);
        {
            control::init_for_test(ctx(&mut scenario));
        };

        // 设置无效费率
        next_tx(&mut scenario, ADMIN);
        {
            let mut config = test::take_shared<ControlConfig>(&mut scenario);
            control::set_fee_rate(&mut config, 10001, ctx(&mut scenario)); // > 100%
            test::return_shared(config);
        };
        test::end(scenario);
    }
} 