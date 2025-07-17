// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseTest } from "../shared/BaseTest.t.sol";
import { IYieldAggregator } from "../../src/interfaces/IYieldAggregator.sol";
import { YieldAggregator } from "../../src/YieldAggregator.sol";

/**
 * @title YieldAggregatorUnitTest
 * @notice Unit tests for YieldAggregator contract functions
 */
contract YieldAggregatorUnitTest is BaseTest {
    /**
     * @notice Test that funds are allocated to the best performing pool
     */
    function testFundAllocation() public {
        vm.startPrank(USER1);
        mockToken.approve(address(yieldVault), DEPOSIT_AMOUNT);
        yieldVault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Check that funds were allocated to the highest APY pool (pool3)
        (address bestPool, uint256 bestAPY) = yieldAggregator.getBestPool();
        assertEq(bestPool, address(pool3), "Best pool should be pool3 with highest APY");
        assertEq(bestAPY, POOL_APY_3, "Best APY should match pool3's APY");

        // Verify allocation
        uint256 pool3Allocation = yieldAggregator.getPoolInfo(address(pool3)).allocation;
        assertGt(pool3Allocation, 0, "Pool3 should have received allocation");
    }

    /**
     * @notice Test rebalancing when APYs change
     */
    function testRebalancing() public {
        // Disable auto-update mode to prevent APY fluctuations during test
        vm.startPrank(ADMIN);
        mockOracle.updateOracleConfig(
            5 minutes, // gasUpdateInterval
            5 minutes, // congestionUpdateInterval
            5 minutes, // apyUpdateInterval
            200, // gasVolatility
            100, // congestionVolatility
            false // autoUpdate - set to false
        );
        vm.stopPrank();

        // Initial deposit
        vm.startPrank(USER1);
        mockToken.approve(address(yieldVault), DEPOSIT_AMOUNT);
        yieldVault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Change APYs to make pool1 the best
        vm.startPrank(ADMIN);
        mockOracle.updatePoolAPY(address(pool1), 2000); // 20% APY
        vm.stopPrank();

        // Wait for rebalance cooldown
        vm.warp(block.timestamp + 2 hours);

        // Trigger rebalancing
        yieldAggregator.rebalancePools();

        // Verify rebalancing occurred
        (address newBestPool,) = yieldAggregator.getBestPool();
        assertEq(newBestPool, address(pool1), "Pool1 should now be the best pool");
    }

    /**
     * @notice Test adding and removing pools
     */
    function testPoolManagement() public {
        vm.startPrank(ADMIN);

        // Add a new pool
        address newPool = address(0x1234);
        yieldAggregator.addPool(newPool, 1500); // 15% APY

        // Verify pool was added
        IYieldAggregator.PoolInfo memory poolInfo = yieldAggregator.getPoolInfo(newPool);
        assertEq(poolInfo.poolAddress, newPool, "Pool address should match");
        assertEq(poolInfo.apy, 1500, "APY should match");
        assertTrue(poolInfo.isActive, "Pool should be active");

        // Remove the pool
        yieldAggregator.removePool(newPool);

        // Verify pool was removed
        poolInfo = yieldAggregator.getPoolInfo(newPool);
        assertFalse(poolInfo.isActive, "Pool should be inactive after removal");

        vm.stopPrank();
    }

    /**
     * @notice Test pool management access control
     */
    function testPoolManagementAccessControl() public {
        vm.startPrank(USER1);

        // Try to add pool as non-admin
        vm.expectRevert();
        yieldAggregator.addPool(address(0x1234), 1500);

        // Try to remove pool as non-admin
        vm.expectRevert();
        yieldAggregator.removePool(address(pool1));

        vm.stopPrank();
    }

    /**
     * @notice Test emergency withdrawal
     */
    function testEmergencyWithdrawal() public {
        // Make initial deposit
        vm.startPrank(USER1);
        mockToken.approve(address(yieldVault), DEPOSIT_AMOUNT);
        yieldVault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Check initial vault balance
        uint256 initialVaultBalance = mockToken.balanceOf(address(yieldVault));

        // Emergency withdrawal by admin
        vm.startPrank(ADMIN);
        yieldAggregator.emergencyWithdrawAll();
        vm.stopPrank();

        // Verify funds were returned to vault
        uint256 finalVaultBalance = mockToken.balanceOf(address(yieldVault));
        assertGt(
            finalVaultBalance,
            initialVaultBalance,
            "Vault should have more funds after emergency withdrawal"
        );
    }

    /**
     * @notice Test rebalance parameters update
     */
    function testRebalanceParametersUpdate() public {
        vm.startPrank(ADMIN);

        // Update rebalance parameters
        yieldAggregator.updateRebalanceParameters(20, 300, 150);

        // Verify parameters were updated
        YieldAggregator.RebalanceParams memory params = yieldAggregator.getRebalanceParameters();
        assertEq(params.minSlippage, 20, "Min slippage should be updated");
        assertEq(params.maxSlippage, 300, "Max slippage should be updated");
        assertEq(params.rebalanceThreshold, 150, "Rebalance threshold should be updated");

        vm.stopPrank();
    }

    /**
     * @notice Test allocation limits update
     */
    function testAllocationLimitsUpdate() public {
        vm.startPrank(ADMIN);

        // Update allocation limits
        yieldAggregator.updateAllocationLimits(6000, 2000);

        // Verify limits were updated
        (uint256 maxPoolAllocation, uint256 minAllocation) = yieldAggregator.getAllocationLimits();
        assertEq(maxPoolAllocation, 6000, "Max pool allocation should be updated");
        assertEq(minAllocation, 2000, "Min allocation should be updated");

        vm.stopPrank();
    }

    /**
     * @notice Test pause/unpause functionality
     */
    function testPauseUnpause() public {
        vm.startPrank(ADMIN);

        // Pause aggregator
        yieldAggregator.pause();

        // Verify paused
        assertTrue(yieldAggregator.paused(), "Aggregator should be paused");

        // Try to allocate funds while paused
        vm.stopPrank();
        vm.startPrank(USER1);
        mockToken.approve(address(yieldVault), DEPOSIT_AMOUNT);
        vm.expectRevert();
        yieldVault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Unpause
        vm.startPrank(ADMIN);
        yieldAggregator.unpause();
        assertFalse(yieldAggregator.paused(), "Aggregator should be unpaused");
        vm.stopPrank();
    }

    /**
     * @notice Test large deposit allocation distribution
     */
    function testLargeDepositAllocation() public {
        // Make very large deposit to test distribution
        uint256 largeAmount = 100_000 * 1e18;
        mockToken.mint(USER1, largeAmount);

        vm.startPrank(USER1);
        mockToken.approve(address(yieldVault), largeAmount);
        yieldVault.deposit(largeAmount);
        vm.stopPrank();

        // Verify funds were distributed across pools
        uint256 pool1Allocation = yieldAggregator.getPoolInfo(address(pool1)).allocation;
        uint256 pool2Allocation = yieldAggregator.getPoolInfo(address(pool2)).allocation;
        uint256 pool3Allocation = yieldAggregator.getPoolInfo(address(pool3)).allocation;

        uint256 totalAllocation = pool1Allocation + pool2Allocation + pool3Allocation;
        assertEq(totalAllocation, largeAmount, "Total allocation should equal deposit");

        // At least two pools should have allocation
        uint256 poolsWithAllocation = 0;
        if (pool1Allocation > 0) poolsWithAllocation++;
        if (pool2Allocation > 0) poolsWithAllocation++;
        if (pool3Allocation > 0) poolsWithAllocation++;

        assertGe(
            poolsWithAllocation, 2, "Large deposit should be distributed across multiple pools"
        );
    }

    /**
     * @notice Test pool allocation percentage calculations
     */
    function testPoolAllocationPercentages() public {
        vm.startPrank(USER1);
        mockToken.approve(address(yieldVault), DEPOSIT_AMOUNT);
        yieldVault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Get allocation percentages
        uint256 pool1Percentage = yieldAggregator.getPoolAllocationPercentage(address(pool1));
        uint256 pool2Percentage = yieldAggregator.getPoolAllocationPercentage(address(pool2));
        uint256 pool3Percentage = yieldAggregator.getPoolAllocationPercentage(address(pool3));

        // Total should equal 100% (10000 basis points)
        assertEq(
            pool1Percentage + pool2Percentage + pool3Percentage,
            10_000,
            "Total allocation should be 100%"
        );
    }

    /**
     * @notice Test rebalance cooldown period
     */
    function testRebalanceCooldown() public {
        vm.startPrank(USER1);
        mockToken.approve(address(yieldVault), DEPOSIT_AMOUNT);
        yieldVault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Try to rebalance immediately (should skip due to cooldown)
        yieldAggregator.rebalancePools();

        // Change APYs
        vm.startPrank(ADMIN);
        mockOracle.updateOracleConfig(5 minutes, 5 minutes, 5 minutes, 100, 100, false);
        mockOracle.updatePoolAPY(address(pool1), 2000);
        vm.stopPrank();

        // Try to rebalance again (should still skip due to cooldown)
        yieldAggregator.rebalancePools();

        // Wait for cooldown period
        vm.warp(block.timestamp + 2 hours);

        // Now rebalancing should work
        yieldAggregator.rebalancePools();

        (address bestPool,) = yieldAggregator.getBestPool();
        assertEq(bestPool, address(pool1), "Pool1 should be best after cooldown");
    }

    /**
     * @notice Test rebalance needed detection
     */
    function testRebalanceNeeded() public {
        vm.startPrank(USER1);
        mockToken.approve(address(yieldVault), DEPOSIT_AMOUNT);
        yieldVault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Should not need rebalance initially
        (bool needed, uint256 reason) = yieldAggregator.isRebalanceNeeded();
        assertFalse(needed, "Should not need rebalance initially");

        // Change APYs significantly
        vm.startPrank(ADMIN);
        mockOracle.updateOracleConfig(5 minutes, 5 minutes, 5 minutes, 100, 100, false);
        mockOracle.updatePoolAPY(address(pool1), 2500);
        vm.stopPrank();

        // Wait for cooldown
        vm.warp(block.timestamp + 2 hours);

        // Should need rebalance now
        (needed, reason) = yieldAggregator.isRebalanceNeeded();
        assertTrue(needed, "Should need rebalance after APY change");
        assertEq(reason, 1, "Reason should be APY difference");
    }

    /**
     * @notice Test pool count tracking
     */
    function testPoolCount() public {
        (uint256 totalPools, uint256 activePools) = yieldAggregator.getPoolCount();
        assertEq(totalPools, 3, "Should have 3 total pools");
        assertEq(activePools, 3, "Should have 3 active pools");

        // Remove a pool
        vm.startPrank(ADMIN);
        yieldAggregator.removePool(address(pool1));
        vm.stopPrank();

        (totalPools, activePools) = yieldAggregator.getPoolCount();
        assertEq(totalPools, 2, "Should have 2 total pools after removal");
        assertEq(activePools, 2, "Should have 2 active pools after removal");
    }

    /**
     * @notice Test estimated yield calculations
     */
    function testEstimatedYield() public view {
        uint256 amount = 10_000 * 1e18;
        uint256 duration = 365 days;

        uint256 estimatedYield = yieldAggregator.getEstimatedYield(amount, duration);
        assertGt(estimatedYield, 0, "Estimated yield should be positive");

        // Test with different duration
        uint256 halfYearYield = yieldAggregator.getEstimatedYield(amount, 182 days);
        assertLt(halfYearYield, estimatedYield, "Half year yield should be less than full year");
    }

    /**
     * @notice Test allocation preview
     */
    function testAllocationPreview() public view {
        uint256 amount = 10_000 * 1e18;

        (address[] memory pools, uint256[] memory allocations) =
            yieldAggregator.previewAllocation(amount);

        assertGt(pools.length, 0, "Should have at least one pool in preview");
        assertEq(
            pools.length, allocations.length, "Pools and allocations arrays should be same length"
        );

        uint256 totalPreviewAllocation = 0;
        for (uint256 i = 0; i < allocations.length; i++) {
            totalPreviewAllocation += allocations[i];
        }

        assertEq(
            totalPreviewAllocation, amount, "Total preview allocation should equal input amount"
        );
    }

    /**
     * @notice Test invalid pool operations
     */
    function testInvalidPoolOperations() public {
        vm.startPrank(ADMIN);

        // Try to add existing pool
        vm.expectRevert();
        yieldAggregator.addPool(address(pool1), 1500);

        // Try to add pool with invalid APY
        vm.expectRevert();
        yieldAggregator.addPool(address(0x1234), 60_000); // 600% APY

        // Try to remove non-existent pool
        vm.expectRevert();
        yieldAggregator.removePool(address(0x5678));

        // Try to update rebalance parameters with invalid values
        vm.expectRevert();
        yieldAggregator.updateRebalanceParameters(500, 100, 50); // min > max

        vm.stopPrank();
    }

    /**
     * @notice Test zero allocation scenario
     */
    function testZeroAllocation() public view {
        // Don't make any deposits

        // Get allocation percentages when no allocations exist
        uint256 pool1Percentage = yieldAggregator.getPoolAllocationPercentage(address(pool1));
        assertEq(pool1Percentage, 0, "Pool percentage should be 0 when no allocations");

        // Test estimated yield with no allocations
        uint256 estimatedYield = yieldAggregator.getEstimatedYield(1000 * 1e18, 365 days);
        assertGt(estimatedYield, 0, "Should still estimate yield even with no current allocations");
    }

    /**
     * @notice Test withdraw for vault functionality
     */
    function testWithdrawForVault() public {
        // Make initial deposit
        vm.startPrank(USER1);
        mockToken.approve(address(yieldVault), DEPOSIT_AMOUNT);
        yieldVault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Get initial vault balance
        uint256 initialVaultBalance = mockToken.balanceOf(address(yieldVault));

        // Withdraw for vault (simulating vault withdrawal)
        vm.startPrank(address(yieldVault));
        yieldAggregator.withdrawForVault(DEPOSIT_AMOUNT / 2);
        vm.stopPrank();

        // Verify vault received funds
        uint256 finalVaultBalance = mockToken.balanceOf(address(yieldVault));
        assertGt(
            finalVaultBalance, initialVaultBalance, "Vault should have received withdrawn funds"
        );
    }

    /**
     * @notice Test vault address setting
     */
    function testVaultAddressSetting() public {
        vm.startPrank(ADMIN);

        address newVault = address(0x9999);
        yieldAggregator.setVault(newVault);

        assertEq(yieldAggregator.vault(), newVault, "Vault address should be updated");

        vm.stopPrank();
    }

    /**
     * @notice Test get all pool info
     */
    function testGetAllPoolInfo() public view {
        IYieldAggregator.PoolInfo[] memory allPools = yieldAggregator.getAllPoolInfo();

        assertEq(allPools.length, 3, "Should return info for all 3 pools");

        for (uint256 i = 0; i < allPools.length; i++) {
            assertTrue(allPools[i].isActive, "All pools should be active");
            assertGt(allPools[i].apy, 0, "All pools should have positive APY");
        }
    }
}
