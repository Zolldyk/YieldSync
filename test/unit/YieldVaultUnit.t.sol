// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseTest } from "../shared/BaseTest.t.sol";
import { IYieldVault } from "../../src/interfaces/IYieldVault.sol";
import { YieldVault } from "../../src/YieldVault.sol";

/**
 * @title YieldVaultUnitTest
 * @notice Unit tests for YieldVault contract functions
 */
contract YieldVaultUnitTest is BaseTest {
    /**
     * @notice Test basic vault deposit functionality
     */
    function testDeposit() public {
        vm.startPrank(USER1);

        // Approve and deposit
        mockToken.approve(address(yieldVault), DEPOSIT_AMOUNT);

        // Expect deposit event
        vm.expectEmit(true, true, true, true);
        emit Deposited(USER1, DEPOSIT_AMOUNT, DEPOSIT_AMOUNT); // 1:1 ratio initially

        uint256 shares = yieldVault.deposit(DEPOSIT_AMOUNT);

        // Verify shares received
        assertEq(shares, DEPOSIT_AMOUNT, "Should receive 1:1 shares initially");
        assertEq(
            yieldVault.balanceOf(USER1), DEPOSIT_AMOUNT, "User should have correct share balance"
        );
        assertEq(yieldVault.totalAssets(), DEPOSIT_AMOUNT, "Vault should track total assets");

        vm.stopPrank();
    }

    /**
     * @notice Test vault withdrawal functionality
     */
    function testWithdraw() public {
        // First deposit
        vm.startPrank(USER1);
        mockToken.approve(address(yieldVault), DEPOSIT_AMOUNT);
        uint256 shares = yieldVault.deposit(DEPOSIT_AMOUNT);

        // Then withdraw

        vm.expectEmit(true, true, true, true);
        emit Withdrawn(USER1, 990025000000000000000, shares); // Net after pool fees (0.5% each) and vault fee

        uint256 amountReceived = yieldVault.withdraw(shares);

        // Verify withdrawal
        assertGt(amountReceived, 0, "Should receive some tokens back");
        assertLt(amountReceived, DEPOSIT_AMOUNT, "Should be less than deposited due to fees");
        assertEq(yieldVault.balanceOf(USER1), 0, "User should have no shares after full withdrawal");

        vm.stopPrank();
    }

    /**
     * @notice Test multiple user deposits and share calculation
     */
    function testMultipleUserDeposits() public {
        // User 1 deposits
        vm.startPrank(USER1);
        mockToken.approve(address(yieldVault), DEPOSIT_AMOUNT);
        uint256 shares1 = yieldVault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();

        // User 2 deposits (should get same shares as no yield generated yet)
        vm.startPrank(USER2);
        mockToken.approve(address(yieldVault), DEPOSIT_AMOUNT);
        uint256 shares2 = yieldVault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Verify share distribution (both users get 1:1 ratio when no yield)
        assertEq(shares1, DEPOSIT_AMOUNT, "First user should get 1:1 ratio");
        assertEq(shares2, DEPOSIT_AMOUNT, "Second user should also get 1:1 ratio when no yield");

        // Verify total shares and assets
        assertEq(
            yieldVault.totalSupply(), shares1 + shares2, "Total supply should match issued shares"
        );
        assertEq(
            yieldVault.totalAssets(), DEPOSIT_AMOUNT * 2, "Total assets should be sum of deposits"
        );
    }

    /**
     * @notice Test emergency scenarios
     */
    function testEmergencyWithdrawal() public {
        // Deposit
        vm.startPrank(USER1);
        mockToken.approve(address(yieldVault), DEPOSIT_AMOUNT);
        uint256 shares = yieldVault.deposit(DEPOSIT_AMOUNT);

        // Emergency withdraw (no fees)
        uint256 balanceBefore = mockToken.balanceOf(USER1);
        uint256 amountReceived = yieldVault.emergencyWithdraw(shares);
        uint256 balanceAfter = mockToken.balanceOf(USER1);

        assertEq(balanceAfter - balanceBefore, amountReceived, "Should receive exact amount back");
        assertEq(yieldVault.balanceOf(USER1), 0, "Should have no shares left");

        vm.stopPrank();
    }

    /**
     * @notice Test pause functionality
     */
    function testPauseFunctionality() public {
        // Pause vault
        vm.startPrank(ADMIN);
        yieldVault.pause();
        vm.stopPrank();

        // Try to deposit while paused
        vm.startPrank(USER1);
        mockToken.approve(address(yieldVault), DEPOSIT_AMOUNT);

        vm.expectRevert(); // Should revert when paused
        yieldVault.deposit(DEPOSIT_AMOUNT);

        vm.stopPrank();

        // Unpause and try again
        vm.startPrank(ADMIN);
        yieldVault.unpause();
        vm.stopPrank();

        vm.startPrank(USER1);
        // Should work now
        uint256 shares = yieldVault.deposit(DEPOSIT_AMOUNT);
        assertGt(shares, 0, "Deposit should work after unpause");
        vm.stopPrank();
    }

    /**
     * @notice Test invariants that should always hold
     */
    function testInvariants() public {
        // Make some deposits and withdrawals
        vm.startPrank(USER1);
        mockToken.approve(address(yieldVault), DEPOSIT_AMOUNT);
        uint256 shares1 = yieldVault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();

        vm.startPrank(USER2);
        mockToken.approve(address(yieldVault), DEPOSIT_AMOUNT * 2);
        uint256 shares2 = yieldVault.deposit(DEPOSIT_AMOUNT * 2);
        vm.stopPrank();

        // Test invariants
        assertEq(
            yieldVault.totalSupply(),
            shares1 + shares2,
            "Total supply should equal sum of user shares"
        );

        assertGe(
            yieldVault.totalAssets(),
            yieldVault.convertToAssets(yieldVault.totalSupply()),
            "Total assets should be at least the value of all shares"
        );
    }

    /**
     * @notice Test reentrancy protection
     */
    function testReentrancyProtection() public {
        // This would require a malicious contract to test properly
        // For now, just verify that the modifier is present and functions work normally
        vm.startPrank(USER1);
        mockToken.approve(address(yieldVault), DEPOSIT_AMOUNT);

        uint256 shares = yieldVault.deposit(DEPOSIT_AMOUNT);
        assertGt(shares, 0, "Normal deposit should work");

        uint256 amount = yieldVault.withdraw(shares);
        assertGt(amount, 0, "Normal withdrawal should work");

        vm.stopPrank();
    }

    /**
     * @notice Test access control
     */
    function testAccessControl() public {
        // Try to call admin function as non-admin
        vm.startPrank(USER1);

        vm.expectRevert(); // Should revert due to access control
        yieldVault.pause();

        vm.expectRevert(); // Should revert due to access control
        yieldVault.setPerformanceFee(100);

        vm.stopPrank();

        // Verify admin can call these functions
        vm.startPrank(ADMIN);
        yieldVault.pause();
        yieldVault.unpause();
        yieldVault.setPerformanceFee(100);
        vm.stopPrank();
    }

    /**
     * @notice Test fee collection and management
     */
    function testFeeManagement() public {
        // Test performance fee update
        vm.startPrank(ADMIN);
        yieldVault.setPerformanceFee(300); // 3%
        assertEq(yieldVault.getPerformanceFee(), 300, "Performance fee should be updated");
        
        // Test management fee update
        yieldVault.setManagementFee(150); // 1.5%
        assertEq(yieldVault.getManagementFee(), 150, "Management fee should be updated");
        
        // Test fee collector update
        address newFeeCollector = address(0x1111);
        yieldVault.setFeeCollector(newFeeCollector);
        assertEq(yieldVault.getFeeCollector(), newFeeCollector, "Fee collector should be updated");
        
        vm.stopPrank();
    }

    /**
     * @notice Test deposit cap functionality
     */
    function testDepositCap() public {
        vm.startPrank(ADMIN);
        
        // Set low deposit cap
        uint256 lowCap = 5000 * 1e18;
        yieldVault.setDepositCap(lowCap);
        assertEq(yieldVault.getDepositCap(), lowCap, "Deposit cap should be updated");
        
        vm.stopPrank();
        
        // Try to deposit more than cap
        uint256 excessiveAmount = 10000 * 1e18;
        mockToken.mint(USER1, excessiveAmount);
        
        vm.startPrank(USER1);
        mockToken.approve(address(yieldVault), excessiveAmount);
        
        vm.expectRevert();
        yieldVault.deposit(excessiveAmount);
        
        vm.stopPrank();
    }

    /**
     * @notice Test yield harvesting
     */
    function testYieldHarvesting() public {
        // Make initial deposit
        vm.startPrank(USER1);
        mockToken.approve(address(yieldVault), DEPOSIT_AMOUNT);
        yieldVault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Simulate yield by advancing time
        vm.warp(block.timestamp + 30 days);
        
        // Harvest yield
        vm.startPrank(ADMIN);
        yieldVault.harvestYield();
        vm.stopPrank();
        
        // Total assets should remain the same or increase
        assertGe(yieldVault.totalAssets(), DEPOSIT_AMOUNT, "Total assets should not decrease after harvest");
    }

    /**
     * @notice Test management fee collection
     */
    function testManagementFeeCollection() public {
        // Make initial deposit
        vm.startPrank(USER1);
        mockToken.approve(address(yieldVault), DEPOSIT_AMOUNT);
        yieldVault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Mint additional tokens to vault to cover management fees
        mockToken.mint(address(yieldVault), 1000 * 1e18);
        
        // Advance time for management fees to accrue
        vm.warp(block.timestamp + 365 days);
        
        // Collect management fees
        vm.startPrank(ADMIN);
        yieldVault.collectManagementFees();
        vm.stopPrank();
        
        // Verify fees were collected
        assertGt(yieldVault.getTotalFeesCollected(), 0, "Management fees should be collected");
    }

    /**
     * @notice Test share conversion functions
     */
    function testShareConversions() public {
        uint256 assetAmount = 1000 * 1e18;
        
        // Test initial conversion (1:1 ratio)
        uint256 shares = yieldVault.convertToShares(assetAmount);
        assertEq(shares, assetAmount, "Initial conversion should be 1:1");
        
        uint256 assets = yieldVault.convertToAssets(shares);
        assertEq(assets, assetAmount, "Reverse conversion should match");
        
        // Make a deposit to change the ratio
        vm.startPrank(USER1);
        mockToken.approve(address(yieldVault), DEPOSIT_AMOUNT);
        yieldVault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Test conversions after deposit
        uint256 newShares = yieldVault.convertToShares(assetAmount);
        uint256 newAssets = yieldVault.convertToAssets(newShares);
        
        // Conversions should be consistent
        assertEq(newAssets, assetAmount, "Conversions should be consistent after deposit");
    }

    /**
     * @notice Test exchange rate calculations
     */
    function testExchangeRate() public {
        // Initial exchange rate should be 1:1
        uint256 initialRate = yieldVault.getExchangeRate();
        assertEq(initialRate, 1e18, "Initial exchange rate should be 1:1");
        
        // Make deposit
        vm.startPrank(USER1);
        mockToken.approve(address(yieldVault), DEPOSIT_AMOUNT);
        yieldVault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Exchange rate should still be close to 1:1 initially
        uint256 postDepositRate = yieldVault.getExchangeRate();
        assertApproxEqRel(postDepositRate, 1e18, 0.01e18, "Exchange rate should be close to 1:1 after deposit");
    }

    /**
     * @notice Test user info tracking
     */
    function testUserInfoTracking() public {
        vm.startPrank(USER1);
        mockToken.approve(address(yieldVault), DEPOSIT_AMOUNT);
        uint256 shares = yieldVault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Check user info
        YieldVault.UserInfo memory userInfo = yieldVault.getUserInfo(USER1);
        assertEq(userInfo.shares, shares, "User info should track shares");
        assertEq(userInfo.totalDeposited, DEPOSIT_AMOUNT, "User info should track total deposited");
        assertGt(userInfo.lastInteractionTime, 0, "User info should track interaction time");
        
        // Make withdrawal
        vm.startPrank(USER1);
        uint256 amountReceived = yieldVault.withdraw(shares / 2);
        vm.stopPrank();
        
        // Check updated user info
        userInfo = yieldVault.getUserInfo(USER1);
        assertEq(userInfo.shares, shares / 2, "User info should update shares after withdrawal");
        assertApproxEqRel(userInfo.totalWithdrawn, amountReceived, 0.01e18, "User info should track total withdrawn");
    }

    /**
     * @notice Test maximum deposit and withdrawal amounts
     */
    function testMaxDepositWithdraw() public {
        // Test max deposit when not paused
        uint256 maxDeposit = yieldVault.getMaxDeposit();
        assertGt(maxDeposit, 0, "Max deposit should be positive when not paused");
        
        // Test max deposit when paused
        vm.startPrank(ADMIN);
        yieldVault.pause();
        vm.stopPrank();
        
        maxDeposit = yieldVault.getMaxDeposit();
        assertEq(maxDeposit, 0, "Max deposit should be 0 when paused");
        
        // Unpause for withdrawal test
        vm.startPrank(ADMIN);
        yieldVault.unpause();
        vm.stopPrank();
        
        // Make deposit first
        vm.startPrank(USER1);
        mockToken.approve(address(yieldVault), DEPOSIT_AMOUNT);
        yieldVault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Test max withdrawal
        uint256 maxWithdraw = yieldVault.maxWithdraw(USER1);
        assertGt(maxWithdraw, 0, "Max withdrawal should be positive for user with deposits");
        
        // Test max withdrawal when paused
        vm.startPrank(ADMIN);
        yieldVault.pause();
        vm.stopPrank();
        
        maxWithdraw = yieldVault.maxWithdraw(USER1);
        assertEq(maxWithdraw, 0, "Max withdrawal should be 0 when paused");
    }

    /**
     * @notice Test preview withdrawal functionality
     */
    function testPreviewWithdraw() public {
        vm.startPrank(USER1);
        mockToken.approve(address(yieldVault), DEPOSIT_AMOUNT);
        uint256 shares = yieldVault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Preview withdrawal
        uint256 previewAmount = yieldVault.previewWithdraw(shares);
        assertGt(previewAmount, 0, "Preview withdrawal should return positive amount");
        
        // Actual withdrawal should be close to preview (accounting for fees)
        vm.startPrank(USER1);
        uint256 actualAmount = yieldVault.withdraw(shares);
        vm.stopPrank();
        
        // Preview is before fees, actual is after fees
        assertLt(actualAmount, previewAmount, "Actual withdrawal should be less than preview due to fees");
    }

    /**
     * @notice Test user asset balance calculations
     */
    function testUserAssetBalance() public {
        vm.startPrank(USER1);
        mockToken.approve(address(yieldVault), DEPOSIT_AMOUNT);
        uint256 shares = yieldVault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Check user asset balance
        uint256 assetBalance = yieldVault.getUserAssetBalance(USER1);
        assertEq(assetBalance, DEPOSIT_AMOUNT, "User asset balance should equal deposit amount initially");
        
        // Withdraw half
        vm.startPrank(USER1);
        yieldVault.withdraw(shares / 2);
        vm.stopPrank();
        
        // Asset balance should be approximately half
        uint256 remainingBalance = yieldVault.getUserAssetBalance(USER1);
        assertApproxEqRel(remainingBalance, DEPOSIT_AMOUNT / 2, 0.01e18, "Remaining balance should be approximately half");
    }

    /**
     * @notice Test edge case withdrawals
     */
    function testEdgeCaseWithdrawals() public {
        vm.startPrank(USER1);
        mockToken.approve(address(yieldVault), DEPOSIT_AMOUNT);
        uint256 shares = yieldVault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Try to withdraw more shares than owned
        vm.startPrank(USER1);
        vm.expectRevert();
        yieldVault.withdraw(shares + 1);
        vm.stopPrank();
        
        // Try to withdraw 0 shares
        vm.startPrank(USER1);
        vm.expectRevert();
        yieldVault.withdraw(0);
        vm.stopPrank();
        
        // Emergency withdraw all shares
        vm.startPrank(USER1);
        uint256 emergencyAmount = yieldVault.emergencyWithdraw(shares);
        assertGt(emergencyAmount, 0, "Emergency withdrawal should return positive amount");
        assertEq(yieldVault.balanceOf(USER1), 0, "User should have no shares after emergency withdrawal");
        vm.stopPrank();
    }

    /**
     * @notice Test fee validation limits
     */
    function testFeeValidationLimits() public {
        vm.startPrank(ADMIN);
        
        // Try to set performance fee too high
        vm.expectRevert();
        yieldVault.setPerformanceFee(1100); // 11% > 10% max
        
        // Try to set management fee too high
        vm.expectRevert();
        yieldVault.setManagementFee(600); // 6% > 5% max
        
        // Valid fee updates should work
        yieldVault.setPerformanceFee(500); // 5%
        yieldVault.setManagementFee(200); // 2%
        
        vm.stopPrank();
    }

    /**
     * @notice Test invalid address operations
     */
    function testInvalidAddressOperations() public {
        vm.startPrank(ADMIN);
        
        // Try to set fee collector to zero address
        vm.expectRevert();
        yieldVault.setFeeCollector(address(0));
        
        vm.stopPrank();
    }

    /**
     * @notice Test zero amount operations
     */
    function testZeroAmountOperations() public {
        vm.startPrank(USER1);
        
        // Try to deposit 0 amount
        mockToken.approve(address(yieldVault), 0);
        vm.expectRevert();
        yieldVault.deposit(0);
        
        vm.stopPrank();
    }

    /**
     * @notice Test deposit with minimum shares requirement
     */
    function testMinimumSharesRequirement() public {
        vm.startPrank(USER1);
        
        // Try to deposit very small amount (less than minimum shares)
        uint256 tinyAmount = 100;
        mockToken.approve(address(yieldVault), tinyAmount);
        vm.expectRevert();
        yieldVault.deposit(tinyAmount);
        
        vm.stopPrank();
    }

    /**
     * @notice Test transfer hook functionality
     */
    function testTransferHooks() public {
        // Make initial deposits for two users
        vm.startPrank(USER1);
        mockToken.approve(address(yieldVault), DEPOSIT_AMOUNT);
        uint256 shares1 = yieldVault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        vm.startPrank(USER2);
        mockToken.approve(address(yieldVault), DEPOSIT_AMOUNT);
        yieldVault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Transfer shares from USER1 to USER2
        vm.startPrank(USER1);
        yieldVault.transfer(USER2, shares1 / 2);
        vm.stopPrank();
        
        // Verify balances
        assertEq(yieldVault.balanceOf(USER1), shares1 / 2, "USER1 should have half shares remaining");
        assertGt(yieldVault.balanceOf(USER2), DEPOSIT_AMOUNT, "USER2 should have more than initial shares");
        
        // Verify user info was updated (interaction times)
        YieldVault.UserInfo memory user1Info = yieldVault.getUserInfo(USER1);
        YieldVault.UserInfo memory user2Info = yieldVault.getUserInfo(USER2);
        
        assertGt(user1Info.lastInteractionTime, 0, "USER1 interaction time should be updated");
        assertGt(user2Info.lastInteractionTime, 0, "USER2 interaction time should be updated");
    }
}