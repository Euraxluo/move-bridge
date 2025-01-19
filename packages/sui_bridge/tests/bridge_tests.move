#[test_only]
module sui_bridge::bridge_tests {
    use sui::test_scenario::{Self as test, next_tx, ctx};
    use sui::coin;
    use sui::sui::SUI;
    use sui::bcs;

    use sui_bridge::bridge::{Self, Bridge};
    use sui_bridge::asset::{Self, AssetRegistry, AssetVault, AdminCap};
    use sui_bridge::message;

    // === 常量 ===
    const TARGET_CHAIN: u64 = 2;
    const TEST_RECEIVER: address = @0x42;

    #[test]
    fun test_bridge_init() {
        let admin = @0x1;
        let mut scenario = test::begin(admin);
        {
            bridge::init_for_test(ctx(&mut scenario));
            asset::init_for_test(ctx(&mut scenario));
        };
        test::end(scenario);
    }

    #[test]
    fun test_send_coin() {
        let admin = @0x1;
        let mut scenario = test::begin(admin);
        {
            // 初始化
            bridge::init_for_test(ctx(&mut scenario));
            asset::init_for_test(ctx(&mut scenario));
        };
        next_tx(&mut scenario, admin);
        {
            // 获取对象
            let bridge = test::take_shared<Bridge>(&scenario);
            let mut registry = test::take_shared<AssetRegistry>(&scenario);
            let admin_cap = test::take_from_address<AdminCap>(&scenario, admin);

            // 注册资产
            asset::register_native_asset<SUI>(
                &admin_cap,
                &mut registry,
                b"SUI",
                9,
                ctx(&mut scenario)
            );

            test::return_shared(bridge);
            test::return_shared(registry);
            test::return_to_address(admin, admin_cap);
        };
        next_tx(&mut scenario, admin);
        {
            // 获取对象
            let mut bridge = test::take_shared<Bridge>(&scenario);
            let registry = test::take_shared<AssetRegistry>(&scenario);
            let mut vault = test::take_shared<AssetVault<SUI>>(&scenario);

            // 创建测试代币
            let coin = coin::mint_for_testing<SUI>(1000, ctx(&mut scenario));
            let receiver_bytes = bcs::to_bytes(&TEST_RECEIVER);

            // 发送代币
            bridge::send_coin(
                &mut bridge,
                &registry,
                &mut vault,
                coin,
                receiver_bytes,
                TARGET_CHAIN,
                ctx(&mut scenario)
            );

            // 清理
            test::return_shared(bridge);
            test::return_shared(registry);
            test::return_shared(vault);
        };
        test::end(scenario);
    }
} 