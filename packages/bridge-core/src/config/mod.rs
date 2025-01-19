use serde::{Deserialize, Serialize};
use std::path::Path;
use std::collections::HashMap;
use crate::Error;

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct EventFilter {
    pub name: String,
    pub handler: String,
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct ChainConfig {
    pub id: String,
    #[serde(rename = "adapter_type")]
    pub adapter_type: String,
    pub name: String,
    pub rpc_url: String,
    pub bridge_address: String,
    pub event_filters: Vec<EventFilter>,
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct AssetConfig {
    pub name: String,
    pub native_chain: String,
    pub type_: String,
    pub decimals: u8,
    pub mappings: HashMap<String, String>,
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct ValidatorConfig {
    pub address: String,
    pub public_key: String,
    pub weight: u64,
    pub chains: Vec<String>,
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct RelayerConfig {
    pub poll_interval: u64,
    pub max_retries: u32,
    pub retry_delay: u64,
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct Config {
    pub chains: Vec<ChainConfig>,
    pub assets: Vec<AssetConfig>,
    pub validators: Vec<ValidatorConfig>,
    pub relayer: RelayerConfig,
}

impl Config {
    pub fn load<P: AsRef<Path>>(config_path: P) -> Result<Self, Error> {
        let config_str = std::fs::read_to_string(config_path)
            .map_err(|e| Error::Config(format!("Failed to read config file: {}", e)))?;
        
        let config: Config = serde_json::from_str(&config_str)
            .map_err(|e| Error::Config(format!("Failed to parse config file: {}", e)))?;
        
        // 验证配置
        config.validate()?;
        
        Ok(config)
    }

    fn validate(&self) -> Result<(), Error> {
        // 验证链配置
        let chain_ids: Vec<_> = self.chains.iter().map(|c| &c.id).collect();
        for chain in &self.chains {
            if !["sui", "rooch"].contains(&chain.adapter_type.as_str()) {
                return Err(Error::Config(format!("Invalid adapter type: {}", chain.adapter_type)));
            }
        }

        // 验证资产配置
        for asset in &self.assets {
            if !chain_ids.contains(&&asset.native_chain) {
                return Err(Error::Config(format!("Invalid chain ID in asset config: {}", asset.native_chain)));
            }
            
            // 验证资产映射
            for (chain_id, _) in &asset.mappings {
                if !chain_ids.contains(&chain_id) {
                    return Err(Error::Config(format!("Invalid chain ID in asset mapping: {}", chain_id)));
                }
            }
        }

        // 验证验证者配置
        for validator in &self.validators {
            // 验证公钥格式
            if hex::decode(&validator.public_key).is_err() {
                return Err(Error::Config(format!("Invalid public key: {}", validator.public_key)));
            }
            
            // 验证支持的链
            for chain in &validator.chains {
                if !chain_ids.contains(&chain) {
                    return Err(Error::Config(format!("Invalid chain ID in validator config: {}", chain)));
                }
            }
        }

        // 验证中继器配置
        if self.relayer.poll_interval == 0 {
            return Err(Error::Config("Relayer poll interval must be greater than 0".to_string()));
        }
        if self.relayer.max_retries == 0 {
            return Err(Error::Config("Relayer max retries must be greater than 0".to_string()));
        }

        Ok(())
    }

    pub fn get_chain_config(&self, chain_id: &str) -> Option<&ChainConfig> {
        self.chains.iter().find(|c| c.id == chain_id)
    }

    pub fn get_asset_config(&self, asset_name: &str) -> Option<&AssetConfig> {
        self.assets.iter().find(|a| a.name == asset_name)
    }

    pub fn get_validators_for_chain(&self, chain_id: &str) -> Vec<&ValidatorConfig> {
        self.validators
            .iter()
            .filter(|v| v.chains.contains(&chain_id.to_string()))
            .collect()
    }
} 