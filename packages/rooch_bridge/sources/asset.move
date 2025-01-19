/// Asset management module for cross-chain bridge
/// This module handles locking and unlocking of assets for cross-chain transfers
module rooch_bridge::asset {
    use std::signer;
    use moveos_std::object::{Self, Object, ObjectID};
    use moveos_std::event;
    use rooch_framework::coin::{Self, Coin};
    use rooch_framework::account_coin_store;

    const EINVALID_CHAIN_ID: u64 = 1;

    struct AssetVault<phantom CoinType> has key, store {
        id: ObjectID,
        amount: u256,
        target_chain: u64,
    }

    struct AssetLockedEvent has copy, drop, store {
        sender: address,
        amount: u256,
        target_chain: u64,
    }

    struct AssetUnlockedEvent has copy, drop, store {
        receiver: address,
        amount: u256,
        source_chain: u64,
    }

    public fun lock_coin<CoinType: key + store>(
        sender: &signer,
        coin: Coin<CoinType>,
        target_chain: u64,
    ): Object<AssetVault<CoinType>> {
        let amount = coin::value(&coin);
        let vault = AssetVault {
            id: object::named_object_id<AssetVault<CoinType>>(),
            amount,
            target_chain,
        };
        let vault_obj = object::new_named_object(vault);

        // Store coin in the vault's coin store
        account_coin_store::deposit(signer::address_of(sender), coin);

        // Emit event
        event::emit(
            AssetLockedEvent {
                sender: signer::address_of(sender),
                amount,
                target_chain,
            }
        );

        vault_obj
    }

    public fun unlock_coin<CoinType: key + store>(
        sender: &signer,
        vault: Object<AssetVault<CoinType>>,
        source_chain: u64,
    ): Coin<CoinType> {
        let AssetVault { id: _, amount, target_chain } = object::remove(vault);
        assert!(source_chain == target_chain, EINVALID_CHAIN_ID);

        // Withdraw coin from the vault's coin store
        let coin = account_coin_store::withdraw<CoinType>(sender, amount);

        // Emit event
        event::emit(
            AssetUnlockedEvent {
                receiver: signer::address_of(sender),
                amount,
                source_chain,
            }
        );

        coin
    }

    #[test_only]
    public fun test_lock_coin<CoinType: key + store>(
        sender: &signer,
        coin: Coin<CoinType>,
        target_chain: u64,
    ): Object<AssetVault<CoinType>> {
        lock_coin(sender, coin, target_chain)
    }

    #[test_only]
    public fun drop_vault<CoinType>(vault: AssetVault<CoinType>) {
        let AssetVault { id: _, amount: _, target_chain: _ } = vault;
    }
} 