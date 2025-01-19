module sui_bridge::asset {
    use sui::object::{Self, UID};
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::event;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::table::{Self, Table};
    use std::type_name::{Self, TypeName};
    use sui::bcs;

    // === 常量 ===
    const NATIVE_ASSET: u8 = 0;
    const EINVALID_AMOUNT: u64 = 1;
    const EASSET_ALREADY_REGISTERED: u64 = 2;

    // === 数据结构 ===
    public struct AdminCap has key {
        id: UID
    }

    public struct AssetRegistry has key {
        id: UID,
        assets: Table<TypeName, AssetInfo>
    }

    public struct AssetInfo has store {
        asset_type: u8,
        symbol: vector<u8>,
        decimals: u8
    }

    public struct AssetVault<phantom T> has key {
        id: UID,
        balance: Balance<T>
    }

    // === 事件 ===
    public struct AssetLockedEvent has copy, drop {
        asset_type: u8,
        symbol: vector<u8>,
        amount: u64,
        target_chain: u64
    }

    // === 初始化 ===
    fun init(ctx: &mut TxContext) {
        transfer::transfer(
            AdminCap { id: object::new(ctx) },
            tx_context::sender(ctx)
        );
        transfer::share_object(AssetRegistry {
            id: object::new(ctx),
            assets: table::new(ctx)
        });
    }

    #[test_only]
    public fun init_for_test(ctx: &mut TxContext) {
        init(ctx)
    }

    // === 资产注册 ===
    public fun register_native_asset<T>(
        _admin: &AdminCap,
        registry: &mut AssetRegistry,
        symbol: vector<u8>,
        decimals: u8,
        ctx: &mut TxContext
    ) {
        let asset_info = AssetInfo {
            asset_type: NATIVE_ASSET,
            symbol,
            decimals
        };
        
        let asset_type = type_name::get<T>();
        assert!(!table::contains(&registry.assets, asset_type), EASSET_ALREADY_REGISTERED);
        table::add(&mut registry.assets, asset_type, asset_info);

        // Create asset vault
        transfer::share_object(AssetVault<T> {
            id: object::new(ctx),
            balance: balance::zero()
        });
    }

    // === 资产操作 ===
    public fun lock_native_asset<T>(
        vault: &mut AssetVault<T>,
        registry: &AssetRegistry,
        coin: Coin<T>,
        target_chain: u64
    ) {
        let asset_type = type_name::get<T>();
        let asset_info = table::borrow(&registry.assets, asset_type);
        
        let amount = coin::value(&coin);
        assert!(amount > 0, EINVALID_AMOUNT);

        let coin_balance = coin::into_balance(coin);
        balance::join(&mut vault.balance, coin_balance);

        event::emit(AssetLockedEvent {
            asset_type: asset_info.asset_type,
            symbol: asset_info.symbol,
            amount,
            target_chain
        });
    }
} 