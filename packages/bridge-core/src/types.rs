use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CrossChainMessage {
    pub nonce: u64,
    pub source_chain: String,
    pub target_chain: String,
    pub message_type: String,
    pub payload: Vec<u8>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SignedMessage {
    pub message: CrossChainMessage,
    pub signature: Vec<u8>,
    pub timestamp: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum MessageStatus {
    Pending,
    Processed,
    Failed,
} 