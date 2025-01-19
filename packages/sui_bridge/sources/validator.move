module sui_bridge::validator {
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::table::{Self, Table};
    use sui::event;
    use sui::transfer;


    // 常量
    const DEFAULT_THRESHOLD: u64 = 2;

    // === 错误码 ===
    const EINVALID_ADMIN: u64 = 1;
    const EINVALID_VALIDATOR: u64 = 2;
    const EINVALID_WEIGHT: u64 = 4;
    const EINVALID_THRESHOLD: u64 = 4;
    const EINVALID_SIGNATURE: u64 = 5;
    const EVALID_ALREADY_VERIFIED: u64 = 6;

    // === 数据结构 ===
    public struct ValidatorConfig has key, store {
        id: UID,
        admin: address,
        threshold: u64,
        validators: Table<address, u64>,
        verified_messages: Table<vector<u8>, bool>,
    }

    // === 事件 ===
    public struct ValidatorAddedEvent has copy, drop {
        validator: address,
        weight: u64,
    }

    public struct ValidatorRemovedEvent has copy, drop {
        validator: address,
    }

    public struct ValidatorWeightUpdatedEvent has copy, drop {
        validator: address,
        weight: u64,
    }

    public struct MessageVerifiedEvent has copy, drop {
        message_id: vector<u8>,
    }

    // === 初始化 ===
    fun init(ctx: &mut TxContext) {
        let config = ValidatorConfig {
            id: object::new(ctx),
            admin: tx_context::sender(ctx),
            threshold: DEFAULT_THRESHOLD,
            validators: table::new(ctx),
            verified_messages: table::new(ctx),
        };
        transfer::public_share_object(config);
    }
        
    #[test_only]
    public fun init_for_test(ctx: &mut TxContext) {
        init(ctx)
    }

    // === 验证者管理 ===
    public fun add_validator(
        config: &mut ValidatorConfig,
        validator: address,
        weight: u64,
        ctx: &mut TxContext
    ) {
        // 验证管理员权限
        assert!(tx_context::sender(ctx) == config.admin, EINVALID_ADMIN);
        // 验证权重
        assert!(weight > 0, EINVALID_WEIGHT);

        // 添加验证者
        table::add(&mut config.validators, validator, weight);

        // 发出事件
        event::emit(ValidatorAddedEvent {
            validator,
            weight,
        });
    }

    public fun remove_validator(
        config: &mut ValidatorConfig,
        validator: address,
        ctx: &mut TxContext
    ) {
        // 验证管理员权限
        assert!(tx_context::sender(ctx) == config.admin, EINVALID_ADMIN);
        // 验证验证者存在
        assert!(table::contains(&config.validators, validator), EINVALID_VALIDATOR);

        // 移除验证者
        table::remove(&mut config.validators, validator);

        // 发出事件
        event::emit(ValidatorRemovedEvent {
            validator,
        });
    }

    public fun update_validator_weight(
        config: &mut ValidatorConfig,
        validator: address,
        weight: u64,
        ctx: &mut TxContext
    ) {
        // 验证管理员权限
        assert!(tx_context::sender(ctx) == config.admin, EINVALID_ADMIN);
        // 验证验证者存在
        assert!(table::contains(&config.validators, validator), EINVALID_VALIDATOR);
        // 验证权重
        assert!(weight > 0, EINVALID_WEIGHT);

        // 更新权重
        *table::borrow_mut(&mut config.validators, validator) = weight;

        // 发出事件
        event::emit(ValidatorWeightUpdatedEvent {
            validator,
            weight,
        });
    }

    // === 消息验证 ===
    public fun verify_message(
        config: &mut ValidatorConfig,
        message_id: vector<u8>,
        signatures: vector<vector<u8>>,
        ctx: &mut TxContext
    ): bool {
        // 验证消息未验证过
        assert!(!table::contains(&config.verified_messages, message_id), EVALID_ALREADY_VERIFIED);

        // TODO: 实现签名验证逻辑
        let _ = signatures;
        let _ = ctx;

        // 标记消息已验证
        table::add(&mut config.verified_messages, message_id, true);

        // 发出事件
        event::emit(MessageVerifiedEvent {
            message_id,
        });

        true
    }

    // === 查询函数 ===
    public fun get_threshold(config: &ValidatorConfig): u64 {
        config.threshold
    }

    public fun has_validator(config: &ValidatorConfig, validator: address): bool {
        table::contains(&config.validators, validator)
    }

    public fun get_validator_weight(config: &ValidatorConfig, validator: address): u64 {
        *table::borrow(&config.validators, validator)
    }
} 