use async_trait::async_trait;
use std::str::FromStr;
use sui_sdk::{
    SuiClient, SuiClientBuilder,
    rpc_types::{
        SuiTransactionBlockResponseOptions,
        SuiEvent,
        EventFilter,
        SuiExecutionStatus,
        SuiTransactionBlockEffects,
        SuiTransactionBlockEffectsAPI,
    },
    types::{
        base_types::{ObjectID, TransactionDigest},
        programmable_transaction_builder::ProgrammableTransactionBuilder,
        transaction::{Argument, CallArg, Command, ProgrammableMoveCall},
    },
};
use sui_types::{
    base_types::SuiAddress,
    transaction::{Transaction, TransactionData},
    crypto::{SuiSignature, Signature},
    message_envelope::Envelope,
    transaction::SenderSignedData,
    gas_coin::GasCoin,
};
use shared_crypto::intent::Intent;
use move_core_types::identifier::Identifier;
use sui_json_rpc_types::BcsEvent;

use crate::types::{SignedMessage, MessageStatus, CrossChainMessage};
use crate::chain_adapter::ChainAdapter;
use crate::config::ChainConfig;
use crate::Error as BridgeError;

pub struct SuiAdapter {
    client: SuiClient,
    config: ChainConfig,
}

impl SuiAdapter {
    pub async fn new(config: ChainConfig) -> Result<Self, BridgeError> {
        let client = SuiClientBuilder::default()
            .build(config.rpc_url.as_str())
            .await
            .map_err(|e| BridgeError::Chain(e.to_string()))?;
        
        Ok(Self { client, config })
    }

    pub async fn send_message(&self, message: &SignedMessage) -> Result<TransactionDigest, BridgeError> {
        let package = ObjectID::from_hex_literal(&self.config.bridge_address)
            .map_err(|e| BridgeError::Chain(e.to_string()))?;
        let sender = SuiAddress::from_str(&self.config.id)
            .map_err(|e| BridgeError::Chain(e.to_string()))?;
        let mut builder = ProgrammableTransactionBuilder::new();
        
        // 添加参数
        builder.input(CallArg::Pure(bcs::to_bytes(&message.message)
            .map_err(|e| BridgeError::Serialization(e.to_string()))?))
            .map_err(|e| BridgeError::Chain(e.to_string()))?;
        builder.input(CallArg::Pure(bcs::to_bytes(&message.signature)
            .map_err(|e| BridgeError::Serialization(e.to_string()))?))
            .map_err(|e| BridgeError::Chain(e.to_string()))?;

        // 添加 Move 调用
        builder.command(Command::MoveCall(Box::new(ProgrammableMoveCall {
            package,
            module: "bridge".to_string(),
            function: "process_message".to_string(),
            type_arguments: vec![],
            arguments: vec![Argument::Input(0), Argument::Input(1)],
        })));

        let pt = builder.finish();
        let tx_data = TransactionData::new_programmable(
            sender,
            vec![],
            pt,
            1000u64,
            1000u64,
        );
        
        let intent = Intent::sui_transaction();
        let signed_tx = Transaction::from_data(tx_data, vec![]);
        
        let response = self.client
            .quorum_driver_api()
            .execute_transaction_block(
                signed_tx,
                SuiTransactionBlockResponseOptions::new(),
                None,
            )
            .await
            .map_err(|e| BridgeError::Chain(e.to_string()))?;

        Ok(response.digest)
    }

    pub async fn get_message_status(&self, digest: &TransactionDigest) -> Result<MessageStatus, BridgeError> {
        let response = self.client
            .read_api()
            .get_transaction_with_options(
                *digest,
                SuiTransactionBlockResponseOptions::new().with_effects(),
            )
            .await
            .map_err(|e| BridgeError::Chain(e.to_string()))?;
        
        if let Some(effects) = response.effects {
            match effects.status() {
                SuiExecutionStatus::Success => Ok(MessageStatus::Processed),
                _ => Ok(MessageStatus::Failed),
            }
        } else {
            Ok(MessageStatus::Pending)
        }
    }

    async fn parse_event(&self, event: &SuiEvent) -> Result<Option<SignedMessage>, BridgeError> {
        let event_type = event.type_.to_string();
        if event_type.contains("::bridge::MessageEvent") {
            let bcs_data = event.bcs.bytes();
            let message: CrossChainMessage = bcs::from_bytes(bcs_data)
                .map_err(|e| BridgeError::Serialization(e.to_string()))?;
            let timestamp = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs();
            
            return Ok(Some(SignedMessage {
                message,
                signature: vec![], // 从事件中获取签名
                timestamp,
            }));
        }
        Ok(None)
    }
}

#[async_trait]
impl ChainAdapter for SuiAdapter {
    fn chain_type(&self) -> &str {
        "sui"
    }

    async fn listen_events(&self, config: &ChainConfig) -> Result<Vec<SignedMessage>, BridgeError> {
        let mut messages = Vec::new();
        let package = ObjectID::from_hex_literal(&config.bridge_address)
            .map_err(|e| BridgeError::Chain(e.to_string()))?;

        let module = Identifier::new("bridge").unwrap();
        let filter = EventFilter::MoveModule {
            package,
            module,
        };

        let events = self.client
            .event_api()
            .query_events(filter, None, None, false)
            .await
            .map_err(|e| BridgeError::Chain(e.to_string()))?;

        for event in events.data {
            if let Some(message) = self.parse_event(&event).await? {
                messages.push(message);
            }
        }

        Ok(messages)
    }

    async fn submit_message(&self, _config: &ChainConfig, message: SignedMessage) -> Result<(), BridgeError> {
        self.send_message(&message).await?;
        Ok(())
    }

    async fn verify_message(&self, _config: &ChainConfig, message: &SignedMessage) -> Result<MessageStatus, BridgeError> {
        // 使用消息的签名作为唯一标识来查询状态
        let digest = TransactionDigest::new(message.signature.as_slice().try_into().unwrap());
        self.get_message_status(&digest).await
    }
} 