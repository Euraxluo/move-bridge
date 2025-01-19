/// Core module for cross-chain bridge
/// This module implements cross-chain message sending and receiving functionality,
/// supporting asset transfer and general message passing
module rooch_bridge::bridge {
    use moveos_std::object::{Self, Object, ObjectID};

    struct Bridge has key, store {
        id: ObjectID,
        chain_id: u64,
    }

    struct BridgeEvent has copy, drop, store {
        source_chain: u64,
        target_chain: u64,
        amount: u256,
    }

    public fun init_bridge(chain_id: u64): Object<Bridge> {
        let bridge = Bridge {
            id: object::named_object_id<Bridge>(),
            chain_id,
        };
        object::new_named_object(bridge)
    }

    public fun chain_id(bridge: &Object<Bridge>): u64 {
        object::borrow(bridge).chain_id
    }

    public fun verify_chain_id(bridge: &Object<Bridge>, chain_id: u64): bool {
        object::borrow(bridge).chain_id == chain_id
    }

    #[test_only]
    public fun init_bridge_for_testing(chain_id: u64): Object<Bridge> {
        init_bridge(chain_id)
    }

    #[test_only]
    public fun drop_bridge(bridge: Bridge) {
        let Bridge { id: _, chain_id: _ } = bridge;
    }
} 