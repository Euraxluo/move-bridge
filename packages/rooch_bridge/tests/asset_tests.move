#[test_only]
module rooch_bridge::asset_tests {
    use std::signer;
    use std::string;
    use std::option;
    use moveos_std::object::{Self, Object};
    use rooch_framework::coin;
    use rooch_framework::account_coin_store;
    use rooch_bridge::asset;

    struct TestCoinMeta has key, store {}

    struct TestCoin has key, store {
        id: Object<TestCoinMeta>,
        value: u256,
    }

    #[test(sender = @0x42)]
    fun test_lock_and_unlock_coin(sender: &signer) {
        // Setup
        let sender_addr = signer::address_of(sender);
        let amount = 100u256;
        let target_chain = 2u64;
        
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

        // Lock coins
        let coin = coin::mint(&mut coin_info, amount);
        let vault = asset::lock_coin<TestCoin>(
            sender,
            coin,
            target_chain
        );

        // Verify vault creation
        assert!(object::exists_object(object::id(&vault)), 1);

        // Unlock coins
        let unlocked_coin = asset::unlock_coin<TestCoin>(sender, vault, target_chain);
        assert!(coin::value(&unlocked_coin) == amount, 2);

        // Clean up
        account_coin_store::deposit<TestCoin>(sender_addr, unlocked_coin);
        let final_coin = coin::mint(&mut coin_info, 0);
        account_coin_store::deposit(@0x0, final_coin);
        object::transfer(coin_info, @0x0);
    }

    #[test(sender = @0x42)]
    #[expected_failure(abort_code = 1)]
    fun test_unlock_coin_wrong_chain(sender: &signer) {
        let amount = 100u256;
        let target_chain = 2u64;
        let wrong_chain = 3u64;
        
        // Register test coin
        let coin_info = coin::register_extend<TestCoin>(
            string::utf8(b"TestCoin"),
            string::utf8(b"TEST"),
            option::none(),
            8
        );
        
        let coin = coin::mint(&mut coin_info, amount);
        let vault = asset::lock_coin<TestCoin>(sender, coin, target_chain);
        
        // Try to unlock with wrong chain ID
        let unlocked_coin = asset::unlock_coin<TestCoin>(sender, vault, wrong_chain);
        account_coin_store::deposit<TestCoin>(signer::address_of(sender), unlocked_coin);
        let final_coin = coin::mint(&mut coin_info, 0);
        account_coin_store::deposit(@0x0, final_coin);
        object::transfer(coin_info, @0x0);
    }
} 