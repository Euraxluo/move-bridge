module sui_bridge::message {
    use sui::object::{Self, UID};
    use sui::tx_context::{Self,TxContext};
    use sui::table::{Self, Table};
    use sui::event;
    use sui::bcs;
    use sui::hash;
    use std::vector;
    use sui::transfer;

    // === 常量 ===
    const MESSAGE_TYPE_ASSET: u8 = 1;

    // === 错误码 ===
    const EINVALID_MESSAGE_TYPE: u64 = 1;
    const EINVALID_CHAIN_ID: u64 = 2;
    const EINVALID_PAYLOAD: u64 = 4;
    const EMESSAGE_ALREADY_EXECUTED: u64 = 5;

    // === 数据结构 ===
    public struct MessageConfig has key, store {
        id: UID,
        nonce: u64,
        executed_messages: Table<vector<u8>, bool>,
    }

    public struct Message has store, copy, drop {
        message_type: u8,
        source_chain: u64,
        target_chain: u64,
        nonce: u64,
        payload: vector<u8>,
    }

    // === 事件 ===
    public struct MessageSentEvent has copy, drop {
        message_id: vector<u8>,
        message_type: u8,
        source_chain: u64,
        target_chain: u64,
        nonce: u64,
        payload: vector<u8>,
    }

    public struct MessageExecutedEvent has copy, drop {
        message_id: vector<u8>,
        message_type: u8,
        source_chain: u64,
        target_chain: u64,
        nonce: u64,
    }

    // === 初始化 ===
    public(package) fun initialize(ctx: &mut TxContext) :MessageConfig {
        MessageConfig {
            id: object::new(ctx),
            nonce: 0,
            executed_messages: table::new(ctx),
        }
    }

    // === 消息创建 ===
    public fun create_message(
        config: &mut MessageConfig,
        message_type: u8,
        source_chain: u64,
        target_chain: u64,
        payload: vector<u8>,
        _ctx: &mut TxContext
    ): Message {
        // 验证消息类型
        assert!(message_type == MESSAGE_TYPE_ASSET, EINVALID_MESSAGE_TYPE);
        // 验证链 ID
        assert!(source_chain != target_chain, EINVALID_CHAIN_ID);
        // 验证 payload 不为空
        assert!(!vector::is_empty(&payload), EINVALID_PAYLOAD);

        // 获取并递增 nonce
        let nonce = config.nonce;
        config.nonce = nonce + 1;

        // 创建消息
        let message = Message {
            message_type,
            source_chain,
            target_chain,
            nonce,
            payload,
        };

        // 发出事件
        event::emit(MessageSentEvent {
            message_id: get_message_id(&message),
            message_type,
            source_chain,
            target_chain,
            nonce,
            payload,
        });

        message
    }

    // === 消息执行 ===
    public fun mark_message_executed(
        config: &mut MessageConfig,
        message: &Message,
        _ctx: &mut TxContext
    ) {
        let message_id = get_message_id(message);
        assert!(!is_message_executed(config, &message_id), EMESSAGE_ALREADY_EXECUTED);

        // 标记消息已执行
        table::add(&mut config.executed_messages, message_id, true);

        // 发出事件
        event::emit(MessageExecutedEvent {
            message_id,
            message_type: message.message_type,
            source_chain: message.source_chain,
            target_chain: message.target_chain,
            nonce: message.nonce,
        });
    }

    // === 序列化函数 ===
    public fun serialize_message(message: &Message): vector<u8> {
        let mut bytes = vector::empty();
        vector::append(&mut bytes, bcs::to_bytes(&message.message_type));
        vector::append(&mut bytes, bcs::to_bytes(&message.source_chain));
        vector::append(&mut bytes, bcs::to_bytes(&message.target_chain));
        vector::append(&mut bytes, bcs::to_bytes(&message.nonce));
        vector::append(&mut bytes, message.payload);
        bytes
    }

    public fun deserialize_message(bytes: vector<u8>): Message {
        let mut bcs_parser = bcs::new(bytes);
        let message_type = bcs::peel_u8(&mut bcs_parser);
        let source_chain = bcs::peel_u64(&mut bcs_parser);
        let target_chain = bcs::peel_u64(&mut bcs_parser);
        let nonce = bcs::peel_u64(&mut bcs_parser);
        let payload = bcs::into_remainder_bytes(bcs_parser);

        assert!(message_type == MESSAGE_TYPE_ASSET, EINVALID_MESSAGE_TYPE);

        Message {
            message_type,
            source_chain,
            target_chain,
            nonce,
            payload,
        }
    }

    // === 查询函数 ===
    public fun is_message_executed(config: &MessageConfig, message_id: &vector<u8>): bool {
        table::contains(&config.executed_messages, *message_id)
    }

    public fun get_message_id(message: &Message): vector<u8> {
        let bytes = serialize_message(message);
        hash::blake2b256(&bytes)
    }

    public fun get_message_type(message: &Message): u8 {
        message.message_type
    }

    public fun get_source_chain(message: &Message): u64 {
        message.source_chain
    }

    public fun get_target_chain(message: &Message): u64 {
        message.target_chain
    }

    public fun get_nonce(message: &Message): u64 {
        message.nonce
    }

    public fun get_payload(message: &Message): vector<u8> {
        message.payload
    }

    // === 测试函数 ===
    #[test_only]
    public fun create_test_message(
        message_type: u8,
        source_chain: u64,
        target_chain: u64,
        payload: vector<u8>,
        _ctx: &mut TxContext
    ): vector<u8> {
        let message = Message {
            message_type,
            source_chain,
            target_chain,
            nonce: 0,
            payload,
        };
        serialize_message(&message)
    }
} 