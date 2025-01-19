#[test_only]
module rooch_bridge::control_tests {
    use std::signer;
    use moveos_std::object;
    use rooch_bridge::control;

    #[test(admin = @0x42)]
    fun test_control_basic(admin: &signer) {
        // Initialize control
        let control_obj = control::init_control(admin);
        
        // Test initial state
        assert!(!control::is_paused(&control_obj), 1);
        assert!(control::get_fee_rate(&control_obj) == 0, 2);
        assert!(control::get_admin(&control_obj) == signer::address_of(admin), 3);

        // Test pause
        control::pause(admin, &mut control_obj);
        assert!(control::is_paused(&control_obj), 4);

        // Test unpause
        control::unpause(admin, &mut control_obj);
        assert!(!control::is_paused(&control_obj), 5);

        // Test update fee rate
        control::update_fee_rate(admin, &mut control_obj, 100);
        assert!(control::get_fee_rate(&control_obj) == 100, 6);

        // Clean up
        let control_inner = object::remove(control_obj);
        control::drop_control(control_inner);
    }

    #[test(admin = @0x42, other = @0x43)]
    #[expected_failure(abort_code = 1)]
    fun test_control_invalid_admin(admin: &signer, other: &signer) {
        let control_obj = control::init_control(admin);
        
        // Try to pause with wrong admin
        control::pause(other, &mut control_obj);
        
        let control_inner = object::remove(control_obj);
        control::drop_control(control_inner);
    }

    #[test(admin = @0x42)]
    #[expected_failure(abort_code = 2)]
    fun test_control_invalid_fee_rate(admin: &signer) {
        let control_obj = control::init_control(admin);
        
        // Try to set invalid fee rate
        control::update_fee_rate(admin, &mut control_obj, 10001);
        
        let control_inner = object::remove(control_obj);
        control::drop_control(control_inner);
    }
} 