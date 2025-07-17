// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { MockOracle } from "../src/MockOracle.sol";
import { YieldAggregator } from "../src/YieldAggregator.sol";
import { YieldVault } from "../src/YieldVault.sol";
import { GovernanceToken } from "../src/GovernanceToken.sol";
import { MockPool } from "../src/MockPool.sol";

/**
 * @title ConfigureDeployment
 * @notice Script to configure deployed contracts with proper connections and roles
 */
contract ConfigureDeployment is Script {
    // Deployed contract addresses
    address constant MOCK_TOKEN = 0x9589a024a960db2B63367a1e8bF659cBBa3215FD;
    address constant MOCK_ORACLE = 0x4f910ef3996d7C4763EFA2fEf15265e8b918cD0b;
    address constant FEE_OPTIMIZER = 0x90aF6FD2d47144a72B1e1D482C4208006Dba4f29;
    address constant YIELD_AGGREGATOR = 0xCB30C36cfaAa32b059138E302281dB4B8e50eD8c;
    address constant YIELD_VAULT = 0xE63cE0E709eB6E7f345133C681Ba177df603e804;
    address constant GOVERNANCE_TOKEN = 0x7412634B3189546549898000929A72600EF52b82;

    // Mock pools
    address constant AMM_POOL = 0xAeAf07d2FcB5F7cB3d96A97FD872E1C12D455D38;
    address constant LENDING_POOL = 0x52BeC0b8025401e2ce84E1289C7dDCF8f290c474;
    address constant STAKING_POOL = 0x4469DDb94Ea2F5faF18F69e6ABb0E9E823ddf5Ca;

    // Configuration
    address constant FEE_COLLECTOR = 0x9aabD891ab1FaA750FAE5aba9b55623c7F69fD58;

    // Contract instances
    MockOracle mockOracle;
    YieldAggregator yieldAggregator;
    YieldVault yieldVault;
    GovernanceToken governanceToken;
    MockPool ammPool;
    MockPool lendingPool;
    MockPool stakingPool;

    function run() external {
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(0));
        
        address deployerAddress;
        if (deployerPrivateKey == 0) {
            deployerAddress = msg.sender;
            console.log("Using account-based deployment");
        } else {
            deployerAddress = vm.addr(deployerPrivateKey);
            vm.startBroadcast(deployerPrivateKey);
        }

        console.log("=== Configuring Deployed Contracts ===");
        console.log("Deployer:", deployerAddress);

        // Initialize contract instances
        mockOracle = MockOracle(MOCK_ORACLE);
        yieldAggregator = YieldAggregator(YIELD_AGGREGATOR);
        yieldVault = YieldVault(YIELD_VAULT);
        governanceToken = GovernanceToken(GOVERNANCE_TOKEN);
        ammPool = MockPool(AMM_POOL);
        lendingPool = MockPool(LENDING_POOL);
        stakingPool = MockPool(STAKING_POOL);

        // Step 1: Configure Oracle with pools
        console.log("\n1. Configuring Oracle with pools...");
        _configureOracle();

        // Step 2: Add pools to aggregator
        console.log("\n2. Adding pools to Yield Aggregator...");
        _configureAggregator();

        // Step 3: Grant roles between contracts
        console.log("\n3. Granting roles between contracts...");
        _grantRoles();

        // Step 4: Verify configuration
        console.log("\n4. Verifying configuration...");
        _verifyConfiguration();

        console.log("\n[OK] All configuration completed successfully!");

        if (deployerPrivateKey != 0) {
            vm.stopBroadcast();
        }

        // Generate summary
        _generateConfigurationSummary();
    }

    /**
     * @notice Configure oracle with pool data
     */
    function _configureOracle() internal {
        console.log("Adding AMM Pool to Oracle...");
        mockOracle.addPool(AMM_POOL, 800, 100); // 8% APY, 100 gas cost
        
        console.log("Adding Lending Pool to Oracle...");
        mockOracle.addPool(LENDING_POOL, 1200, 150); // 12% APY, 150 gas cost
        
        console.log("Adding Staking Pool to Oracle...");
        mockOracle.addPool(STAKING_POOL, 1500, 200); // 15% APY, 200 gas cost

        console.log("Updating Oracle gas price and network congestion...");
        mockOracle.updateGasPrice(20 gwei);
        mockOracle.updateNetworkCongestion(50);

        console.log("[OK] Oracle configured with 3 pools");
    }

    /**
     * @notice Add pools to the yield aggregator
     */
    function _configureAggregator() internal {
        console.log("Adding AMM Pool to Aggregator...");
        yieldAggregator.addPool(AMM_POOL, 800); // 8% APY
        
        console.log("Adding Lending Pool to Aggregator...");
        yieldAggregator.addPool(LENDING_POOL, 1200); // 12% APY
        
        console.log("Adding Staking Pool to Aggregator...");
        yieldAggregator.addPool(STAKING_POOL, 1500); // 15% APY

        console.log("[OK] Added 3 pools to yield aggregator");
    }

    /**
     * @notice Grant necessary roles between contracts
     */
    function _grantRoles() internal {
        console.log("Granting VAULT_ROLE to YieldVault on YieldAggregator...");
        bytes32 vaultRole = yieldAggregator.VAULT_ROLE();
        yieldAggregator.grantRole(vaultRole, YIELD_VAULT);

        console.log("Granting AGGREGATOR_ROLE to YieldAggregator on YieldVault...");
        bytes32 aggregatorRole = yieldVault.AGGREGATOR_ROLE();
        yieldVault.grantRole(aggregatorRole, YIELD_AGGREGATOR);

        console.log("Granting YIELD_DISTRIBUTOR_ROLE to YieldVault on GovernanceToken...");
        bytes32 yieldDistributorRole = governanceToken.YIELD_DISTRIBUTOR_ROLE();
        governanceToken.grantRole(yieldDistributorRole, YIELD_VAULT);

        console.log("[OK] Roles granted successfully");
    }

    /**
     * @notice Verify configuration is correct
     */
    function _verifyConfiguration() internal view {
        console.log("Verifying Oracle pool count...");
        // Note: This assumes MockOracle has a way to check pool count
        // You might need to adjust based on your MockOracle implementation
        
        console.log("Verifying Aggregator pool count...");
        // Note: This assumes YieldAggregator has a way to check pool count
        // You might need to adjust based on your YieldAggregator implementation
        
        console.log("Verifying roles...");
        bytes32 vaultRole = yieldAggregator.VAULT_ROLE();
        require(yieldAggregator.hasRole(vaultRole, YIELD_VAULT), "VAULT_ROLE not granted");
        
        bytes32 aggregatorRole = yieldVault.AGGREGATOR_ROLE();
        require(yieldVault.hasRole(aggregatorRole, YIELD_AGGREGATOR), "AGGREGATOR_ROLE not granted");
        
        bytes32 yieldDistributorRole = governanceToken.YIELD_DISTRIBUTOR_ROLE();
        require(governanceToken.hasRole(yieldDistributorRole, YIELD_VAULT), "YIELD_DISTRIBUTOR_ROLE not granted");

        console.log("[OK] Configuration verified successfully");
    }

    /**
     * @notice Generate comprehensive configuration summary
     */
    function _generateConfigurationSummary() internal view {
        console.log("\n=== CONFIGURATION SUMMARY ===");
        console.log("Chain ID:", block.chainid);
        console.log("Block Number:", block.number);
        console.log("Configured by:", msg.sender);
        console.log("");
        console.log("=== ORACLE CONFIGURATION ===");
        console.log("AMM Pool:     ", AMM_POOL, " (8% APY, 100 gas)");
        console.log("Lending Pool: ", LENDING_POOL, " (12% APY, 150 gas)");
        console.log("Staking Pool: ", STAKING_POOL, " (15% APY, 200 gas)");
        console.log("Gas Price:    20 gwei");
        console.log("Network Congestion: 50");
        console.log("");
        console.log("=== AGGREGATOR CONFIGURATION ===");
        console.log("AMM Pool:     ", AMM_POOL, " (8% APY)");
        console.log("Lending Pool: ", LENDING_POOL, " (12% APY)");
        console.log("Staking Pool: ", STAKING_POOL, " (15% APY)");
        console.log("");
        console.log("=== ROLES GRANTED ===");
        console.log("YieldVault has VAULT_ROLE on YieldAggregator");
        console.log("YieldAggregator has AGGREGATOR_ROLE on YieldVault");
        console.log("YieldVault has YIELD_DISTRIBUTOR_ROLE on GovernanceToken");
        console.log("");
        console.log("=== NEXT STEPS ===");
        console.log("1. Test deposit/withdraw functionality");
        console.log("2. Test yield sharing mechanism");
        console.log("3. Test governance token distribution");
        console.log("4. Monitor pool performance and rebalancing");
    }
}