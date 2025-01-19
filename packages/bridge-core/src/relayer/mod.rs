use async_trait::async_trait;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use crate::{
    config::{Config, ChainConfig},
    types::{SignedMessage, MessageStatus},
    Error,
    chain_adapter::{ChainAdapter, SuiAdapter, RoochAdapter},
};
use tokio::time::{sleep, Duration};
use std::collections::HashSet;
use log::{info, error, warn};

#[async_trait]
pub trait ChainAdapterFactory: Send + Sync {
    async fn create_adapter(&self, config: &ChainConfig) -> Result<Box<dyn ChainAdapter>, Error>;
}

pub struct DefaultChainAdapterFactory;

#[async_trait]
impl ChainAdapterFactory for DefaultChainAdapterFactory {
    async fn create_adapter(&self, config: &ChainConfig) -> Result<Box<dyn ChainAdapter>, Error> {
        match config.adapter_type.as_str() {
            "sui" => {
                let adapter = SuiAdapter::new(config.clone()).await?;
                Ok(Box::new(adapter))
            }
            "rooch" => {
                let adapter = RoochAdapter::new(&config.rpc_url).await?;
                Ok(Box::new(adapter))
            }
            _ => Err(Error::Chain(format!("Unsupported adapter type: {}", config.adapter_type))),
        }
    }
}

pub struct Relayer {
    config: Config,
    chain_adapters: Arc<RwLock<HashMap<String, Box<dyn ChainAdapter>>>>,
}

impl Relayer {
    pub async fn new(config: Config) -> Result<Self, Error> {
        let mut chain_adapters = HashMap::new();
        let factory = DefaultChainAdapterFactory;

        for chain in &config.chains {
            let adapter = factory.create_adapter(chain).await?;
            chain_adapters.insert(chain.id.clone(), adapter);
        }

        Ok(Self {
            config,
            chain_adapters: Arc::new(RwLock::new(chain_adapters)),
        })
    }

    pub async fn start(&self) -> Result<(), Error> {
        info!("Starting relayer...");
        
        let adapters = self.chain_adapters.read().await;
        let mut processed_messages: HashSet<String> = HashSet::new();

        loop {
            for (chain_id, adapter) in adapters.iter() {
                match self.process_chain_events(chain_id, adapter.as_ref()).await {
                    Ok(messages) => {
                        for message in messages {
                            let message_id = hex::encode(&message.signature);
                            if !processed_messages.contains(&message_id) {
                                if let Err(e) = self.relay_message(chain_id, message.clone()).await {
                                    error!("Failed to relay message {}: {}", message_id, e);
                                    continue;
                                }
                                processed_messages.insert(message_id);
                            }
                        }
                    }
                    Err(e) => {
                        error!("Failed to process events for chain {}: {}", chain_id, e);
                    }
                }
            }

            sleep(Duration::from_secs(self.config.relayer.poll_interval)).await;
        }
    }

    async fn process_chain_events(&self, chain_id: &str, adapter: &dyn ChainAdapter) -> Result<Vec<SignedMessage>, Error> {
        let chain_config = self.config.get_chain_config(chain_id)
            .ok_or_else(|| Error::Config(format!("Chain config not found: {}", chain_id)))?;
        adapter.listen_events(chain_config).await
    }

    async fn relay_message(&self, source_chain_id: &str, message: SignedMessage) -> Result<(), Error> {
        let target_chain_id = &message.message.target_chain;
        let adapters = self.chain_adapters.read().await;
        let target_adapter = adapters
            .get(target_chain_id)
            .ok_or_else(|| Error::Chain(format!("Target chain adapter not found: {}", target_chain_id)))?;
        
        let target_config = self.config.get_chain_config(target_chain_id)
            .ok_or_else(|| Error::Config(format!("Chain config not found: {}", target_chain_id)))?;
        
        // 验证消息
        if let Err(e) = self.verify_message(&message).await {
            error!("Message verification failed: {}", e);
            return Err(e);
        }

        // 重试提交消息
        let mut retry_count = 0;
        let max_retries = self.config.relayer.max_retries;
        let base_delay = self.config.relayer.retry_delay;

        loop {
            match target_adapter.submit_message(target_config, message.clone()).await {
                Ok(_) => {
                    info!("Successfully relayed message from {} to {}", source_chain_id, target_chain_id);
                    return Ok(());
                }
                Err(e) => {
                    retry_count += 1;
                    if retry_count >= max_retries {
                        error!("Max retries ({}) reached for message relay. Last error: {}", max_retries, e);
                        return Err(Error::Chain(format!("Max retries reached: {}", e)));
                    }
                    
                    // 使用线性增长的重试延迟，避免等待时间过长
                    let delay = base_delay * retry_count as u64;
                    warn!("Retry {}/{} for message relay after {} seconds. Error: {}", 
                          retry_count, max_retries, delay, e);
                    sleep(Duration::from_secs(delay)).await;
                }
            }
        }
    }

    async fn verify_message(&self, message: &SignedMessage) -> Result<bool, Error> {
        // 验证时间戳
        let current_time = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_err(|e| Error::Chain(format!("Failed to get current time: {}", e)))?
            .as_secs();

        // 检查消息是否在有效时间窗口内（1小时内）
        if message.timestamp > current_time {
            return Err(Error::Chain("Message timestamp is in the future".to_string()));
        }
        if current_time - message.timestamp > 3600 {
            return Err(Error::Chain("Message has expired (older than 1 hour)".to_string()));
        }

        // 验证源链和目标链
        if !self.config.chains.iter().any(|c| c.id == message.message.source_chain) {
            return Err(Error::Chain(format!("Invalid source chain: {}", message.message.source_chain)));
        }
        if !self.config.chains.iter().any(|c| c.id == message.message.target_chain) {
            return Err(Error::Chain(format!("Invalid target chain: {}", message.message.target_chain)));
        }

        // 验证资产映射
        if message.message.message_type == "transfer" {
            let asset_configs = &self.config.assets;
            let valid_transfer = asset_configs.iter().any(|asset| {
                asset.native_chain == message.message.source_chain &&
                asset.mappings.contains_key(&message.message.target_chain)
            });
            if !valid_transfer {
                return Err(Error::Chain(format!(
                    "Invalid asset transfer mapping from {} to {}", 
                    message.message.source_chain, 
                    message.message.target_chain
                )));
            }
        }

        // TODO: 添加签名验证
        // 这里需要根据具体的签名方案实现验证逻辑

        Ok(true)
    }

    pub async fn process_message(&self, chain_id: &str, message: SignedMessage) -> Result<(), Error> {
        let chain_config = self.config.get_chain_config(chain_id)
            .ok_or_else(|| Error::Config(format!("Chain config not found: {}", chain_id)))?;
            
        let adapters = self.chain_adapters.read().await;
        if let Some(adapter) = adapters.get(chain_id) {
            adapter.submit_message(chain_config, message).await?;
            Ok(())
        } else {
            Err(Error::Chain(format!("Chain adapter not found: {}", chain_id)))
        }
    }
}