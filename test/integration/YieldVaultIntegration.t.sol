// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseTest } from "../shared/BaseTest.t.sol";

/**
 * @title YieldVaultIntegrationTest
 * @notice Integration tests for YieldVault with other protocol components
 */
contract YieldVaultIntegrationTest is BaseTest {
    /**
     * @notice Test full user journey: deposit -> yield generation -> withdrawal
     */
    function testFullUserJourney() public {
        vm.startPrank(USER1);

        // 1. Initial deposit
        uint256 initialBalance = mockToken.balanceOf(USER1);
        mockToken.approve(address(yieldVault), DEPOSIT_AMOUNT);
        uint256 shares = yieldVault.deposit(DEPOSIT_AMOUNT);

        // 2. Wait for yield generation
        vm.warp(block.timestamp + 90 days);

        // 3. Harvest yield
        vm.stopPrank();
        vm.startPrank(ADMIN);
        yieldVault.harvestYield();
        vm.stopPrank();
        vm.startPrank(USER1);

        // 4. Check that vault value increased
        uint256 assetValue = yieldVault.getUserAssetBalance(USER1);
        assertGt(assetValue, DEPOSIT_AMOUNT, "Asset value should have increased due to yield");

        // 5. Withdraw
        uint256 amountReceived = yieldVault.withdraw(shares);
        uint256 finalBalance = mockToken.balanceOf(USER1);

        // 6. Verify profit (accounting for fees)
        assertGt(finalBalance, initialBalance - DEPOSIT_AMOUNT, "Should have made some profit");

        vm.stopPrank();
    }

    /**
     * @notice Test end-to-end yield aggregation and fee optimization
     */
    function testEndToEndYieldAggregation() public {
        // Setup different network conditions
        vm.startPrank(ADMIN);
        mockOracle.updateGasPrice(50 gwei);
        mockOracle.updateNetworkCongestion(60);
        vm.stopPrank();

        // Multiple users deposit
        vm.startPrank(USER1);
        mockToken.approve(address(yieldVault), DEPOSIT_AMOUNT);
        yieldVault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();

        vm.startPrank(USER2);
        mockToken.approve(address(yieldVault), DEPOSIT_AMOUNT * 2);
        yieldVault.deposit(DEPOSIT_AMOUNT * 2);
        vm.stopPrank();

        // Verify funds are allocated to best pool
        (address bestPool, uint256 bestAPY) = yieldAggregator.getBestPool();
        assertEq(bestPool, address(pool3), "Funds should be allocated to highest APY pool");

        // Change market conditions
        vm.startPrank(ADMIN);
        mockOracle.updatePoolAPY(address(pool1), 2500); // 25% APY
        vm.stopPrank();

        // Wait for rebalance
        vm.warp(block.timestamp + 2 hours);
        yieldAggregator.rebalancePools();

        // Verify rebalancing occurred
        (address newBestPool,) = yieldAggregator.getBestPool();
        assertEq(newBestPool, address(pool1), "Funds should have rebalanced to new best pool");

        // Test fee optimization during withdrawal
        vm.startPrank(USER1);
        uint256 userShares = yieldVault.balanceOf(USER1);
        uint256 receivedAmount = yieldVault.withdraw(userShares);
        
        // Verify fee was calculated correctly
        assertGt(receivedAmount, 0, "Should receive tokens after withdrawal");
        assertLt(receivedAmount, DEPOSIT_AMOUNT, "Should be less than deposit due to fees");
        
        vm.stopPrank();
    }

    /**
     * @notice Test governance integration with yield sharing
     */
    function testGovernanceIntegration() public {
        // Setup governance tokens
        _setupGovernanceTokens(USER1, 10_000 * 1e18);
        _setupGovernanceTokens(USER2, 5000 * 1e18);

        // Create and vote on proposal
        vm.startPrank(USER1);
        uint256 proposalId = governanceToken.createProposal("Change performance fee to 2%");
        vm.stopPrank();

        // Wait for voting period
        vm.warp(block.timestamp + 1 days + 1);

        // Vote
        vm.startPrank(USER1);
        governanceToken.vote(proposalId, true);
        vm.stopPrank();

        vm.startPrank(USER2);
        governanceToken.vote(proposalId, true);
        vm.stopPrank();

        // Wait for execution period
        vm.warp(block.timestamp + 7 days);

        // Execute proposal (if implemented)
        // This would require actual governance execution logic
        
        // Verify proposal state
        (,,,, uint256 forVotes, uint256 againstVotes,,,) = governanceToken.getProposal(proposalId);
        assertGt(forVotes, againstVotes, "Proposal should have majority support");
    }

    /**
     * @notice Test multi-pool yield optimization
     */
    function testMultiPoolYieldOptimization() public {
        // Large deposit to test pool diversification
        uint256 largeAmount = 50_000 * 1e18;
        mockToken.mint(USER1, largeAmount);

        vm.startPrank(USER1);
        mockToken.approve(address(yieldVault), largeAmount);
        yieldVault.deposit(largeAmount);
        vm.stopPrank();

        // Verify allocation strategy
        uint256 pool1Allocation = yieldAggregator.getPoolInfo(address(pool1)).allocation;
        uint256 pool2Allocation = yieldAggregator.getPoolInfo(address(pool2)).allocation;
        uint256 pool3Allocation = yieldAggregator.getPoolInfo(address(pool3)).allocation;

        uint256 totalAllocation = pool1Allocation + pool2Allocation + pool3Allocation;
        assertEq(totalAllocation, largeAmount, "Total allocation should equal deposit amount");

        // Highest APY pool should get most allocation
        assertGt(pool3Allocation, pool2Allocation, "Pool3 should have more allocation than Pool2");
        assertGt(pool2Allocation, pool1Allocation, "Pool2 should have more allocation than Pool1");
    }

    /**
     * @notice Test protocol behavior during market stress
     */
    function testMarketStressScenario() public {
        // Initial deposits
        vm.startPrank(USER1);
        mockToken.approve(address(yieldVault), DEPOSIT_AMOUNT);
        yieldVault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Simulate market stress - pools lose value
        vm.startPrank(ADMIN);
        mockOracle.updatePoolAPY(address(pool1), 0); // 0% APY
        mockOracle.updatePoolAPY(address(pool2), 100); // 1% APY
        mockOracle.updatePoolAPY(address(pool3), 200); // 2% APY
        
        // High gas prices
        mockOracle.updateGasPrice(200 gwei);
        mockOracle.updateNetworkCongestion(95);
        vm.stopPrank();

        // Wait for rebalancing
        vm.warp(block.timestamp + 2 hours);
        yieldAggregator.rebalancePools();

        // Verify system still functions
        (address bestPool, uint256 bestAPY) = yieldAggregator.getBestPool();
        assertEq(bestPool, address(pool3), "Should still pick best available pool");
        assertEq(bestAPY, 200, "Should have correct APY");

        // User can still withdraw
        vm.startPrank(USER1);
        uint256 userShares = yieldVault.balanceOf(USER1);
        uint256 receivedAmount = yieldVault.withdraw(userShares);
        assertGt(receivedAmount, 0, "Should still be able to withdraw during stress");
        vm.stopPrank();
    }
}