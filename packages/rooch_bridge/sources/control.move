module rooch_bridge::control {
    use std::signer;
    use moveos_std::object::{Self, Object, ObjectID};
    use moveos_std::event;

    const EINVALID_ADMIN: u64 = 1;
    const EINVALID_FEE_RATE: u64 = 2;

    struct BridgeControl has key, store {
        id: ObjectID,
        admin: address,
        paused: bool,
        fee_rate: u64,
    }

    struct BridgePausedEvent has copy, drop, store {
        admin: address,
    }

    struct BridgeUnpausedEvent has copy, drop, store {
        admin: address,
    }

    struct FeeRateUpdatedEvent has copy, drop, store {
        old_rate: u64,
        new_rate: u64,
    }

    public fun init_control(account: &signer): Object<BridgeControl> {
        let control = BridgeControl {
            id: object::named_object_id<BridgeControl>(),
            admin: signer::address_of(account),
            paused: false,
            fee_rate: 0
        };
        object::new_named_object(control)
    }

    public fun pause(account: &signer, control: &mut Object<BridgeControl>) {
        let admin = signer::address_of(account);
        let control_ref = object::borrow_mut(control);
        assert!(admin == control_ref.admin, EINVALID_ADMIN);
        control_ref.paused = true;
        event::emit(BridgePausedEvent { admin: control_ref.admin });
    }

    public fun unpause(account: &signer, control: &mut Object<BridgeControl>) {
        let admin = signer::address_of(account);
        let control_ref = object::borrow_mut(control);
        assert!(admin == control_ref.admin, EINVALID_ADMIN);
        control_ref.paused = false;
        event::emit(BridgeUnpausedEvent { admin: control_ref.admin });
    }

    public fun update_fee_rate(account: &signer, control: &mut Object<BridgeControl>, new_rate: u64) {
        let admin = signer::address_of(account);
        let control_ref = object::borrow_mut(control);
        assert!(admin == control_ref.admin, EINVALID_ADMIN);
        assert!(new_rate <= 10000, EINVALID_FEE_RATE); // Fee rate should be in basis points (0-10000)
        let old_rate = control_ref.fee_rate;
        control_ref.fee_rate = new_rate;
        event::emit(FeeRateUpdatedEvent { old_rate, new_rate });
    }

    public fun is_paused(control: &Object<BridgeControl>): bool {
        object::borrow(control).paused
    }

    public fun get_fee_rate(control: &Object<BridgeControl>): u64 {
        object::borrow(control).fee_rate
    }

    public fun get_admin(control: &Object<BridgeControl>): address {
        object::borrow(control).admin
    }

    #[test_only]
    public fun drop_control(control: BridgeControl) {
        let BridgeControl { id: _, admin: _, paused: _, fee_rate: _ } = control;
    }
} 