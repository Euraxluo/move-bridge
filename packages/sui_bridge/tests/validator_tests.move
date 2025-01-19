#[test_only]
module sui_bridge::validator_tests {
    use sui::test_scenario::{Self as test, next_tx, ctx};
    use sui::test_utils::assert_eq;
    use sui::transfer;
    use std::vector;

    use sui_bridge::validator::{Self, ValidatorConfig};

    // === 测试常量 ===
    const ADMIN: address = @0x1;
    const VALIDATOR1: address = @0xA1;
    const VALIDATOR2: address = @0xA2;
    const NON_VALIDATOR: address = @0xB1;
    const THRESHOLD: u64 = 2;

    #[test]
    fun test_validator_initialization() {
        let mut scenario = test::begin(ADMIN);
        validator::init_for_test(ctx(&mut scenario));
        
        next_tx(&mut scenario, ADMIN);
        let validator_config = test::take_shared<ValidatorConfig>(&scenario);
        assert!(validator::get_threshold(&validator_config) == THRESHOLD, 0);
        test::return_shared(validator_config);
        test::end(scenario);
    }

    #[test]
    fun test_add_validator() {
        let mut scenario = test::begin(ADMIN);
        validator::init_for_test(ctx(&mut scenario));
        
        next_tx(&mut scenario, ADMIN);
        let mut validator_config = test::take_shared<ValidatorConfig>(&scenario);
        validator::add_validator(&mut validator_config, VALIDATOR1, 1, ctx(&mut scenario));
        assert!(validator::has_validator(&validator_config, VALIDATOR1), 0);
        assert!(validator::get_validator_weight(&validator_config, VALIDATOR1) == 1, 1);
        test::return_shared(validator_config);
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = validator::EINVALID_ADMIN)]
    fun test_add_validator_by_non_admin() {
        let mut scenario = test::begin(ADMIN);
        validator::init_for_test(ctx(&mut scenario));
        
        next_tx(&mut scenario, NON_VALIDATOR);
        let mut validator_config = test::take_shared<ValidatorConfig>(&scenario);
        validator::add_validator(&mut validator_config, VALIDATOR1, 1, ctx(&mut scenario));
        test::return_shared(validator_config);
        test::end(scenario);
    }

    #[test]
    fun test_remove_validator() {
        let mut scenario = test::begin(ADMIN);
        validator::init_for_test(ctx(&mut scenario));
        
        next_tx(&mut scenario, ADMIN);
        let mut validator_config = test::take_shared<ValidatorConfig>(&scenario);
        validator::add_validator(&mut validator_config, VALIDATOR1, 1, ctx(&mut scenario));
        validator::remove_validator(&mut validator_config, VALIDATOR1, ctx(&mut scenario));
        assert!(!validator::has_validator(&validator_config, VALIDATOR1), 0);
        test::return_shared(validator_config);
        test::end(scenario);
    }

    #[test]
    fun test_update_validator_weight() {
        let mut scenario = test::begin(ADMIN);
        validator::init_for_test(ctx(&mut scenario));
        
        next_tx(&mut scenario, ADMIN);
        let mut validator_config = test::take_shared<ValidatorConfig>(&scenario);
        validator::add_validator(&mut validator_config, VALIDATOR1, 1, ctx(&mut scenario));
        validator::update_validator_weight(&mut validator_config, VALIDATOR1, 2, ctx(&mut scenario));
        assert!(validator::get_validator_weight(&validator_config, VALIDATOR1) == 2, 0);
        test::return_shared(validator_config);
        test::end(scenario);
    }

    #[test]
    fun test_verify_message() {
        let mut scenario = test::begin(ADMIN);
        validator::init_for_test(ctx(&mut scenario));
        
        next_tx(&mut scenario, ADMIN);
        let mut validator_config = test::take_shared<ValidatorConfig>(&scenario);
        validator::add_validator(&mut validator_config, VALIDATOR1, 1, ctx(&mut scenario));
        validator::add_validator(&mut validator_config, VALIDATOR2, 1, ctx(&mut scenario));

        let message_id = x"0123456789abcdef";
        let signatures = vector::empty();
        assert!(validator::verify_message(&mut validator_config, message_id, signatures, ctx(&mut scenario)), 0);

        test::return_shared(validator_config);
        test::end(scenario);
    }
} 