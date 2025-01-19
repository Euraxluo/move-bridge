/// Message module for cross-chain bridge
/// This module handles message creation and event emission for cross-chain communication
module rooch_bridge::message {
    use std::vector;
    use moveos_std::object::{Self, Object, ObjectID};
    use moveos_std::event;
    use rooch_bridge::asset::AssetVault;

    const EINVALID_CHAIN_ID: u64 = 1;

    struct Message<phantom CoinType> has key, store {
        id: ObjectID,
        source_chain: u64,
        target_chain: u64,
        receiver: vector<u8>,
        payload: Object<AssetVault<CoinType>>,
    }

    struct MessageSentEvent has copy, drop, store {
        source_chain: u64,
        target_chain: u64,
        receiver: vector<u8>,
        payload: vector<u8>,
    }

    public fun create_message<CoinType: key + store>(
        source_chain: u64,
        target_chain: u64,
        receiver: vector<u8>,
        payload: Object<AssetVault<CoinType>>,
    ): Object<Message<CoinType>> {
        assert!(source_chain != target_chain, EINVALID_CHAIN_ID);

        let message = Message {
            id: object::named_object_id<Message<CoinType>>(),
            source_chain,
            target_chain,
            receiver,
            payload,
        };
        let message_obj = object::new_named_object(message);

        // Emit event
        event::emit(
            MessageSentEvent {
                source_chain,
                target_chain,
                receiver,
                payload: vector::empty(),
            }
        );

        message_obj
    }

    #[test_only]
    public fun test_create_message<CoinType: key + store>(
        source_chain: u64,
        target_chain: u64,
        receiver: vector<u8>,
        payload: Object<AssetVault<CoinType>>,
    ): Object<Message<CoinType>> {
        create_message(source_chain, target_chain, receiver, payload)
    }

    #[test_only]
    public fun drop_message<CoinType>(message: Message<CoinType>): Object<AssetVault<CoinType>> {
        let Message { id: _, source_chain: _, target_chain: _, receiver: _, payload } = message;
        payload
    }
} 