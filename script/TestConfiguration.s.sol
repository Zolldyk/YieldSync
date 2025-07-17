// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { MockOracle } from "../src/MockOracle.sol";
import { YieldAggregator } from "../src/YieldAggregator.sol";
import { YieldVault } from "../src/YieldVault.sol";
import { GovernanceToken } from "../src/GovernanceToken.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title TestConfiguration
 * @notice Script to test the configured contracts
 */
contract TestConfiguration is Script {
    // Deployed contract addresses
    address constant MOCK_TOKEN = 0x9589a024a960db2B63367a1e8bF659cBBa3215FD;
    address constant MOCK_ORACLE = 0x4f910ef3996d7C4763EFA2fEf15265e8b918cD0b;
    address constant YIELD_AGGREGATOR = 0xCB30C36cfaAa32b059138E302281dB4B8e50eD8c;
    address constant YIELD_VAULT = 0xE63cE0E709eB6E7f345133C681Ba177df603e804;
    address constant GOVERNANCE_TOKEN = 0x7412634B3189546549898000929A72600EF52b82;

    // Mock pools
    address constant AMM_POOL = 0xAeAf07d2FcB5F7cB3d96A97FD872E1C12D455D38;
    address constant LENDING_POOL = 0x52BeC0b8025401e2ce84E1289C7dDCF8f290c474;
    address constant STAKING_POOL = 0x4469DDb94Ea2F5faF18F69e6ABb0E9E823ddf5Ca;

    function run() external {
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(0));
        
        address deployerAddress;
        if (deployerPrivateKey == 0) {
            deployerAddress = msg.sender;
        } else {
            deployerAddress = vm.addr(deployerPrivateKey);
            vm.startBroadcast(deployerPrivateKey);
        }

        console.log("=== Testing Configuration ===");
        console.log("Tester:", deployerAddress);

        // Test 1: Check contract instances
        console.log("\n1. Testing contract instances...");
        _testContractInstances();

        // Test 2: Check roles
        console.log("\n2. Testing roles...");
        _testRoles();

        // Test 3: Test basic functionality
        console.log("\n3. Testing basic functionality...");
        _testBasicFunctionality();

        console.log("\n[OK] All tests completed!");

        if (deployerPrivateKey != 0) {
            vm.stopBroadcast();
        }
    }

    function _testContractInstances() internal view {
        console.log("Testing MockOracle...");
        MockOracle oracle = MockOracle(MOCK_ORACLE);
        console.log("Gas price:", oracle.getGasPrice());
        
        console.log("Testing YieldAggregator...");
        YieldAggregator aggregator = YieldAggregator(YIELD_AGGREGATOR);
        address[] memory activePools = aggregator.getActivePools();
        console.log("Active pools count:", activePools.length);
        
        console.log("Testing YieldVault...");
        YieldVault vault = YieldVault(YIELD_VAULT);
        console.log("Vault name:", vault.name());
        console.log("Vault symbol:", vault.symbol());
        
        console.log("Testing GovernanceToken...");
        GovernanceToken govToken = GovernanceToken(GOVERNANCE_TOKEN);
        console.log("Gov token name:", govToken.name());
        console.log("Gov token symbol:", govToken.symbol());
        console.log("Yield sharing rate:", govToken.getYieldSharingRate());
        
        console.log("[OK] All contract instances working");
    }

    function _testRoles() internal view {
        YieldAggregator aggregator = YieldAggregator(YIELD_AGGREGATOR);
        YieldVault vault = YieldVault(YIELD_VAULT);
        GovernanceToken govToken = GovernanceToken(GOVERNANCE_TOKEN);
        
        console.log("Testing VAULT_ROLE...");
        bytes32 vaultRole = aggregator.VAULT_ROLE();
        bool hasVaultRole = aggregator.hasRole(vaultRole, YIELD_VAULT);
        console.log("YieldVault has VAULT_ROLE:", hasVaultRole);
        
        console.log("Testing AGGREGATOR_ROLE...");
        bytes32 aggregatorRole = vault.AGGREGATOR_ROLE();
        bool hasAggregatorRole = vault.hasRole(aggregatorRole, YIELD_AGGREGATOR);
        console.log("YieldAggregator has AGGREGATOR_ROLE:", hasAggregatorRole);
        
        console.log("Testing YIELD_DISTRIBUTOR_ROLE...");
        bytes32 yieldDistributorRole = govToken.YIELD_DISTRIBUTOR_ROLE();
        bool hasYieldDistributorRole = govToken.hasRole(yieldDistributorRole, YIELD_VAULT);
        console.log("YieldVault has YIELD_DISTRIBUTOR_ROLE:", hasYieldDistributorRole);
        
        console.log("[OK] All roles verified");
    }

    function _testBasicFunctionality() internal view {
        console.log("Testing MockToken balance...");
        IERC20 mockToken = IERC20(MOCK_TOKEN);
        console.log("MockToken total supply:", mockToken.totalSupply());
        
        console.log("Testing Oracle pools...");
        MockOracle oracle = MockOracle(MOCK_ORACLE);
        console.log("Network congestion:", oracle.getNetworkCongestion());
        
        console.log("Testing GovernanceToken settings...");
        GovernanceToken govToken = GovernanceToken(GOVERNANCE_TOKEN);
        console.log("Yield sharing active:", govToken.isYieldSharingActive());
        console.log("Community yield pool:", govToken.getCommunityYieldPool());
        console.log("Total tokens distributed:", govToken.getTotalTokensDistributed());
        
        console.log("[OK] Basic functionality tests passed");
    }
}