// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseTest } from "../shared/BaseTest.t.sol";

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
}