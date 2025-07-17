// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { GovernanceToken } from "../src/GovernanceToken.sol";

/**
 * @title DeployGovernanceToken
 * @notice Simplified script to deploy only the updated GovernanceToken contract
 */
contract DeployGovernanceToken is Script {
    // Existing YieldVault address from your previous deployment
    address public constant YIELD_VAULT = 0xE63cE0E709eB6E7f345133C681Ba177df603e804;
    
    // Governance token configuration
    string public constant GOV_TOKEN_NAME = "YieldSync Governance";
    string public constant GOV_TOKEN_SYMBOL = "YSG";

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

        console.log("=== GovernanceToken Deployment ===");
        console.log("Deployer:", deployerAddress);
        console.log("Chain ID:", block.chainid);
        console.log("YieldVault address:", YIELD_VAULT);
        console.log("Balance:", deployerAddress.balance);

        // Check balance
        require(deployerAddress.balance > 0.01 ether, "Insufficient balance for deployment");

        // Deploy GovernanceToken
        console.log("\nDeploying GovernanceToken...");
        GovernanceToken governanceToken = new GovernanceToken(
            YIELD_VAULT,
            GOV_TOKEN_NAME,
            GOV_TOKEN_SYMBOL
        );
        
        console.log("[OK] GovernanceToken deployed at:", address(governanceToken));

        // Grant the YieldVault the YIELD_DISTRIBUTOR_ROLE
        console.log("\nConfiguring roles...");
        bytes32 yieldDistributorRole = governanceToken.YIELD_DISTRIBUTOR_ROLE();
        governanceToken.grantRole(yieldDistributorRole, YIELD_VAULT);
        console.log("[OK] Granted YIELD_DISTRIBUTOR_ROLE to YieldVault");

        if (deployerPrivateKey != 0) {
            vm.stopBroadcast();
        }

        // Generate summary
        console.log("\n=== DEPLOYMENT COMPLETE ===");
        console.log("New GovernanceToken address:", address(governanceToken));
        console.log("Token Name:", GOV_TOKEN_NAME);
        console.log("Token Symbol:", GOV_TOKEN_SYMBOL);
        console.log("Connected to YieldVault:", YIELD_VAULT);
        
        console.log("\n=== UPDATE FRONTEND CONFIG ===");
        console.log("Update this address in your frontend:");
        console.log("GOVERNANCE_TOKEN: '", address(governanceToken), "'");
        
        console.log("\n=== VERIFICATION COMMAND ===");
        console.log("forge verify-contract", address(governanceToken), "src/GovernanceToken.sol:GovernanceToken");
        console.log("--constructor-args YIELD_VAULT GOV_NAME GOV_SYMBOL");
        console.log("--rpc-url https://test-rpc.primordial.bdagscan.com");
        console.log("--chain-id 1043");
    }
}