/// 安全控制模块
/// 本模块负责处理系统的安全相关功能，包括：
/// 1. 时间锁定机制的实现
/// 2. 操作类型的定义和管理
/// 3. 安全相关的常量配置
#[test_only]
module bridge_validator::security {
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use bridge_validator::types;

    // === 系统常量定义 ===
    /// 解质押操作的时间锁类型标识
    const TIMELOCK_UNSTAKE: u8 = 1;
    /// 时间锁定的持续时间（以epoch为单位）
    /// 在测试环境中设置为2个epoch，生产环境应该设置更长的时间
    const TIMELOCK_DURATION: u64 = 2;

    // === 公共函数 ===
    /// 获取解质押操作的时间锁类型标识
    /// 返回：解质押操作的类型标识（1）
    public fun get_unstake_action_type(): u8 {
        TIMELOCK_UNSTAKE
    }

    /// 创建新的时间锁定
    /// * `validator` - 时间锁定的目标验证器地址
    /// * `action_type` - 操作类型（例如：1表示解质押）
    /// * `ctx` - 交易上下文
    /// 返回：新创建的时间锁定对象
    public fun create_timelock(
        validator: address,
        action_type: u8,
        ctx: &mut TxContext
    ): types::TimeLock {
        let current_epoch = tx_context::epoch(ctx);
        types::new_timelock(
            validator,
            action_type,
            current_epoch + TIMELOCK_DURATION, // 锁定时间 = 当前epoch + 2
            ctx
        )
    }
} 