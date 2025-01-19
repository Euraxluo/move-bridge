#[test_only]
module sui_bridge::message_tests {
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    use sui_bridge::message::{Self, MessageConfig, Message};
    use std::vector;
    use sui::transfer;

    const ADMIN: address = @0xA;
    const USER: address = @0xB;
    
    const SOURCE_CHAIN: u64 = 1;
    const TARGET_CHAIN: u64 = 2;
    const MESSAGE_TYPE_ASSET: u8 = 1;

    fun test_scenario(): Scenario { test::begin(ADMIN) }

    #[test]
    fun test_message_creation() {
        let mut scenario = test_scenario();
        
        // 初始化配置
        next_tx(&mut scenario, ADMIN);
        {
            let mut config = message::initialize(ctx(&mut scenario));
            let payload = b"test payload";
            
            let msg = message::create_message(
                &mut config,
                MESSAGE_TYPE_ASSET,
                SOURCE_CHAIN,
                TARGET_CHAIN,
                payload,
                ctx(&mut scenario)
            );

            assert!(message::get_message_type(&msg) == MESSAGE_TYPE_ASSET, 0);
            assert!(message::get_source_chain(&msg) == SOURCE_CHAIN, 0);
            assert!(message::get_target_chain(&msg) == TARGET_CHAIN, 0);
            assert!(message::get_nonce(&msg) == 0, 0);
            assert!(message::get_payload(&msg) == payload, 0);

            transfer::public_transfer(config, USER);
        };
        test::end(scenario);
    }

    #[test]
    fun test_message_execution() {
        let mut scenario = test_scenario();
        
        // 初始化配置并测试消息执行
        next_tx(&mut scenario, ADMIN);
        {
            let mut config = message::initialize(ctx(&mut scenario));
            let payload = b"test payload";
            
            let msg = message::create_message(
                &mut config,
                MESSAGE_TYPE_ASSET,
                SOURCE_CHAIN,
                TARGET_CHAIN,
                payload,
                ctx(&mut scenario)
            );

            let msg_id = message::get_message_id(&msg);
            assert!(!message::is_message_executed(&config, &msg_id), 0);
            
            message::mark_message_executed(&mut config, &msg, ctx(&mut scenario));
            assert!(message::is_message_executed(&config, &msg_id), 0);

            transfer::public_transfer(config, USER);
        };
        test::end(scenario);
    }

    #[test]
    fun test_message_serialization() {
        let mut scenario = test_scenario();
        
        next_tx(&mut scenario, USER);
        {
            let payload = b"test payload";
            let msg_bytes = message::create_test_message(
                MESSAGE_TYPE_ASSET,
                SOURCE_CHAIN,
                TARGET_CHAIN,
                payload,
                ctx(&mut scenario)
            );

            let msg = message::deserialize_message(msg_bytes);
            assert!(message::get_message_type(&msg) == MESSAGE_TYPE_ASSET, 0);
            assert!(message::get_source_chain(&msg) == SOURCE_CHAIN, 0);
            assert!(message::get_target_chain(&msg) == TARGET_CHAIN, 0);
            assert!(message::get_payload(&msg) == payload, 0);
        };
        test::end(scenario);
    }
} 