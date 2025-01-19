use anyhow::Result;
use bridge_core::{Config, relayer::Relayer};
use clap::{Parser, Subcommand};
use std::path::PathBuf;
use tracing::{info, error};

#[derive(Parser)]
#[command(author, version, about, long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// 验证并解析配置文件
    ValidateConfig {
        /// 配置文件路径
        #[arg(short, long, value_name = "FILE")]
        config: PathBuf,
    },
    /// 启动中继器服务
    Start {
        /// 配置文件路径
        #[arg(short, long, value_name = "FILE")]
        config: PathBuf,
    },
}

#[tokio::main]
async fn main() -> Result<()> {
    // 初始化日志
    tracing_subscriber::fmt::init();

    let cli = Cli::parse();

    match cli.command {
        Commands::ValidateConfig { config } => {
            info!("正在验证配置文件: {:?}", config);
            let config = Config::load(config)?;
            println!("配置文件验证成功!");
            println!("配置内容概要:");
            println!("- 支持的链:");
            for chain in &config.chains {
                println!("  - {} ({}): {}", chain.name, chain.id, chain.adapter_type);
            }
            println!("- 支持的资产:");
            for asset in &config.assets {
                println!("  - {} (原生链: {})", asset.name, asset.native_chain);
                println!("    映射:");
                for (chain_id, mapping) in &asset.mappings {
                    println!("    - {}: {}", chain_id, mapping);
                }
            }
            println!("- 验证者数量: {}", config.validators.len());
            println!("- 中继器配置:");
            println!("  - 轮询间隔: {}秒", config.relayer.poll_interval);
            println!("  - 最大重试次数: {}", config.relayer.max_retries);
            println!("  - 重试延迟: {}秒", config.relayer.retry_delay);
            Ok(())
        }
        Commands::Start { config } => {
            info!("正在启动中继器服务");
            info!("使用配置文件: {:?}", config);
            
            // 加载配置
            let config = Config::load(config)?;
            
            // 创建并启动中继器
            let relayer = Relayer::new(config).await?;
            info!("中继器初始化成功，开始运行...");
            
            // 启动中继器服务
            if let Err(e) = relayer.start().await {
                error!("中继器服务异常退出: {}", e);
                return Err(e.into());
            }
            
            Ok(())
        }
    }
}
