/// 控制模块
/// 该模块负责跨链桥的安全控制和治理功能
/// 包含紧急暂停、费用管理等核心功能
module sui_bridge::control {
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::event;
    use sui::transfer;

    // === 错误码 ===
    const EINVALID_ADMIN: u64 = 1;
    const EINVALID_FEE: u64 = 2;
    const EBRIDGE_PAUSED: u64 = 3;
    const EBRIDGE_NOT_PAUSED: u64 = 4;

    // === 数据结构 ===
    public struct ControlConfig has key, store {
        id: UID,
        admin: address,
        paused: bool,
        fee_rate: u64,
    }

    // === 事件 ===
    public struct BridgePausedEvent has copy, drop {
        admin: address,
    }

    public struct BridgeUnpausedEvent has copy, drop {
        admin: address,
    }

    public struct AdminChangedEvent has copy, drop {
        old_admin: address,
        new_admin: address,
    }

    public struct FeeRateChangedEvent has copy, drop {
        old_rate: u64,
        new_rate: u64,
    }

    // === 初始化 ===
    fun init(ctx: &mut TxContext) {
        let config = ControlConfig {
            id: object::new(ctx),
            admin: tx_context::sender(ctx),
            paused: false,
            fee_rate: 0,
        };
        transfer::public_share_object(config);
    }

    #[test_only]
    public fun init_for_test(ctx: &mut TxContext) {
        init(ctx)
    }

    // === 控制函数 ===
    public fun pause_bridge(config: &mut ControlConfig, ctx: &TxContext) {
        // 验证管理员权限
        assert!(tx_context::sender(ctx) == config.admin, EINVALID_ADMIN);
        // 验证桥未暂停
        assert!(!config.paused, EBRIDGE_NOT_PAUSED);

        // 暂停桥
        config.paused = true;

        // 发出事件
        event::emit(BridgePausedEvent {
            admin: config.admin,
        });
    }

    public fun unpause_bridge(config: &mut ControlConfig, ctx: &TxContext) {
        // 验证管理员权限
        assert!(tx_context::sender(ctx) == config.admin, EINVALID_ADMIN);
        // 验证桥已暂停
        assert!(config.paused, EBRIDGE_PAUSED);

        // 恢复桥
        config.paused = false;

        // 发出事件
        event::emit(BridgeUnpausedEvent {
            admin: config.admin,
        });
    }

    public fun set_admin(config: &mut ControlConfig, new_admin: address, ctx: &TxContext) {
        // 验证管理员权限
        assert!(tx_context::sender(ctx) == config.admin, EINVALID_ADMIN);
        assert!(new_admin != @0x0, EINVALID_ADMIN);

        let old_admin = config.admin;
        config.admin = new_admin;

        // 发出事件
        event::emit(AdminChangedEvent {
            old_admin,
            new_admin,
        });
    }

    public fun set_fee_rate(config: &mut ControlConfig, new_rate: u64, ctx: &TxContext) {
        // 验证管理员权限
        assert!(tx_context::sender(ctx) == config.admin, EINVALID_ADMIN);
        // 验证费率合法性 (0-10000, 即0-100%)
        assert!(new_rate <= 10000, EINVALID_FEE);

        let old_rate = config.fee_rate;
        config.fee_rate = new_rate;

        // 发出事件
        event::emit(FeeRateChangedEvent {
            old_rate,
            new_rate,
        });
    }

    // === 查询函数 ===
    public fun is_paused(config: &ControlConfig): bool {
        config.paused
    }

    public fun get_admin(config: &ControlConfig): address {
        config.admin
    }

    public fun get_fee_rate(config: &ControlConfig): u64 {
        config.fee_rate
    }

    // === 内部函数 ===
    public(package) fun assert_not_paused(config: &ControlConfig) {
        assert!(!config.paused, EBRIDGE_PAUSED);
    }

    public(package) fun calculate_fee(config: &ControlConfig, amount: u64): u64 {
        (amount * config.fee_rate) / 10000
    }
} 