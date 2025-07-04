// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { GovernanceToken } from "../GovernanceToken.sol";

/**
 * @title IGovernanceToken
 * @author YieldSync Team
 * @notice Interface for governance token with yield sharing capabilities
 */
interface IGovernanceToken {
    /**
     * @notice Share yield with the community pool
     * @param amount The amount of yield to share
     * @return tokensAwarded The number of governance tokens awarded
     */
    function shareYield(uint256 amount) external returns (uint256 tokensAwarded);

    /**
     * @notice Get the current yield sharing rate
     * @return rate The current rate (tokens per unit of yield shared)
     */
    function getYieldSharingRate() external view returns (uint256 rate);

    /**
     * @notice Get user's voting power
     * @param user The user address
     * @return votingPower The user's voting power
     */
    function getVotingPower(address user) external view returns (uint256 votingPower);

    /**
     * @notice Create a governance proposal
     * @param description The proposal description
     * @return proposalId The ID of the created proposal
     */
    function createProposal(string calldata description) external returns (uint256 proposalId);

    /**
     * @notice Vote on a proposal
     * @param proposalId The proposal ID
     * @param support Whether to support the proposal
     */
    function vote(uint256 proposalId, bool support) external;
}
