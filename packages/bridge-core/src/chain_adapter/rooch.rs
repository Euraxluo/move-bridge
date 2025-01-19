use async_trait::async_trait;
use crate::{
    types::{SignedMessage, MessageStatus, CrossChainMessage},
    Error,
    config::ChainConfig,
};
use super::ChainAdapter;
use std::time::Duration;
use tokio::time::sleep;

const MAX_RETRIES: u32 = 3;
const RETRY_DELAY: u64 = 2;

pub struct RoochAdapter {
    rpc_url: String,
}

impl RoochAdapter {
    pub async fn new(rpc_url: &str) -> Result<Self, Error> {
        Ok(Self {
            rpc_url: rpc_url.to_string(),
        })
    }

    async fn retry_with_backoff<F, Fut, T>(&self, operation: F) -> Result<T, Error>
    where
        F: Fn() -> Fut,
        Fut: std::future::Future<Output = Result<T, Error>>,
    {
        let mut retries = 0;
        loop {
            match operation().await {
                Ok(result) => return Ok(result),
                Err(e) => {
                    retries += 1;
                    if retries >= MAX_RETRIES {
                        return Err(e);
                    }
                    sleep(Duration::from_secs(RETRY_DELAY.pow(retries))).await;
                }
            }
        }
    }
}

#[async_trait]
impl ChainAdapter for RoochAdapter {
    fn chain_type(&self) -> &str {
        "rooch"
    }

    async fn listen_events(&self, config: &ChainConfig) -> Result<Vec<SignedMessage>, Error> {
        self.retry_with_backoff(|| async {
            let client = reqwest::Client::new();
            let response = client
                .post(&self.rpc_url)
                .json(&serde_json::json!({
                    "jsonrpc": "2.0",
                    "method": "rooch_getEvents",
                    "params": [
                        {
                            "address": config.bridge_address,
                            "start": 0,
                            "limit": 50
                        }
                    ],
                    "id": 1
                }))
                .send()
                .await
                .map_err(|e| Error::Chain(e.to_string()))?;

            let events: Vec<SignedMessage> = response
                .json()
                .await
                .map_err(|e| Error::Chain(e.to_string()))?;

            Ok(events)
        })
        .await
    }

    async fn submit_message(&self, config: &ChainConfig, message: SignedMessage) -> Result<(), Error> {
        self.retry_with_backoff(|| async {
            let client = reqwest::Client::new();
            let response = client
                .post(&self.rpc_url)
                .json(&serde_json::json!({
                    "jsonrpc": "2.0",
                    "method": "rooch_submitTransaction",
                    "params": [
                        {
                            "function": format!("{}::bridge::process_message", config.bridge_address),
                            "type_args": [],
                            "args": [
                                serde_json::to_value(&message).map_err(|e| Error::Serialization(e.to_string()))?
                            ]
                        }
                    ],
                    "id": 1
                }))
                .send()
                .await
                .map_err(|e| Error::Chain(e.to_string()))?;

            let result: serde_json::Value = response
                .json()
                .await
                .map_err(|e| Error::Chain(e.to_string()))?;

            if result.get("error").is_some() {
                return Err(Error::Chain(format!("Transaction failed: {:?}", result["error"])));
            }

            Ok(())
        })
        .await
    }

    async fn verify_message(&self, config: &ChainConfig, message: &SignedMessage) -> Result<MessageStatus, Error> {
        self.retry_with_backoff(|| async {
            let client = reqwest::Client::new();
            let response = client
                .post(&self.rpc_url)
                .json(&serde_json::json!({
                    "jsonrpc": "2.0",
                    "method": "rooch_getMessageStatus",
                    "params": [
                        {
                            "bridge_address": config.bridge_address,
                            "message_hash": hex::encode(message.signature.clone())
                        }
                    ],
                    "id": 1
                }))
                .send()
                .await
                .map_err(|e| Error::Chain(e.to_string()))?;

            let result: serde_json::Value = response
                .json()
                .await
                .map_err(|e| Error::Chain(e.to_string()))?;

            match result.get("result").and_then(|v| v.as_str()) {
                Some("processed") => Ok(MessageStatus::Processed),
                Some("failed") => Ok(MessageStatus::Failed),
                _ => Ok(MessageStatus::Pending),
            }
        })
        .await
    }
}