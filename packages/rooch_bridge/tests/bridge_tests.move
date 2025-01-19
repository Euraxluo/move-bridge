#[test_only]
module rooch_bridge::bridge_tests {
    use std::signer;
    use std::string;
    use std::option;
    use moveos_std::object::{Self, Object};
    use rooch_framework::coin;
    use rooch_framework::account_coin_store;
    use rooch_bridge::bridge;
    use rooch_bridge::asset;
    use rooch_bridge::message;

    struct TestCoinMeta has key, store {}

    struct TestCoin has key, store {
        id: Object<TestCoinMeta>,
        value: u256,
    }

    #[test(sender = @0x42)]
    fun test_bridge_transfer(sender: &signer) {
        // Setup
        let sender_addr = signer::address_of(sender);
        let amount = 100u256;
        let target_chain = 2u64;
        
        // Initialize bridge
        let bridge_obj = bridge::init_bridge_for_testing(1);
        
        // Register test coin
        let coin_info = coin::register_extend<TestCoin>(
            string::utf8(b"TestCoin"),
            string::utf8(b"TEST"),
            option::none(),
            8
        );
        
        // Create test coin
        let coin = coin::mint(&mut coin_info, amount);
        account_coin_store::deposit<TestCoin>(sender_addr, coin);

        // Lock coins and create message
        let coin = coin::mint(&mut coin_info, amount);
        let vault = asset::lock_coin<TestCoin>(sender, coin, target_chain);
        let message = message::create_message<TestCoin>(1, target_chain, std::vector::empty(), vault);

        // Verify message creation
        assert!(object::exists_object(object::id(&message)), 1);
        
        // Clean up
        let message_inner = object::remove(message);
        let vault = message::drop_message(message_inner);
        let vault_inner = object::remove(vault);
        asset::drop_vault(vault_inner);
        let bridge_inner = object::remove(bridge_obj);
        bridge::drop_bridge(bridge_inner);
        let final_coin = coin::mint(&mut coin_info, 0);
        account_coin_store::deposit(@0x0, final_coin);
        object::transfer(coin_info, @0x0);
    }

    #[test(sender = @0x42)]
    #[expected_failure(abort_code = 1)]
    fun test_bridge_transfer_same_chain(sender: &signer) {
        let amount = 100u256;
        let same_chain = 1u64;
        
        // Initialize bridge
        let bridge_obj = bridge::init_bridge_for_testing(same_chain);
        
        // Register test coin
        let coin_info = coin::register_extend<TestCoin>(
            string::utf8(b"TestCoin"),
            string::utf8(b"TEST"),
            option::none(),
            8
        );
        
        let coin = coin::mint(&mut coin_info, amount);
        let vault = asset::lock_coin<TestCoin>(sender, coin, same_chain);
        let message = message::create_message<TestCoin>(same_chain, same_chain, std::vector::empty(), vault);
        
        // Clean up
        let message_inner = object::remove(message);
        let vault = message::drop_message(message_inner);
        let vault_inner = object::remove(vault);
        asset::drop_vault(vault_inner);
        let bridge_inner = object::remove(bridge_obj);
        bridge::drop_bridge(bridge_inner);
        let final_coin = coin::mint(&mut coin_info, 0);
        account_coin_store::deposit(@0x0, final_coin);
        object::transfer(coin_info, @0x0);
    }
} 