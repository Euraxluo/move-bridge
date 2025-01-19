/// 治理模块测试
/// 本测试模块验证治理系统的核心功能，包括：
/// 1. 提案的创建、投票和执行流程
/// 2. 无效提案的处理
/// 3. 验证器权限控制
#[test_only]
module bridge_validator::governance_tests {
    use sui::test_scenario::{Self, Scenario};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use bridge_validator::governance;
    use bridge_validator::validator;
    use bridge_validator::stake;
    use bridge_validator::types::{Self, ValidatorSet, StakeManager, Proposal};

    // === 测试常量定义 ===
    /// 最小质押要求：1000 SUI
    const MIN_STAKE: u64 = 1000_000_000; // 1 SUI = 1_000_000_000 (9个0)
    /// 系统管理员地址
    const ADMIN: address = @0xAD;
    /// 测试验证器1地址
    const VALIDATOR1: address = @0x1;
    /// 测试验证器2地址
    const VALIDATOR2: address = @0x2;
    /// 测试验证器3地址
    const VALIDATOR3: address = @0x3;

    // === 测试公钥数据 ===
    /// 验证器1的Ed25519公钥（32字节）
    const VALIDATOR1_PUBKEY: vector<u8> = vector[
        182, 47, 109, 177, 21, 56, 131, 42, 202, 138, 249, 242, 16, 3, 5, 205,
        244, 227, 116, 217, 98, 53, 120, 118, 24, 119, 37, 98, 158, 119, 33, 162
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

    // === 测试辅助函数 ===
    /// 初始化测试环境
    /// 创建验证器集合和质押管理器
    /// 返回：初始化后的测试场景
    fun setup_test(): Scenario {
        let mut scenario = test_scenario::begin(ADMIN);
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

    /// 测试提案的完整生命周期
    /// 验证提案的创建、投票和执行流程
    #[test]
    fun test_proposal_lifecycle() {
        let mut scenario = setup_test();
        setup_validators(&mut scenario);
        
        // 第一步：VALIDATOR1创建系统参数更新提案
        test_scenario::next_tx(&mut scenario, VALIDATOR1);
        {
            let validator_set = test_scenario::take_shared<ValidatorSet>(&mut scenario);
            
            governance::create_proposal(
                &validator_set,
                1, // PROPOSAL_TYPE_PARAMETER：系统参数更新提案
                // 参数格式：[参数类型(1字节), 参数值(8字节)]
                // 这里设置最小质押量为2000 SUI
                vector[
                    1, // 参数类型：1 = 最小质押量
                    208, 167, 30, 0, 0, 0, 0, 0, // 2000_000_000_000 (2000 SUI) in little-endian
                ],
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(validator_set);
        };
        
        // 第二步：VALIDATOR1投票赞成
        test_scenario::next_tx(&mut scenario, VALIDATOR1);
        {
            let validator_set = test_scenario::take_shared<ValidatorSet>(&mut scenario);
            let mut proposal = test_scenario::take_from_sender<Proposal>(&mut scenario);
            
            governance::vote_on_proposal(
                &validator_set,
                &mut proposal,
                true, // 赞成票
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_to_sender(&mut scenario, proposal);
            test_scenario::return_shared(validator_set);
        };
        
        // 第三步：VALIDATOR2投票赞成
        test_scenario::next_tx(&mut scenario, VALIDATOR2);
        {
            let validator_set = test_scenario::take_shared<ValidatorSet>(&mut scenario);
            let mut proposal = test_scenario::take_from_address<Proposal>(&mut scenario, VALIDATOR1);
            
            governance::vote_on_proposal(
                &validator_set,
                &mut proposal,
                true, // 赞成票
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_to_address(VALIDATOR1, proposal);
            test_scenario::return_shared(validator_set);
        };
        
        // 第四步：VALIDATOR1执行已通过的提案
        test_scenario::next_tx(&mut scenario, VALIDATOR1);
        {
            let mut validator_set = test_scenario::take_shared<ValidatorSet>(&mut scenario);
            let mut proposal = test_scenario::take_from_sender<Proposal>(&mut scenario);
            
            governance::execute_proposal(
                &mut validator_set,
                &mut proposal,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_to_sender(&mut scenario, proposal);
            test_scenario::return_shared(validator_set);
        };
        
        test_scenario::end(scenario);
    }

    /// 测试无效提案的处理
    /// 验证系统正确拒绝无效的提案类型
    #[test]
    #[expected_failure(abort_code = governance::EINVALID_PROPOSAL)]
    fun test_invalid_proposal_execution() {
        let mut scenario = setup_test();
        setup_validators(&mut scenario);
        
        // 尝试创建一个无效类型的提案（应该失败）
        test_scenario::next_tx(&mut scenario, VALIDATOR1);
        {
            let validator_set = test_scenario::take_shared<ValidatorSet>(&mut scenario);
            
            governance::create_proposal(
                &validator_set,
                99, // 使用一个无效的提案类型（有效类型为1,2,3）
                VALIDATOR1_PUBKEY, // 测试参数数据
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(validator_set);
        };
        
        test_scenario::end(scenario);
    }
} 