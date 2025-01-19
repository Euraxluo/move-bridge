/// 跨链桥核心模块
/// 该模块实现了跨链消息的发送和接收功能，支持资产转移和通用消息
module sui_bridge::bridge {
    use sui::object::{Self, UID};
    use sui::coin::{Self, Coin};
    use sui::event;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui_bridge::message::{Self, MessageConfig};
    use sui_bridge::asset::{Self, AssetRegistry, AssetVault};
    use sui::bcs;
    use std::vector;

    // === 常量 ===
    const MESSAGE_TYPE_ASSET: u8 = 1;
    const EINVALID_CHAIN_ID: u64 = 1;
    const EINVALID_AMOUNT: u64 = 2;

    // === 数据结构 ===
    public struct Bridge has key {
        id: UID,
        chain_id: u64,
        message_config: MessageConfig
    }

    // === 事件 ===
    public struct CoinSentEvent<phantom T> has copy, drop {
        message_id: vector<u8>,
        coin_type: vector<u8>,
        amount: u64,
        receiver: vector<u8>,
        target_chain: u64
    }

    // === 初始化 ===
    fun init(ctx: &mut TxContext) {
        transfer::share_object(Bridge {
            id: object::new(ctx),
            chain_id: 1, // Sui chain ID
            message_config: message::initialize(ctx)
        });
    }
    
    #[test_only]
    public fun init_for_test(ctx: &mut TxContext) {
        init(ctx)
    }

    // === 公共函数 ===
    public entry fun send_coin<T>(
        bridge: &mut Bridge,
        registry: &AssetRegistry,
        vault: &mut AssetVault<T>,
        coin: Coin<T>,
        receiver: vector<u8>,
        target_chain: u64,
        ctx: &mut TxContext
    ) {
        // 验证链 ID
        assert!(bridge.chain_id != target_chain, EINVALID_CHAIN_ID);
        // 验证金额
        let amount = coin::value(&coin);
        assert!(amount > 0, EINVALID_AMOUNT);

        // 锁定代币
        asset::lock_native_asset(vault, registry, coin, target_chain);

        // 创建消息
        let payload = encode_asset_payload(receiver, amount);
        let message = message::create_message(
            &mut bridge.message_config,
            MESSAGE_TYPE_ASSET,
            bridge.chain_id,
            target_chain,
            payload,
            ctx
        );

        // 发出事件
        let message_id = message::get_message_id(&message);
        event::emit(CoinSentEvent<T> {
            message_id,
            coin_type: bcs::to_bytes(&0u8),
            amount,
            receiver,
            target_chain
        });
    }

    // === 内部函数 ===
    fun encode_asset_payload(receiver: vector<u8>, amount: u64): vector<u8> {
        let mut payload = vector::empty();
        vector::append(&mut payload, receiver);
        vector::append(&mut payload, bcs::to_bytes(&amount));
        payload
    }
} 