use async_trait::async_trait;
use crate::{
    types::{SignedMessage, MessageStatus},
    Error,
    config::ChainConfig,
};

/// 链适配器特征，定义了与具体链交互所需的基本功能
#[async_trait]
pub trait ChainAdapter: Send + Sync {
    /// 获取链的类型标识
    fn chain_type(&self) -> &str;
    
    /// 监听链上事件
    async fn listen_events(&self, config: &ChainConfig) -> Result<Vec<SignedMessage>, Error>;
    
    /// 提交消息到链上
    async fn submit_message(&self, config: &ChainConfig, message: SignedMessage) -> Result<(), Error>;
    
    /// 验证消息状态
    async fn verify_message(&self, config: &ChainConfig, message: &SignedMessage) -> Result<MessageStatus, Error>;
}

/// 链适配器工厂，用于创建不同链的适配器实例
pub trait ChainAdapterFactory {
    fn create_adapter(&self, chain_type: &str) -> Result<Box<dyn ChainAdapter>, Error>;
}

// 注册所有支持的链适配器
pub mod sui;
pub mod rooch;

// 导出具体的适配器实现
pub use sui::SuiAdapter;
pub use rooch::RoochAdapter; 