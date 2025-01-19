/// 消息验证模块测试
/// 本测试模块验证跨链消息验证系统的核心功能，包括：
/// 1. 验证器对消息的签名验证
/// 2. 验证权限控制
/// 3. 验证记录的管理
#[test_only]
module bridge_validator::verify_tests {
    use sui::test_scenario::{Self, Scenario};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::object::{Self, ID};
    use sui::transfer;
    use bridge_validator::verify::{Self, MessageVerification};
    use bridge_validator::validator::{Self};
    use bridge_validator::stake::{Self};
    use bridge_validator::types::{Self, ValidatorSet, StakeManager};
    use sui::hash::blake2b256;
    use std::vector;

    // === 测试常量定义 ===
    /// 最小质押要求：1000 SUI
    const MIN_STAKE: u64 = 1000_000_000; // 1 SUI = 1_000_000_000 (9个0)
    /// 系统管理员地址
    const ADMIN: address = @0xAD;
    /// 测试验证器1地址
    const VALIDATOR1: address = @0x1;
    /// 测试验证器2地址
    const VALIDATOR2: address = @0x2;
    /// 测试验证器3地址（未授权的验证器）
    const VALIDATOR3: address = @0x3;
    /// 普通用户地址
    const USER: address = @0x4;

    // === 测试公钥数据 ===
    /// 验证器1的Ed25519公钥（32字节）
    const VALIDATOR1_PUBKEY: vector<u8> = vector[
        129, 195, 22, 255, 90, 236, 14, 202, 136, 174, 145, 28, 186, 228, 35, 214,
        50, 86, 208, 25, 84, 82, 58, 237, 117, 186, 103, 57, 149, 181, 255, 89
    ];
    /// 验证器2的Ed25519公钥（32字节）
    const VALIDATOR2_PUBKEY: vector<u8> = vector[
        20, 154, 147, 13, 4, 64, 166, 200, 159, 179, 194, 235, 205, 176, 117, 6,
        154, 152, 127, 161, 216, 8, 233, 60, 193, 12, 130, 131, 227, 60, 82, 35
    ];
    /// 验证器3的Ed25519公钥（32字节）
    const VALIDATOR3_PUBKEY: vector<u8> = vector[
        237, 70, 123, 179, 76, 65, 106, 77, 118, 197, 19, 209, 132, 43, 20, 146,
        24, 129, 18, 51, 132, 234, 150, 38, 47, 206, 121, 141, 49, 134, 145, 31
    ];

    // === Ed25519测试向量 ===
    /// 测试消息（"Test message"的字节表示）
    const TEST_MESSAGE: vector<u8> = vector[84, 101, 115, 116, 32, 109, 101, 115, 115, 97, 103, 101];
    /// 测试签名（64字节 Ed25519 签名）
    const TEST_SIGNATURE: vector<u8> = vector[
        38, 175, 96, 108, 93, 36, 218, 46, 63, 121, 37, 103, 134, 197, 139, 141,
        186, 69, 208, 145, 167, 125, 77, 50, 100, 83, 172, 237, 211, 177, 33, 201,
        66, 230, 235, 135, 180, 234, 109, 156, 153, 35, 252, 110, 15, 23, 124, 201,
        246, 112, 70, 195, 9, 74, 125, 107, 144, 55, 147, 127, 166, 71, 234, 12
    ];

    // === 测试辅助函数 ===
    /// 初始化测试环境
    /// 创建验证器集合和质押管理器
    /// 返回：初始化后的测试场景
    fun setup_test(): Scenario {
        let mut scenario = test_scenario::begin(ADMIN);
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            validator::init_for_test(test_scenario::ctx(&mut scenario));
            stake::init_for_test(test_scenario::ctx(&mut scenario));
        };
        scenario
    }

    /// 设置测试验证器
    /// * `scenario` - 测试场景
    /// 为测试准备两个验证器：
    /// 1. VALIDATOR1: 质押2000 SUI
    /// 2. VALIDATOR2: 质押1000 SUI
    fun setup_validators(scenario: &mut Scenario) {
        // 第一步：VALIDATOR1质押2000 SUI
        test_scenario::next_tx(scenario, VALIDATOR1);
        {
            let mut stake_manager = test_scenario::take_shared<StakeManager>(scenario);
            let stake_coin = coin::mint_for_testing<SUI>(MIN_STAKE * 2, test_scenario::ctx(scenario));
            stake::stake(&mut stake_manager, stake_coin, test_scenario::ctx(scenario));
            test_scenario::return_shared(stake_manager);
        };

        // 第二步：管理员将VALIDATOR1添加到验证器集合
        test_scenario::next_tx(scenario, ADMIN);
        {
            let mut validator_set = test_scenario::take_shared<ValidatorSet>(scenario);
            let stake_manager = test_scenario::take_shared<StakeManager>(scenario);
            
            validator::add_validator(
                &mut validator_set,
                &stake_manager,
                VALIDATOR1,
                VALIDATOR1_PUBKEY,
                test_scenario::ctx(scenario)
            );
            
            test_scenario::return_shared(validator_set);
            test_scenario::return_shared(stake_manager);
        };

        // 第三步：VALIDATOR2质押1000 SUI
        test_scenario::next_tx(scenario, VALIDATOR2);
        {
            let mut stake_manager = test_scenario::take_shared<StakeManager>(scenario);
            let stake_coin = coin::mint_for_testing<SUI>(MIN_STAKE, test_scenario::ctx(scenario));
            stake::stake(&mut stake_manager, stake_coin, test_scenario::ctx(scenario));
            test_scenario::return_shared(stake_manager);
        };

        // 第四步：管理员将VALIDATOR2添加到验证器集合
        test_scenario::next_tx(scenario, ADMIN);
        {
            let mut validator_set = test_scenario::take_shared<ValidatorSet>(scenario);
            let stake_manager = test_scenario::take_shared<StakeManager>(scenario);
            
            validator::add_validator(
                &mut validator_set,
                &stake_manager,
                VALIDATOR2,
                VALIDATOR2_PUBKEY,
                test_scenario::ctx(scenario)
            );
            
            test_scenario::return_shared(validator_set);
            test_scenario::return_shared(stake_manager);
        };
    }

    /// 测试消息验证流程
    /// 验证授权验证器能够正确验证消息并创建验证记录
    #[test]
    fun test_message_verification() {
        let mut scenario = setup_test();
        
        // 第一步：设置测试验证器
        setup_validators(&mut scenario);
        
        // 第二步：VALIDATOR1验证消息
        test_scenario::next_tx(&mut scenario, VALIDATOR1);
        {
            let validator_set = test_scenario::take_shared<ValidatorSet>(&scenario);
            
            verify::verify_message(
                &validator_set,
                TEST_MESSAGE, // 使用RFC 8032中的测试消息
                TEST_SIGNATURE, // 使用RFC 8032中的测试签名
                1, // 源链ID
                2, // 目标链ID
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(validator_set);
        };
        
        // 第三步：验证消息验证结果
        test_scenario::next_tx(&mut scenario, USER);
        {
            let verification = test_scenario::take_shared<MessageVerification>(&scenario);
            
            assert!(verify::is_message_verified(&verification), 0); // 验证消息已被验证
            assert!(verify::get_verification_count(&verification) == 1, 1); // 验证计数为1
            
            test_scenario::return_shared(verification);
        };
        
        test_scenario::end(scenario);
    }

    /// 测试未授权验证器的验证请求
    /// 验证系统正确拒绝未授权验证器的验证请求
    #[test]
    #[expected_failure(abort_code = verify::EINVALID_VALIDATOR)]
    fun test_unauthorized_verification() {
        let mut scenario = setup_test();
        setup_validators(&mut scenario);
        
        // 尝试使用未授权的验证器（VALIDATOR3）验证消息
        test_scenario::next_tx(&mut scenario, VALIDATOR3);
        {
            let validator_set = test_scenario::take_shared<ValidatorSet>(&scenario);
            
            let message = b"test message"; // 测试消息
            let signature = b"test signature"; // 无效签名
            
            verify::verify_message(
                &validator_set,
                message,
                signature,
                1, // 源链ID
                2, // 目标链ID
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(validator_set);
        };
        
        test_scenario::end(scenario);
    }
} 