// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseTest } from "../shared/BaseTest.t.sol";

/**
 * @title GovernanceUnitTest
 * @notice Unit tests for Governance contract functions
 */
contract GovernanceUnitTest is BaseTest {
    /**
     * @notice Test yield sharing mechanism
     */
    function testYieldSharing() public {
        // First user deposits to get vault shares
        vm.startPrank(USER1);
        mockToken.approve(address(yieldVault), DEPOSIT_AMOUNT);
        uint256 vaultShares = yieldVault.deposit(DEPOSIT_AMOUNT);

        // Share some yield with governance
        yieldVault.approve(address(governanceToken), vaultShares / 10);
        uint256 tokensAwarded = governanceToken.shareYield(vaultShares / 10);

        assertGt(tokensAwarded, 0, "Should receive governance tokens for sharing yield");
        assertEq(
            governanceToken.balanceOf(USER1), tokensAwarded, "User should have governance tokens"
        );

        vm.stopPrank();
    }

    /**
     * @notice Test governance proposal creation and voting
     */
    function testGovernanceProposal() public {
        // Give USER1 some governance tokens first
        vm.startPrank(ADMIN);
        bytes32 govManagerRole = governanceToken.GOVERNANCE_MANAGER_ROLE();
        governanceToken.grantRole(govManagerRole, ADMIN);
        vm.stopPrank();

        // Setup voting power for USER1
        _setupGovernanceTokens(USER1, 10_000 * 1e18);

        vm.startPrank(USER1);

        // Create proposal
        string memory description = "Test proposal";
        uint256 proposalId = governanceToken.createProposal(description);

        assertEq(proposalId, 1, "First proposal should have ID 1");

        // Check proposal details
        (
            address proposer,
            string memory desc,
            uint256 startTime,
            uint256 endTime,
            ,
            ,
            ,
            , // votes data
        ) = governanceToken.getProposal(proposalId);

        assertEq(proposer, USER1, "Proposer should be USER1");
        assertEq(desc, description, "Description should match");
        assertGt(endTime, startTime, "End time should be after start time");

        vm.stopPrank();
    }

    /**
     * @notice Test voting on proposals
     */
    function testVoting() public {
        // Setup governance tokens for users
        _setupGovernanceTokens(USER1, 10_000 * 1e18);
        _setupGovernanceTokens(USER2, 5000 * 1e18);

        // Create proposal
        vm.startPrank(USER1);
        uint256 proposalId = governanceToken.createProposal("Test voting proposal");
        vm.stopPrank();

        // Wait for voting to start
        vm.warp(block.timestamp + 1 days + 1);

        // Vote in favor
        vm.startPrank(USER1);
        governanceToken.vote(proposalId, true);
        vm.stopPrank();

        // Vote against
        vm.startPrank(USER2);
        governanceToken.vote(proposalId, false);
        vm.stopPrank();

        // Check votes
        (,,,, uint256 forVotes, uint256 againstVotes,,,) = governanceToken.getProposal(proposalId);

        assertGt(forVotes, 0, "Should have votes in favor");
        assertGt(againstVotes, 0, "Should have votes against");
        assertGt(forVotes, againstVotes, "For votes should be greater (USER1 has more tokens)");
    }
}