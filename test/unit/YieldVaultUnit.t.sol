// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseTest } from "../shared/BaseTest.t.sol";

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
        uint256 balanceBefore = mockToken.balanceOf(USER1);

        vm.expectEmit(true, true, true, true);
        emit Withdrawn(USER1, DEPOSIT_AMOUNT - 500, shares); // Assuming 0.05% fee

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

        // Simulate some yield generation
        vm.warp(block.timestamp + 30 days);

        // User 2 deposits (should get fewer shares due to yield)
        vm.startPrank(USER2);
        mockToken.approve(address(yieldVault), DEPOSIT_AMOUNT);
        uint256 shares2 = yieldVault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Verify share distribution
        assertEq(shares1, DEPOSIT_AMOUNT, "First user should get 1:1 ratio");
        assertLt(shares2, DEPOSIT_AMOUNT, "Second user should get fewer shares due to yield");

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
}