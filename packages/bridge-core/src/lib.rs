pub mod config;
pub mod types;
pub mod chain_adapter;
pub mod relayer;

pub use config::Config;
pub use types::{CrossChainMessage, SignedMessage, MessageStatus};

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("Config error: {0}")]
    Config(String),
    
    #[error("Chain error: {0}")]
    Chain(String),
    
    #[error("Network error: {0}")]
    Network(String),
    
    #[error("Serialization error: {0}")]
    Serialization(String),
}