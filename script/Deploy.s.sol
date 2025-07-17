// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { YieldVault } from "../src/YieldVault.sol";
import { YieldAggregator } from "../src/YieldAggregator.sol";
import { FeeOptimizer } from "../src/FeeOptimizer.sol";
import { MockOracle } from "../src/MockOracle.sol";
import { GovernanceToken } from "../src/GovernanceToken.sol";
import { MockPool } from "../src/MockPool.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockBDAG
 * @notice Mock BDAG token for testing
 */
contract MockBDAG is ERC20 {
    constructor() ERC20("Mock BDAG", "mBDAG") {
        _mint(msg.sender, 1_000_000_000 * 10 ** decimals()); // 1 billion tokens
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title Deploy
 * @author YieldSync Team
 * @notice Enhanced deployment script with better error handling and verification
 */
contract Deploy is Script {
    // Contract instances
    MockBDAG public mockBDAG;
    MockOracle public mockOracle;
    FeeOptimizer public feeOptimizer;
    YieldAggregator public yieldAggregator;
    YieldVault public yieldVault;
    GovernanceToken public governanceToken;

    // Mock pools for testing
    MockPool public ammPool;
    MockPool public lendingPool;
    MockPool public stakingPool;

    // Configuration
    address public constant FEE_COLLECTOR = 0x742d35cc6634C0532925A3B8D956C1bfA6666E2A;
    string public constant VAULT_NAME = "YieldSync Vault Shares";
    string public constant VAULT_SYMBOL = "YSV";
    string public constant GOV_TOKEN_NAME = "YieldSync Governance";
    string public constant GOV_TOKEN_SYMBOL = "YSG";

    // Deployment tracking
    struct DeploymentData {
        address mockBDAG;
        address mockOracle;
        address feeOptimizer;
        address yieldAggregator;
        address yieldVault;
        address governanceToken;
        address ammPool;
        address lendingPool;
        address stakingPool;
        address deployer;
        uint256 chainId;
        uint256 blockNumber;
    }

    /**
     * @notice Main deployment function with enhanced error handling
     */
    function run() external {
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(0));

        // If no private key in env, try to use the account (arbWallet)
        address deployerAddress;
        if (deployerPrivateKey == 0) {
            // Using account-based deployment
            deployerAddress = msg.sender;
            console.log("Using account-based deployment");
        } else {
            deployerAddress = vm.addr(deployerPrivateKey);
            vm.startBroadcast(deployerPrivateKey);
        }

        console.log("=== Enhanced YieldSync Deployment ===");
        console.log("Deployer:", deployerAddress);
        console.log("Chain ID:", block.chainid);
        console.log("Block Number:", block.number);
        console.log("Balance:", deployerAddress.balance);

        // Check if we have enough balance
        require(deployerAddress.balance > 0.1 ether, "Insufficient balance for deployment");

        // Step 1: Deploy Mock BDAG token
        console.log("\n1. Deploying Mock BDAG token...");
        mockBDAG = new MockBDAG();
        console.log("[OK] Mock BDAG deployed at:", address(mockBDAG));

        // Step 2: Deploy Mock Oracle
        console.log("\n2. Deploying Mock Oracle...");
        mockOracle = new MockOracle();
        console.log("[OK] Mock Oracle deployed at:", address(mockOracle));

        // Step 3: Deploy Mock Pools
        console.log("\n3. Deploying Mock Pools...");
        _deployMockPools();

        // Step 4: Configure Oracle with pools
        console.log("\n4. Configuring Oracle with pools...");
        _configureOracle();

        // Step 5: Deploy Fee Optimizer
        console.log("\n5. Deploying Fee Optimizer...");
        feeOptimizer = new FeeOptimizer(address(mockOracle));
        console.log("[OK] Fee Optimizer deployed at:", address(feeOptimizer));

        // Step 6: Deploy Yield Aggregator
        console.log("\n6. Deploying Yield Aggregator...");
        yieldAggregator = new YieldAggregator(
            address(mockBDAG),
            address(mockOracle),
            address(0) // Vault address will be set later
        );
        console.log("[OK] Yield Aggregator deployed at:", address(yieldAggregator));

        // Step 7: Deploy Yield Vault
        console.log("\n7. Deploying Yield Vault...");
        yieldVault = new YieldVault(
            address(mockBDAG),
            address(yieldAggregator),
            address(feeOptimizer),
            FEE_COLLECTOR,
            VAULT_NAME,
            VAULT_SYMBOL
        );
        console.log("[OK] Yield Vault deployed at:", address(yieldVault));

        // Step 8: Deploy Governance Token
        console.log("\n8. Deploying Governance Token...");
        governanceToken = new GovernanceToken(address(yieldVault), GOV_TOKEN_NAME, GOV_TOKEN_SYMBOL);
        console.log("[OK] Governance Token deployed at:", address(governanceToken));

        // Step 9: Update aggregator vault address
        console.log("\n9. Updating aggregator vault address...");
        yieldAggregator.setVault(address(yieldVault));
        console.log("[OK] Aggregator vault address updated");

        // Step 10: Configure contracts
        console.log("\n10. Configuring contracts...");
        _configureContracts();

        // Step 11: Add pools to aggregator
        console.log("\n11. Adding pools to aggregator...");
        _addPoolsToAggregator();

        // Step 12: Setup initial liquidity and test scenarios
        console.log("\n12. Setting up test scenarios...");
        _setupTestScenarios();

        console.log("\n[OK] All deployments completed successfully!");

        if (deployerPrivateKey != 0) {
            vm.stopBroadcast();
        }

        // Step 13: Generate deployment summary
        _generateDeploymentSummary();

        // Step 14: Generate verification commands
        _generateVerificationCommands();
    }

    /**
     * @notice Deploy mock pools for testing different yield strategies
     */
    function _deployMockPools() internal {
        ammPool = new MockPool(
            address(mockBDAG),
            800, // 8% APY
            "Mock AMM Pool",
            "AMM"
        );
        console.log("[OK] AMM Pool deployed at:", address(ammPool));

        lendingPool = new MockPool(
            address(mockBDAG),
            1200, // 12% APY
            "Mock Lending Pool",
            "Lending"
        );
        console.log("[OK] Lending Pool deployed at:", address(lendingPool));

        stakingPool = new MockPool(
            address(mockBDAG),
            1500, // 15% APY
            "Mock Staking Pool",
            "Staking"
        );
        console.log("[OK] Staking Pool deployed at:", address(stakingPool));
    }

    /**
     * @notice Configure oracle with pool data
     */
    function _configureOracle() internal {
        mockOracle.addPool(address(ammPool), 800, 100);
        mockOracle.addPool(address(lendingPool), 1200, 150);
        mockOracle.addPool(address(stakingPool), 1500, 200);

        mockOracle.updateGasPrice(20 gwei);
        mockOracle.updateNetworkCongestion(50);

        console.log("[OK] Oracle configured with 3 pools");
    }

    /**
     * @notice Configure contracts with proper permissions and settings
     */
    function _configureContracts() internal {
        bytes32 vaultRole = yieldAggregator.VAULT_ROLE();
        yieldAggregator.grantRole(vaultRole, address(yieldVault));

        bytes32 aggregatorRole = yieldVault.AGGREGATOR_ROLE();
        yieldVault.grantRole(aggregatorRole, address(yieldAggregator));

        bytes32 yieldDistributorRole = governanceToken.YIELD_DISTRIBUTOR_ROLE();
        governanceToken.grantRole(yieldDistributorRole, address(yieldVault));

        console.log("[OK] Contracts configured with proper roles");
    }

    /**
     * @notice Add pools to the yield aggregator
     */
    function _addPoolsToAggregator() internal {
        yieldAggregator.addPool(address(ammPool), 800);
        yieldAggregator.addPool(address(lendingPool), 1200);
        yieldAggregator.addPool(address(stakingPool), 1500);

        console.log("[OK] Added 3 pools to yield aggregator");
    }

    /**
     * @notice Setup test scenarios with initial liquidity
     */
    function _setupTestScenarios() internal {
        uint256 testAmount = 10_000 * 10 ** mockBDAG.decimals();

        // Add liquidity to pools
        mockBDAG.approve(address(ammPool), testAmount);
        ammPool.deposit(testAmount / 3);

        mockBDAG.approve(address(lendingPool), testAmount);
        lendingPool.deposit(testAmount / 3);

        mockBDAG.approve(address(stakingPool), testAmount);
        stakingPool.deposit(testAmount / 3);

        // Test vault deposit
        uint256 vaultTestAmount = 5000 * 10 ** mockBDAG.decimals();
        mockBDAG.approve(address(yieldVault), vaultTestAmount);
        yieldVault.deposit(vaultTestAmount);

        console.log("[OK] Test scenarios setup completed");
    }

    /**
     * @notice Generate comprehensive deployment summary
     */
    function _generateDeploymentSummary() internal view {
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("Chain ID:", block.chainid);
        console.log("Block Number:", block.number);
        console.log("Deployer:", msg.sender);
        console.log("");
        console.log("=== CONTRACT ADDRESSES ===");
        console.log("Mock BDAG Token:     ", address(mockBDAG));
        console.log("Mock Oracle:        ", address(mockOracle));
        console.log("Fee Optimizer:      ", address(feeOptimizer));
        console.log("Yield Aggregator:   ", address(yieldAggregator));
        console.log("Yield Vault:        ", address(yieldVault));
        console.log("Governance Token:   ", address(governanceToken));
        console.log("");
        console.log("=== MOCK POOLS ===");
        console.log("AMM Pool:           ", address(ammPool));
        console.log("Lending Pool:       ", address(lendingPool));
        console.log("Staking Pool:       ", address(stakingPool));
        console.log("");
        console.log("=== CONFIGURATION ===");
        console.log("Fee Collector:      ", FEE_COLLECTOR);
        console.log("Vault Name:         ", VAULT_NAME);
        console.log("Vault Symbol:       ", VAULT_SYMBOL);
        console.log("Gov Token Name:     ", GOV_TOKEN_NAME);
        console.log("Gov Token Symbol:   ", GOV_TOKEN_SYMBOL);
    }

    /**
     * @notice Generate verification commands for manual verification
     */
    function _generateVerificationCommands() internal view {
        console.log("\n=== VERIFICATION COMMANDS ===");
        console.log("Copy and run these commands to verify contracts:");
        console.log("");

        console.log("# Verify Mock BDAG Token");
        console.log("forge verify-contract", address(mockBDAG), "MockBDAG --chain 1043");
        console.log("");

        console.log("# Verify Mock Oracle");
        console.log("forge verify-contract", address(mockOracle), "MockOracle --chain 1043");
        console.log("");

        console.log("# Verify Fee Optimizer");
        console.log("forge verify-contract", address(feeOptimizer), "FeeOptimizer --chain 1043");
        console.log("");

        console.log("# Verify Yield Aggregator");
        console.log(
            "forge verify-contract", address(yieldAggregator), "YieldAggregator --chain 1043"
        );
        console.log("");

        console.log("# Verify Yield Vault");
        console.log("forge verify-contract", address(yieldVault), "YieldVault --chain 1043");
        console.log("");

        console.log("# Verify Governance Token");
        console.log(
            "forge verify-contract", address(governanceToken), "GovernanceToken --chain 1043"
        );
        console.log("");

        console.log("=== FRONTEND CONFIGURATION ===");
        console.log("Update your frontend config with these addresses:");
        console.log("const CONTRACTS = {");
        console.log("  MOCK_BDAG: '", address(mockBDAG), "',");
        console.log("  MOCK_ORACLE: '", address(mockOracle), "',");
        console.log("  FEE_OPTIMIZER: '", address(feeOptimizer), "',");
        console.log("  YIELD_AGGREGATOR: '", address(yieldAggregator), "',");
        console.log("  YIELD_VAULT: '", address(yieldVault), "',");
        console.log("  GOVERNANCE_TOKEN: '", address(governanceToken), "'");
        console.log("};");
    }
}
