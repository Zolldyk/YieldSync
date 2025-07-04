// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseTest } from "../shared/BaseTest.t.sol";

/**
 * @title YieldVaultFuzzTest
 * @notice Fuzz tests for YieldVault contract
 */
contract YieldVaultFuzzTest is BaseTest {
    /**
     * @notice Fuzz test deposit amounts
     */
    function testFuzzDeposit(uint256 amount) public {
        // Bound amount to reasonable range
        amount = bound(amount, 1e18, 1_000_000e18);

        // Mint tokens for user
        mockToken.mint(USER1, amount);

        vm.startPrank(USER1);
        mockToken.approve(address(yieldVault), amount);

        uint256 shares = yieldVault.deposit(amount);

        assertGt(shares, 0, "Should receive shares for any valid deposit");
        assertEq(yieldVault.balanceOf(USER1), shares, "Share balance should match returned shares");

        vm.stopPrank();
    }

    /**
     * @notice Fuzz test withdraw amounts
     */
    function testFuzzWithdraw(uint256 depositAmount, uint256 withdrawShares) public {
        // Bound amounts to reasonable ranges
        depositAmount = bound(depositAmount, 1e18, 1_000_000e18);
        
        // Mint tokens and make initial deposit
        mockToken.mint(USER1, depositAmount);
        
        vm.startPrank(USER1);
        mockToken.approve(address(yieldVault), depositAmount);
        uint256 totalShares = yieldVault.deposit(depositAmount);
        
        // Bound withdraw amount to available shares
        withdrawShares = bound(withdrawShares, 1, totalShares);
        
        uint256 balanceBefore = mockToken.balanceOf(USER1);
        uint256 amountReceived = yieldVault.withdraw(withdrawShares);
        uint256 balanceAfter = mockToken.balanceOf(USER1);
        
        assertEq(balanceAfter - balanceBefore, amountReceived, "Balance change should match returned amount");
        assertGt(amountReceived, 0, "Should receive some tokens for any valid withdrawal");
        
        vm.stopPrank();
    }

    /**
     * @notice Fuzz test multiple user deposits with varying amounts
     */
    function testFuzzMultipleDeposits(uint256 amount1, uint256 amount2, uint256 amount3) public {
        // Bound amounts to reasonable ranges
        amount1 = bound(amount1, 1e18, 100_000e18);
        amount2 = bound(amount2, 1e18, 100_000e18);
        amount3 = bound(amount3, 1e18, 100_000e18);

        // Mint tokens for users
        mockToken.mint(USER1, amount1);
        mockToken.mint(USER2, amount2);
        mockToken.mint(USER3, amount3);

        // User 1 deposits
        vm.startPrank(USER1);
        mockToken.approve(address(yieldVault), amount1);
        uint256 shares1 = yieldVault.deposit(amount1);
        vm.stopPrank();

        // User 2 deposits
        vm.startPrank(USER2);
        mockToken.approve(address(yieldVault), amount2);
        uint256 shares2 = yieldVault.deposit(amount2);
        vm.stopPrank();

        // User 3 deposits
        vm.startPrank(USER3);
        mockToken.approve(address(yieldVault), amount3);
        uint256 shares3 = yieldVault.deposit(amount3);
        vm.stopPrank();

        // Verify total supply equals sum of individual shares
        assertEq(
            yieldVault.totalSupply(),
            shares1 + shares2 + shares3,
            "Total supply should equal sum of all issued shares"
        );

        // Verify total assets
        assertEq(
            yieldVault.totalAssets(),
            amount1 + amount2 + amount3,
            "Total assets should equal sum of all deposits"
        );
    }

    /**
     * @notice Fuzz test fee calculations
     */
    function testFuzzFeeCalculation(uint256 amount, uint256 gasPrice, uint256 congestion) public {
        // Bound inputs to reasonable ranges
        amount = bound(amount, 1e18, 1_000_000e18);
        gasPrice = bound(gasPrice, 1 gwei, 1000 gwei);
        congestion = bound(congestion, 0, 100);

        // Update oracle with fuzzed values
        vm.startPrank(ADMIN);
        mockOracle.updateGasPrice(gasPrice);
        mockOracle.updateNetworkCongestion(congestion);
        vm.stopPrank();

        // Update and get fee
        feeOptimizer.updateFee();
        uint256 fee = feeOptimizer.calculateFee(amount);

        // Verify fee bounds
        assertGt(fee, 0, "Fee should be greater than 0");
        assertLt(fee, amount, "Fee should be less than amount");
        
        // Fee should increase with congestion
        if (congestion > 50) {
            uint256 lowCongestionFee = feeOptimizer.calculateFee(amount);
            
            // Set low congestion
            vm.startPrank(ADMIN);
            mockOracle.updateNetworkCongestion(10);
            vm.stopPrank();
            
            vm.warp(block.timestamp + 5 minutes);
            feeOptimizer.updateFee();
            uint256 newLowFee = feeOptimizer.calculateFee(amount);
            
            assertLt(newLowFee, fee, "Fee should be lower with less congestion");
        }
    }

    /**
     * @notice Fuzz test APY updates and rebalancing
     */
    function testFuzzAPYUpdates(uint256 apy1, uint256 apy2, uint256 apy3) public {
        // Bound APYs to reasonable ranges (0-50%)
        apy1 = bound(apy1, 0, 5000);
        apy2 = bound(apy2, 0, 5000);
        apy3 = bound(apy3, 0, 5000);

        // Make initial deposit
        vm.startPrank(USER1);
        mockToken.approve(address(yieldVault), DEPOSIT_AMOUNT);
        yieldVault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Update APYs
        vm.startPrank(ADMIN);
        mockOracle.updatePoolAPY(address(pool1), apy1);
        mockOracle.updatePoolAPY(address(pool2), apy2);
        mockOracle.updatePoolAPY(address(pool3), apy3);
        vm.stopPrank();

        // Wait for rebalance cooldown
        vm.warp(block.timestamp + 2 hours);

        // Trigger rebalancing
        yieldAggregator.rebalancePools();

        // Get best pool
        (address bestPool, uint256 bestAPY) = yieldAggregator.getBestPool();

        // Verify best pool has highest APY
        uint256 maxAPY = apy1 > apy2 ? apy1 : apy2;
        maxAPY = maxAPY > apy3 ? maxAPY : apy3;
        assertEq(bestAPY, maxAPY, "Best pool should have highest APY");

        // Verify correct pool is selected
        if (maxAPY == apy1) {
            assertEq(bestPool, address(pool1), "Pool1 should be selected");
        } else if (maxAPY == apy2) {
            assertEq(bestPool, address(pool2), "Pool2 should be selected");
        } else {
            assertEq(bestPool, address(pool3), "Pool3 should be selected");
        }
    }

    /**
     * @notice Fuzz test time-based operations
     */
    function testFuzzTimeBasedOperations(uint256 timeElapsed) public {
        // Bound time to reasonable range (1 hour to 2 years)
        timeElapsed = bound(timeElapsed, 1 hours, 730 days);

        // Make initial deposit
        vm.startPrank(USER1);
        mockToken.approve(address(yieldVault), DEPOSIT_AMOUNT);
        uint256 shares = yieldVault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Get initial asset value
        uint256 initialAssetValue = yieldVault.getUserAssetBalance(USER1);

        // Advance time
        vm.warp(block.timestamp + timeElapsed);

        // Harvest yield
        vm.startPrank(ADMIN);
        yieldVault.harvestYield();
        vm.stopPrank();

        // Get final asset value
        uint256 finalAssetValue = yieldVault.getUserAssetBalance(USER1);

        // Asset value should have increased (or at least not decreased)
        assertGe(finalAssetValue, initialAssetValue, "Asset value should not decrease over time");

        // User should still be able to withdraw
        vm.startPrank(USER1);
        uint256 amountReceived = yieldVault.withdraw(shares);
        assertGt(amountReceived, 0, "Should be able to withdraw after any time period");
        vm.stopPrank();
    }

    /**
     * @notice Fuzz test edge cases for share calculations
     */
    function testFuzzShareCalculations(uint256 deposit1, uint256 deposit2, uint256 yieldAmount) public {
        // Bound inputs
        deposit1 = bound(deposit1, 1e18, 100_000e18);
        deposit2 = bound(deposit2, 1e18, 100_000e18);
        yieldAmount = bound(yieldAmount, 0, 10_000e18);

        // First user deposits
        mockToken.mint(USER1, deposit1);
        vm.startPrank(USER1);
        mockToken.approve(address(yieldVault), deposit1);
        uint256 shares1 = yieldVault.deposit(deposit1);
        vm.stopPrank();

        // Simulate yield generation
        if (yieldAmount > 0) {
            mockToken.mint(address(yieldVault), yieldAmount);
        }

        // Second user deposits
        mockToken.mint(USER2, deposit2);
        vm.startPrank(USER2);
        mockToken.approve(address(yieldVault), deposit2);
        uint256 shares2 = yieldVault.deposit(deposit2);
        vm.stopPrank();

        // Verify share calculations
        assertGt(shares1, 0, "First user should receive shares");
        assertGt(shares2, 0, "Second user should receive shares");

        // If there was yield, second user should get fewer shares per token
        if (yieldAmount > 0) {
            uint256 shareRatio1 = (shares1 * 1e18) / deposit1;
            uint256 shareRatio2 = (shares2 * 1e18) / deposit2;
            assertLt(shareRatio2, shareRatio1, "Second user should get fewer shares per token due to yield");
        }
    }
}