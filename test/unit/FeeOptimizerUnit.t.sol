// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseTest } from "../shared/BaseTest.t.sol";

/**
 * @title FeeOptimizerUnitTest
 * @notice Unit tests for FeeOptimizer contract functions
 */
contract FeeOptimizerUnitTest is BaseTest {
    /**
     * @notice Test dynamic fee adjustment based on network conditions
     */
    function testDynamicFees() public {
        // Set initial network conditions
        vm.startPrank(ADMIN);
        mockOracle.updateGasPrice(10 gwei);
        mockOracle.updateNetworkCongestion(30);
        vm.stopPrank();

        // Update fees
        feeOptimizer.updateFee();
        uint256 lowCongestionFee = feeOptimizer.getCurrentFee();

        // Change to high congestion
        vm.startPrank(ADMIN);
        mockOracle.updateGasPrice(100 gwei);
        mockOracle.updateNetworkCongestion(90);
        vm.stopPrank();

        // Wait for update interval
        vm.warp(block.timestamp + 5 minutes);

        // Update fees again
        feeOptimizer.updateFee();
        uint256 highCongestionFee = feeOptimizer.getCurrentFee();

        // Verify fees increased with congestion
        assertGt(highCongestionFee, lowCongestionFee, "Fees should increase with congestion");
    }

    /**
     * @notice Test fee calculation for different amounts
     */
    function testFeeCalculation() public {
        uint256 amount = 1000 * 1e18;
        uint256 fee = feeOptimizer.calculateFee(amount);

        assertGt(fee, 0, "Fee should be greater than 0");
        assertLt(fee, amount, "Fee should be less than amount");

        // Test with different amount
        uint256 largerAmount = 10_000 * 1e18;
        uint256 largerFee = feeOptimizer.calculateFee(largerAmount);

        assertEq(largerFee, fee * 10, "Fee should scale linearly with amount");
    }
}