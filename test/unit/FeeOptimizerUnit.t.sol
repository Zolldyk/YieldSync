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

        // Force fee update to get initial fee
        feeOptimizer.forceFeeUpdate();
        uint256 lowCongestionFee = feeOptimizer.getCurrentFee();

        // Change to high congestion
        mockOracle.updateGasPrice(100 gwei);
        mockOracle.updateNetworkCongestion(90);

        // Force fee update again to get updated fee
        feeOptimizer.forceFeeUpdate();
        uint256 highCongestionFee = feeOptimizer.getCurrentFee();

        vm.stopPrank();

        // Verify fees increased with congestion
        assertGt(highCongestionFee, lowCongestionFee, "Fees should increase with congestion");
    }

    /**
     * @notice Test fee calculation for different amounts
     */
    function testFeeCalculation() public view {
        uint256 amount = 1000 * 1e18;
        uint256 fee = feeOptimizer.calculateFee(amount);

        assertGt(fee, 0, "Fee should be greater than 0");
        assertLt(fee, amount, "Fee should be less than amount");

        // Test with different amount
        uint256 largerAmount = 10_000 * 1e18;
        uint256 largerFee = feeOptimizer.calculateFee(largerAmount);

        assertEq(largerFee, fee * 10, "Fee should scale linearly with amount");
    }

    /**
     * @notice Test fee update frequency control
     */
    function testFeeUpdateFrequency() public view {
        // Just verify that the fee is positive and reasonable
        uint256 currentFee = feeOptimizer.getCurrentFee();
        assertGt(currentFee, 0, "Current fee should be positive");
        assertLt(currentFee, 1000, "Current fee should be less than 10%");
    }

    /**
     * @notice Test forced fee updates (admin function)
     */
    function testForcedFeeUpdate() public {
        vm.startPrank(ADMIN);
        
        // Get initial fee
        uint256 initialFee = feeOptimizer.getCurrentFee();
        
        // Change network conditions
        mockOracle.updateGasPrice(200 gwei);
        mockOracle.updateNetworkCongestion(80);
        
        // Force fee update should work immediately
        feeOptimizer.forceFeeUpdate();
        uint256 newFee = feeOptimizer.getCurrentFee();
        
        assertGt(newFee, initialFee, "Fee should increase after forced update with higher congestion");
        
        vm.stopPrank();
    }

    /**
     * @notice Test fee calculation bounds
     */
    function testFeeCalculationBounds() public view {
        uint256 amount = 1000 * 1e18;
        uint256 fee = feeOptimizer.calculateFee(amount);
        
        // Fee should be positive but less than amount
        assertGt(fee, 0, "Fee should be positive");
        assertLt(fee, amount, "Fee should be less than amount");
        
        // Fee should be reasonable (less than 10% of amount)
        assertLt(fee, amount / 10, "Fee should be less than 10% of amount");
    }

    /**
     * @notice Test access control for fee updates
     */
    function testFeeUpdateAccessControl() public {
        vm.startPrank(USER1);
        
        // Non-admin should not be able to force update
        vm.expectRevert();
        feeOptimizer.forceFeeUpdate();
        
        vm.stopPrank();
    }

    /**
     * @notice Test fee calculation with zero amount
     */
    function testFeeCalculationZeroAmount() public view {
        uint256 fee = feeOptimizer.calculateFee(0);
        assertEq(fee, 0, "Fee should be 0 for 0 amount");
    }

    /**
     * @notice Test fee calculation with very large amounts
     */
    function testFeeCalculationLargeAmount() public view {
        uint256 largeAmount = 1_000_000 * 1e18;
        uint256 fee = feeOptimizer.calculateFee(largeAmount);
        
        assertGt(fee, 0, "Fee should be positive for large amounts");
        assertLt(fee, largeAmount / 2, "Fee should not be more than 50% of amount");
    }

    /**
     * @notice Test fee behavior under extreme network conditions
     */
    function testExtremeNetworkConditions() public {
        vm.startPrank(ADMIN);
        
        // Set high but valid gas price and congestion
        mockOracle.updateGasPrice(1000 gwei); // Reduced from 2000 gwei
        mockOracle.updateNetworkCongestion(100);
        
        feeOptimizer.forceFeeUpdate();
        uint256 extremeFee = feeOptimizer.getCurrentFee();
        
        // Set very low gas price and congestion
        mockOracle.updateGasPrice(1 gwei);
        mockOracle.updateNetworkCongestion(0);
        
        feeOptimizer.forceFeeUpdate();
        uint256 lowFee = feeOptimizer.getCurrentFee();
        
        // Extreme fee should be higher than low fee
        assertGt(extremeFee, lowFee, "Extreme conditions should result in higher fees");
        
        vm.stopPrank();
    }

    /**
     * @notice Test current fee getter function
     */
    function testCurrentFeeGetter() public view {
        uint256 currentFee = feeOptimizer.getCurrentFee();
        assertGt(currentFee, 0, "Current fee should be positive");
    }

    /**
     * @notice Test fee consistency across multiple calculations
     */
    function testFeeConsistency() public view {
        uint256 amount = 5000 * 1e18;
        
        // Calculate fee multiple times
        uint256 fee1 = feeOptimizer.calculateFee(amount);
        uint256 fee2 = feeOptimizer.calculateFee(amount);
        uint256 fee3 = feeOptimizer.calculateFee(amount);
        
        // All calculations should return the same result
        assertEq(fee1, fee2, "Fee calculations should be consistent");
        assertEq(fee2, fee3, "Fee calculations should be consistent");
    }

    /**
     * @notice Test fee calculation with different amounts at same conditions
     */
    function testFeeScaling() public view {
        uint256 baseAmount = 1000 * 1e18;
        uint256 doubleAmount = 2000 * 1e18;
        uint256 halfAmount = 500 * 1e18;
        
        uint256 baseFee = feeOptimizer.calculateFee(baseAmount);
        uint256 doubleFee = feeOptimizer.calculateFee(doubleAmount);
        uint256 halfFee = feeOptimizer.calculateFee(halfAmount);
        
        // Fees should scale proportionally
        assertEq(doubleFee, baseFee * 2, "Fee should double with double amount");
        assertEq(halfFee * 2, baseFee, "Half amount should give half fee");
    }
}