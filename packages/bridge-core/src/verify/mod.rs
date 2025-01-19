use ed25519_dalek::{Keypair, PublicKey, SecretKey, Signature, Signer, Verifier};
use rand::rngs::OsRng;
use blake2::{Blake2b512, Digest};
use std::time::{SystemTime, UNIX_EPOCH};
use tracing::{info, warn, error, debug};
use crate::{
    types::{CrossChainMessage, SignedMessage, ChainType},
    Result, BridgeError,
};

const MAX_MESSAGE_AGE: u64 = 3600; // 消息最大有效期（1小时）
const MIN_NONCE: u64 = 1; // 最小nonce值

/// 验证器配置
#[derive(Debug, Clone)]
pub struct VerifierConfig {
    pub max_message_age: u64,
    pub allowed_source_chains: Vec<ChainType>,
    pub allowed_target_chains: Vec<ChainType>,
}

impl Default for VerifierConfig {
    fn default() -> Self {
        Self {
            max_message_age: MAX_MESSAGE_AGE,
            allowed_source_chains: vec![ChainType::Sui, ChainType::Rooch],
            allowed_target_chains: vec![ChainType::Sui, ChainType::Rooch],
        }
    }
}

/// 验证器结构体
pub struct MessageVerifier {
    keypair: Keypair,
    config: VerifierConfig,
    last_processed_nonce: u64,
}

impl MessageVerifier {
    /// 创建新的验证器实例
    pub fn new() -> Self {
        info!("Creating new message verifier instance");
        let mut csprng = OsRng {};
        let keypair: Keypair = Keypair::generate(&mut csprng);
        Self { 
            keypair,
            config: VerifierConfig::default(),
            last_processed_nonce: 0,
        }
    }

    /// 从已有的密钥对创建验证器
    pub fn from_keypair(secret_key: &[u8], config: Option<VerifierConfig>) -> Result<Self> {
        debug!("Creating verifier from existing keypair");
        let secret = SecretKey::from_bytes(secret_key)
            .map_err(|e| {
                error!("Failed to create secret key: {}", e);
                BridgeError::ValidationError(format!("Invalid secret key: {}", e))
            })?;
        let public = PublicKey::from(&secret);
        let keypair = Keypair {
            secret,
            public,
        };
        Ok(Self { 
            keypair,
            config: config.unwrap_or_default(),
            last_processed_nonce: 0,
        })
    }

    /// 获取公钥
    pub fn public_key(&self) -> [u8; 32] {
        self.keypair.public.to_bytes()
    }

    /// 验证消息的基本属性
    fn validate_message_properties(&self, message: &CrossChainMessage) -> Result<()> {
        // 验证链类型
        if !self.config.allowed_source_chains.contains(&message.source_chain) {
            warn!("Invalid source chain: {:?}", message.source_chain);
            return Err(BridgeError::ValidationError("Invalid source chain".to_string()));
        }
        if !self.config.allowed_target_chains.contains(&message.target_chain) {
            warn!("Invalid target chain: {:?}", message.target_chain);
            return Err(BridgeError::ValidationError("Invalid target chain".to_string()));
        }

        // 验证nonce
        if message.nonce <= self.last_processed_nonce || message.nonce < MIN_NONCE {
            warn!("Invalid nonce: {}", message.nonce);
            return Err(BridgeError::ValidationError("Invalid nonce".to_string()));
        }

        Ok(())
    }

    /// 对消息进行签名
    pub fn sign_message(&self, message: CrossChainMessage) -> Result<SignedMessage> {
        debug!("Signing message with nonce: {}", message.nonce);
        
        // 验证消息属性
        self.validate_message_properties(&message)?;
        
        // 序列化消息
        let message_bytes = serde_json::to_vec(&message)
            .map_err(|e| {
                error!("Failed to serialize message: {}", e);
                BridgeError::SerializationError(e.to_string())
            })?;
        
        // 计算消息哈希
        let mut hasher = Blake2b512::new();
        hasher.update(&message_bytes);
        let message_hash = hasher.finalize();
        
        // 签名消息哈希
        let signature = self.keypair.sign(&message_hash).to_bytes().to_vec();
        
        let signed_message = SignedMessage::new(message, signature);
        info!("Message signed successfully, nonce: {}", signed_message.message.nonce);
        
        Ok(signed_message)
    }

    /// 批量签名消息
    pub fn sign_messages(&self, messages: Vec<CrossChainMessage>) -> Vec<Result<SignedMessage>> {
        info!("Batch signing {} messages", messages.len());
        messages.into_iter()
            .map(|msg| self.sign_message(msg))
            .collect()
    }

    /// 验证签名消息
    pub fn verify_message(&mut self, signed_message: &SignedMessage) -> Result<bool> {
        debug!("Verifying message with nonce: {}", signed_message.message.nonce);
        
        // 验证消息时间戳
        let current_time = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();
            
        if current_time - signed_message.timestamp > self.config.max_message_age {
            warn!("Message expired: timestamp={}", signed_message.timestamp);
            return Ok(false);
        }

        // 验证消息属性
        self.validate_message_properties(&signed_message.message)?;
        
        // 序列化原始消息
        let message_bytes = serde_json::to_vec(&signed_message.message)
            .map_err(|e| {
                error!("Failed to serialize message: {}", e);
                BridgeError::SerializationError(e.to_string())
            })?;
        
        // 计算消息哈希
        let mut hasher = Blake2b512::new();
        hasher.update(&message_bytes);
        let message_hash = hasher.finalize();
        
        // 解析签名
        let signature = Signature::from_bytes(&signed_message.signature)
            .map_err(|e| {
                error!("Invalid signature format: {}", e);
                BridgeError::ValidationError(format!("Invalid signature: {}", e))
            })?;
        
        // 验证签名
        match self.keypair.public.verify(&message_hash, &signature) {
            Ok(_) => {
                info!("Message verified successfully, nonce: {}", signed_message.message.nonce);
                self.last_processed_nonce = signed_message.message.nonce;
                Ok(true)
            }
            Err(e) => {
                warn!("Signature verification failed: {}", e);
                Ok(false)
            }
        }
    }

    /// 批量验证消息
    pub fn verify_messages(&mut self, messages: Vec<SignedMessage>) -> Vec<Result<bool>> {
        info!("Batch verifying {} messages", messages.len());
        messages.iter()
            .map(|msg| self.verify_message(msg))
            .collect()
    }

    /// 导出验证器配置
    pub fn export_config(&self) -> VerifierConfig {
        self.config.clone()
    }

    /// 更新验证器配置
    pub fn update_config(&mut self, config: VerifierConfig) {
        info!("Updating verifier configuration");
        self.config = config;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::MessageType;
    use std::time::Duration;
    use std::thread;

    // 基本功能测试
    #[test]
    fn test_message_signing_and_verification() {
        let mut verifier = MessageVerifier::new();
        let message = CrossChainMessage::new(
            ChainType::Sui,
            ChainType::Rooch,
            MessageType::AssetTransfer,
            1,
            verifier.public_key(),
            vec![1, 2, 3],
        );
        
        let signed_message = verifier.sign_message(message).unwrap();
        assert!(verifier.verify_message(&signed_message).unwrap());
    }

    // 无效签名测试
    #[test]
    fn test_invalid_signature() {
        let verifier1 = MessageVerifier::new();
        let mut verifier2 = MessageVerifier::new();
        
        let message = CrossChainMessage::new(
            ChainType::Sui,
            ChainType::Rooch,
            MessageType::AssetTransfer,
            1,
            verifier1.public_key(),
            vec![1, 2, 3],
        );
        let signed_message = verifier1.sign_message(message).unwrap();
        
        assert!(!verifier2.verify_message(&signed_message).unwrap());
    }

    // 消息过期测试
    #[test]
    fn test_message_expiration() {
        let mut config = VerifierConfig::default();
        config.max_message_age = 0; // 立即过期
        let mut verifier = MessageVerifier::from_keypair(
            &[1u8; 32],
            Some(config)
        ).unwrap();
        
        let message = CrossChainMessage::new(
            ChainType::Sui,
            ChainType::Rooch,
            MessageType::AssetTransfer,
            1,
            verifier.public_key(),
            vec![1, 2, 3],
        );
        
        let signed_message = verifier.sign_message(message).unwrap();
        thread::sleep(Duration::from_secs(1));
        assert!(!verifier.verify_message(&signed_message).unwrap());
    }

    // 批量操作测试
    #[test]
    fn test_batch_operations() {
        let mut verifier = MessageVerifier::new();
        let messages: Vec<_> = (1..=3)
            .map(|i| CrossChainMessage::new(
                ChainType::Sui,
                ChainType::Rooch,
                MessageType::AssetTransfer,
                i as u64,
                verifier.public_key(),
                vec![i as u8],
            ))
            .collect();
        
        let signed_messages: Vec<_> = verifier.sign_messages(messages)
            .into_iter()
            .filter_map(Result::ok)
            .collect();
            
        let verification_results = verifier.verify_messages(signed_messages);
        assert!(verification_results.iter().all(|r| r.as_ref().unwrap_or(&false) == &true));
    }

    // 配置测试
    #[test]
    fn test_verifier_config() {
        let mut config = VerifierConfig::default();
        config.allowed_source_chains = vec![ChainType::Sui];
        config.allowed_target_chains = vec![ChainType::Rooch];
        
        let verifier = MessageVerifier::from_keypair(&[1u8; 32], Some(config.clone())).unwrap();
        
        // 测试有效配置
        let valid_message = CrossChainMessage::new(
            ChainType::Sui,
            ChainType::Rooch,
            MessageType::AssetTransfer,
            1,
            verifier.public_key(),
            vec![1, 2, 3],
        );
        assert!(verifier.sign_message(valid_message).is_ok());
        
        // 测试无效配置
        let invalid_message = CrossChainMessage::new(
            ChainType::Rooch, // 不允许的源链
            ChainType::Sui,   // 不允许的目标链
            MessageType::AssetTransfer,
            2,
            verifier.public_key(),
            vec![1, 2, 3],
        );
        assert!(verifier.sign_message(invalid_message).is_err());
    }

    // Nonce测试
    #[test]
    fn test_nonce_validation() {
        let mut verifier = MessageVerifier::new();
        
        // 测试正常nonce递增
        for i in 1..=5 {
            let message = CrossChainMessage::new(
                ChainType::Sui,
                ChainType::Rooch,
                MessageType::AssetTransfer,
                i,
                verifier.public_key(),
                vec![1, 2, 3],
            );
            let signed = verifier.sign_message(message).unwrap();
            assert!(verifier.verify_message(&signed).unwrap());
        }
        
        // 测试重复nonce
        let message = CrossChainMessage::new(
            ChainType::Sui,
            ChainType::Rooch,
            MessageType::AssetTransfer,
            3, // 已使用的nonce
            verifier.public_key(),
            vec![1, 2, 3],
        );
        assert!(verifier.sign_message(message).is_err());
    }
} 