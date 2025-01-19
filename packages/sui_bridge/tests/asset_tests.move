#[test_only]
module sui_bridge::asset_tests {
    use sui::test_scenario::{Self as test, next_tx, ctx};
    use sui::coin;
    use sui::sui::SUI;

    use sui_bridge::asset::{Self, AssetRegistry, AssetVault, AdminCap};

    // === 常量 ===
    const TARGET_CHAIN: u64 = 2;

    #[test]
    fun test_register_native_asset() {
        let admin = @0x1;
        let mut scenario = test::begin(admin);
        {
            asset::init_for_test(ctx(&mut scenario));
        };
        next_tx(&mut scenario, admin);
        {
            let mut registry = test::take_shared<AssetRegistry>(&scenario);
            let admin_cap = test::take_from_address<AdminCap>(&scenario, admin);

            asset::register_native_asset<SUI>(
                &admin_cap,
                &mut registry,
                b"SUI",
                9,
                ctx(&mut scenario)
            );

            test::return_shared(registry);
            test::return_to_address(admin, admin_cap);
        };
        test::end(scenario);
    }

    #[test]
    fun test_lock_and_unlock_native_asset() {
        let admin = @0x1;
        let mut scenario = test::begin(admin);
        {
            asset::init_for_test(ctx(&mut scenario));
        };
        next_tx(&mut scenario, admin);
        {
            let mut registry = test::take_shared<AssetRegistry>(&scenario);
            let admin_cap = test::take_from_address<AdminCap>(&scenario, admin);

            asset::register_native_asset<SUI>(
                &admin_cap,
                &mut registry,
                b"SUI",
                9,
                ctx(&mut scenario)
            );

            test::return_shared(registry);
            test::return_to_address(admin, admin_cap);
        };
        next_tx(&mut scenario, admin);
        {
            let registry = test::take_shared<AssetRegistry>(&scenario);
            let mut vault = test::take_shared<AssetVault<SUI>>(&scenario);
            let coin = coin::mint_for_testing<SUI>(1000, ctx(&mut scenario));

            asset::lock_native_asset(
                &mut vault,
                &registry,
                coin,
                TARGET_CHAIN
            );

            test::return_shared(registry);
            test::return_shared(vault);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 2, location = sui_bridge::asset)]
    fun test_register_native_asset_duplicate() {
        let admin = @0x1;
        let mut scenario = test::begin(admin);
        {
            asset::init_for_test(ctx(&mut scenario));
        };
        next_tx(&mut scenario, admin);
        {
            let mut registry = test::take_shared<AssetRegistry>(&scenario);
            let admin_cap = test::take_from_address<AdminCap>(&scenario, admin);

            asset::register_native_asset<SUI>(
                &admin_cap,
                &mut registry,
                b"SUI",
                9,
                ctx(&mut scenario)
            );

            asset::register_native_asset<SUI>(
                &admin_cap,
                &mut registry,
                b"SUI",
                9,
                ctx(&mut scenario)
            );

            test::return_shared(registry);
            test::return_to_address(admin, admin_cap);
        };
        test::end(scenario);
    }
} 