// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC20Votes } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Nonces } from "@openzeppelin/contracts/utils/Nonces.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IGovernanceToken } from "./interfaces/IGovernanceToken.sol";

/**
 * @title GovernanceToken
 * @author YieldSync Team
 * @notice Governance token with yield sharing capabilities for community participation
 * @dev ERC20 token with voting capabilities and yield sharing mechanism
 *
 * This contract implements:
 * - ERC20 token with permit functionality
 * - Voting delegation and governance participation
 * - Yield sharing mechanism that rewards community participation
 * - Proposal creation and voting system
 * - Time-locked governance actions
 * - Dynamic yield sharing rates based on participation
 *
 * Layout of Contract:
 * - version
 * - imports
 * - errors
 * - interfaces, libraries, contracts
 * - Type declarations
 * - State variables
 * - Events
 * - Modifiers
 * - Functions
 *
 * Layout of Functions:
 * - constructor
 * - receive function (if exists)
 * - fallback function (if exists)
 * - external
 * - public
 * - internal
 * - private
 * - view & pure functions
 */
contract GovernanceToken is
    IGovernanceToken,
    ERC20,
    ERC20Permit,
    ERC20Votes,
    AccessControl,
    ReentrancyGuard,
    Pausable
{
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error GovernanceToken__InsufficientBalance();
    error GovernanceToken__InvalidProposal();
    error GovernanceToken__AlreadyVoted();
    error GovernanceToken__Unauthorized();
    error GovernanceToken__InvalidAddress();
    error GovernanceToken__ProposalNotActive();
    error GovernanceToken__ProposalNotEnded();
    error GovernanceToken__InvalidAmount();
    error GovernanceToken__InvalidYieldShare();
    error GovernanceToken__YieldSharingNotActive();
    error GovernanceToken__InsufficientYield();

    /*//////////////////////////////////////////////////////////////
                            TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    struct Proposal {
        uint256 id; // Proposal ID
        address proposer; // Address of proposer
        string description; // Proposal description
        uint256 startTime; // Voting start time
        uint256 endTime; // Voting end time
        uint256 forVotes; // Votes in favor
        uint256 againstVotes; // Votes against
        uint256 totalVotes; // Total votes cast
        bool executed; // Whether proposal was executed
        bool canceled; // Whether proposal was canceled
        mapping(address => bool) hasVoted; // Track if user has voted
        mapping(address => bool) userVote; // Track user's vote
    }

    struct YieldSharingInfo {
        uint256 totalYieldShared; // Total yield shared by user
        uint256 tokensEarned; // Total tokens earned from sharing
        uint256 lastShareTime; // Last time user shared yield
        uint256 shareCount; // Number of times user shared yield
    }

    struct GovernanceConfig {
        uint256 proposalThreshold; // Minimum tokens needed to propose
        uint256 votingDelay; // Delay before voting starts
        uint256 votingPeriod; // Duration of voting period
        uint256 quorumThreshold; // Minimum participation for valid vote
        uint256 executionDelay; // Delay before execution
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    /// @notice The underlying yield token (e.g., vault shares)
    IERC20 public immutable yieldToken;

    /// @notice Role identifier for governance managers
    bytes32 public constant GOVERNANCE_MANAGER_ROLE = keccak256("GOVERNANCE_MANAGER_ROLE");

    /// @notice Role identifier for yield distributors
    bytes32 public constant YIELD_DISTRIBUTOR_ROLE = keccak256("YIELD_DISTRIBUTOR_ROLE");

    /// @notice Basis points for percentage calculations
    uint256 public constant BASIS_POINTS = 10_000;

    /// @notice Maximum yield sharing rate (10% = 1000 basis points)
    uint256 public constant MAX_YIELD_SHARE_RATE = 1000;

    /// @notice Minimum proposal threshold (0.1% of total supply)
    uint256 public constant MIN_PROPOSAL_THRESHOLD = 10;

    /// @notice Current yield sharing rate (tokens per unit of yield shared)
    uint256 private s_yieldSharingRate;

    /// @notice Total yield in the community pool
    uint256 private s_communityYieldPool;

    /// @notice Governance configuration
    GovernanceConfig private s_governanceConfig;

    /// @notice Current proposal ID counter
    uint256 private s_proposalCounter;

    /// @notice Mapping of proposal ID to proposal data
    mapping(uint256 => Proposal) private s_proposals;

    /// @notice Mapping of user to yield sharing info
    mapping(address => YieldSharingInfo) private s_yieldSharingInfo;

    /// @notice Whether yield sharing is active
    bool private s_yieldSharingActive;

    /// @notice Total tokens distributed through yield sharing
    uint256 private s_totalTokensDistributed;

    /// @notice Total yield collected in community pool
    uint256 private s_totalYieldCollected;

    /// @notice Yield sharing bonus multiplier for early participants
    uint256 private s_bonusMultiplier;

    /// @notice Time when yield sharing started
    uint256 private s_yieldSharingStartTime;

    /// @notice Array of all proposal IDs
    uint256[] private s_proposalIds;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event YieldShared(address indexed user, uint256 amount, uint256 tokensAwarded);
    event GovernanceProposal(
        uint256 indexed proposalId, address indexed proposer, string description
    );
    event VoteCast(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight);
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCanceled(uint256 indexed proposalId);
    event YieldSharingRateUpdated(uint256 newRate);
    event GovernanceConfigUpdated(
        uint256 proposalThreshold,
        uint256 votingDelay,
        uint256 votingPeriod,
        uint256 quorumThreshold
    );
    event YieldSharingToggled(bool active);
    event CommunityYieldWithdrawn(address indexed recipient, uint256 amount);
    event BonusMultiplierUpdated(uint256 newMultiplier);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier onlyGovernanceManager() {
        if (!hasRole(GOVERNANCE_MANAGER_ROLE, msg.sender)) {
            revert GovernanceToken__Unauthorized();
        }
        _;
    }

    modifier onlyYieldDistributor() {
        if (!hasRole(YIELD_DISTRIBUTOR_ROLE, msg.sender)) {
            revert GovernanceToken__Unauthorized();
        }
        _;
    }

    modifier validProposal(uint256 proposalId) {
        if (proposalId == 0 || proposalId > s_proposalCounter) {
            revert GovernanceToken__InvalidProposal();
        }
        _;
    }

    modifier validAddress(address addr) {
        if (addr == address(0)) {
            revert GovernanceToken__InvalidAddress();
        }
        _;
    }

    modifier validAmount(uint256 amount) {
        if (amount == 0) {
            revert GovernanceToken__InvalidAmount();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Initialize the GovernanceToken contract
     * @param _yieldToken The underlying yield token
     * @param _name The name of the governance token
     * @param _symbol The symbol of the governance token
     */
    constructor(
        address _yieldToken,
        string memory _name,
        string memory _symbol
    )
        ERC20(_name, _symbol)
        ERC20Permit(_name)
        validAddress(_yieldToken)
    {
        yieldToken = IERC20(_yieldToken);

        // Initialize governance configuration
        s_governanceConfig = GovernanceConfig({
            proposalThreshold: 100, // 1% of total supply needed to propose
            votingDelay: 1 days, // 1 day delay before voting starts
            votingPeriod: 7 days, // 7 days voting period
            quorumThreshold: 400, // 4% quorum required
            executionDelay: 2 days // 2 days delay before execution
         });

        // Initialize yield sharing
        s_yieldSharingRate = 1000; // 1000 tokens per unit of yield
        s_yieldSharingActive = true;
        s_bonusMultiplier = 150; // 1.5x bonus for early participants
        s_yieldSharingStartTime = block.timestamp;

        // Grant roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(GOVERNANCE_MANAGER_ROLE, msg.sender);
        _grantRole(YIELD_DISTRIBUTOR_ROLE, msg.sender);

        // Mint initial supply to deployer for distribution
        _mint(msg.sender, 1_000_000 * 10 ** decimals()); // 1M initial supply
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Share yield with the community pool
     * @param amount The amount of yield to share
     * @return tokensAwarded The number of governance tokens awarded
     */
    function shareYield(uint256 amount)
        external
        override
        nonReentrant
        whenNotPaused
        validAmount(amount)
        returns (uint256 tokensAwarded)
    {
        if (!s_yieldSharingActive) {
            revert GovernanceToken__YieldSharingNotActive();
        }

        // Check user has sufficient yield tokens
        if (yieldToken.balanceOf(msg.sender) < amount) {
            revert GovernanceToken__InsufficientYield();
        }

        // Calculate tokens to award
        tokensAwarded = _calculateTokensAwarded(amount, msg.sender);

        // Update user's yield sharing info
        YieldSharingInfo storage userInfo = s_yieldSharingInfo[msg.sender];
        userInfo.totalYieldShared += amount;
        userInfo.tokensEarned += tokensAwarded;
        userInfo.lastShareTime = block.timestamp;
        userInfo.shareCount += 1;

        // Update global stats
        s_communityYieldPool += amount;
        s_totalTokensDistributed += tokensAwarded;
        s_totalYieldCollected += amount;

        // Transfer yield from user to contract
        yieldToken.safeTransferFrom(msg.sender, address(this), amount);

        // Mint governance tokens to user
        _mint(msg.sender, tokensAwarded);

        emit YieldShared(msg.sender, amount, tokensAwarded);
    }

    /**
     * @notice Create a governance proposal
     * @param description The proposal description
     * @return proposalId The ID of the created proposal
     */
    function createProposal(string calldata description)
        external
        override
        whenNotPaused
        returns (uint256 proposalId)
    {
        // Check proposer has enough voting power
        uint256 proposerVotes = getVotes(msg.sender);
        uint256 threshold = (totalSupply() * s_governanceConfig.proposalThreshold) / BASIS_POINTS;

        if (proposerVotes < threshold) {
            revert GovernanceToken__InsufficientBalance();
        }

        // Create new proposal
        proposalId = ++s_proposalCounter;
        Proposal storage newProposal = s_proposals[proposalId];

        newProposal.id = proposalId;
        newProposal.proposer = msg.sender;
        newProposal.description = description;
        newProposal.startTime = block.timestamp + s_governanceConfig.votingDelay;
        newProposal.endTime = newProposal.startTime + s_governanceConfig.votingPeriod;
        newProposal.executed = false;
        newProposal.canceled = false;

        s_proposalIds.push(proposalId);

        emit GovernanceProposal(proposalId, msg.sender, description);
    }

    /**
     * @notice Vote on a proposal
     * @param proposalId The proposal ID
     * @param support Whether to support the proposal
     */
    function vote(
        uint256 proposalId,
        bool support
    )
        external
        override
        validProposal(proposalId)
        whenNotPaused
    {
        Proposal storage proposal = s_proposals[proposalId];

        // Check voting is active
        if (block.timestamp < proposal.startTime || block.timestamp > proposal.endTime) {
            revert GovernanceToken__ProposalNotActive();
        }

        // Check user hasn't already voted
        if (proposal.hasVoted[msg.sender]) {
            revert GovernanceToken__AlreadyVoted();
        }

        // Get user's voting power at proposal creation
        uint256 votingPower = getVotes(msg.sender);

        // Record vote
        proposal.hasVoted[msg.sender] = true;
        proposal.userVote[msg.sender] = support;
        proposal.totalVotes += votingPower;

        if (support) {
            proposal.forVotes += votingPower;
        } else {
            proposal.againstVotes += votingPower;
        }

        emit VoteCast(proposalId, msg.sender, support, votingPower);
    }

    /**
     * @notice Execute a passed proposal
     * @param proposalId The proposal ID
     */
    function executeProposal(uint256 proposalId) external validProposal(proposalId) whenNotPaused {
        Proposal storage proposal = s_proposals[proposalId];

        // Check proposal has ended
        if (block.timestamp <= proposal.endTime) {
            revert GovernanceToken__ProposalNotEnded();
        }

        // Check proposal hasn't been executed or canceled
        if (proposal.executed || proposal.canceled) {
            revert GovernanceToken__InvalidProposal();
        }

        // Check quorum
        uint256 quorum = (totalSupply() * s_governanceConfig.quorumThreshold) / BASIS_POINTS;
        if (proposal.totalVotes < quorum) {
            revert GovernanceToken__InvalidProposal();
        }

        // Check proposal passed
        if (proposal.forVotes <= proposal.againstVotes) {
            revert GovernanceToken__InvalidProposal();
        }

        // Check execution delay
        if (block.timestamp < proposal.endTime + s_governanceConfig.executionDelay) {
            revert GovernanceToken__ProposalNotEnded();
        }

        // Mark as executed
        proposal.executed = true;

        emit ProposalExecuted(proposalId);
    }

    /**
     * @notice Cancel a proposal (only by proposer or governance manager)
     * @param proposalId The proposal ID
     */
    function cancelProposal(uint256 proposalId) external validProposal(proposalId) {
        Proposal storage proposal = s_proposals[proposalId];

        // Only proposer or governance manager can cancel
        if (msg.sender != proposal.proposer && !hasRole(GOVERNANCE_MANAGER_ROLE, msg.sender)) {
            revert GovernanceToken__Unauthorized();
        }

        // Can't cancel executed proposals
        if (proposal.executed) {
            revert GovernanceToken__InvalidProposal();
        }

        proposal.canceled = true;

        emit ProposalCanceled(proposalId);
    }

    /**
     * @notice Distribute community yield to governance token holders
     * @param amount The amount to distribute
     */
    function distributeCommunityYield(uint256 amount)
        external
        onlyYieldDistributor
        validAmount(amount)
    {
        if (amount > s_communityYieldPool) {
            revert GovernanceToken__InsufficientYield();
        }

        s_communityYieldPool -= amount;

        // For simplicity, send to governance manager to handle distribution
        yieldToken.safeTransfer(msg.sender, amount);

        emit CommunityYieldWithdrawn(msg.sender, amount);
    }

    /**
     * @notice Update yield sharing rate
     * @param newRate The new rate (tokens per unit of yield)
     */
    function setYieldSharingRate(uint256 newRate)
        external
        onlyGovernanceManager
        validAmount(newRate)
    {
        s_yieldSharingRate = newRate;
        emit YieldSharingRateUpdated(newRate);
    }

    /**
     * @notice Toggle yield sharing on/off
     * @param active Whether yield sharing should be active
     */
    function toggleYieldSharing(bool active) external onlyGovernanceManager {
        s_yieldSharingActive = active;
        emit YieldSharingToggled(active);
    }

    /**
     * @notice Update governance configuration
     * @param proposalThreshold Minimum tokens needed to propose (basis points)
     * @param votingDelay Delay before voting starts
     * @param votingPeriod Duration of voting period
     * @param quorumThreshold Minimum participation for valid vote (basis points)
     * @param executionDelay Delay before execution
     */
    function updateGovernanceConfig(
        uint256 proposalThreshold,
        uint256 votingDelay,
        uint256 votingPeriod,
        uint256 quorumThreshold,
        uint256 executionDelay
    )
        external
        onlyGovernanceManager
    {
        if (proposalThreshold < MIN_PROPOSAL_THRESHOLD || proposalThreshold > 1000) {
            revert GovernanceToken__InvalidAmount();
        }

        if (quorumThreshold > 5000) {
            // Max 50% quorum
            revert GovernanceToken__InvalidAmount();
        }

        s_governanceConfig = GovernanceConfig({
            proposalThreshold: proposalThreshold,
            votingDelay: votingDelay,
            votingPeriod: votingPeriod,
            quorumThreshold: quorumThreshold,
            executionDelay: executionDelay
        });

        emit GovernanceConfigUpdated(proposalThreshold, votingDelay, votingPeriod, quorumThreshold);
    }

    /**
     * @notice Update bonus multiplier for early yield sharers
     * @param newMultiplier The new multiplier (basis points, 10000 = 1x)
     */
    function setBonusMultiplier(uint256 newMultiplier) external onlyGovernanceManager {
        if (newMultiplier > 300) {
            // Max 3x multiplier
            revert GovernanceToken__InvalidAmount();
        }

        s_bonusMultiplier = newMultiplier;
        emit BonusMultiplierUpdated(newMultiplier);
    }

    /**
     * @notice Pause the contract
     */
    function pause() external onlyGovernanceManager {
        _pause();
    }

    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyGovernanceManager {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Get the current yield sharing rate
     * @return rate The current rate (tokens per unit of yield shared)
     */
    function getYieldSharingRate() public view override returns (uint256 rate) {
        rate = s_yieldSharingRate;
    }

    /**
     * @notice Get user's voting power
     * @param user The user address
     * @return votingPower The user's voting power
     */
    function getVotingPower(address user) public view override returns (uint256 votingPower) {
        votingPower = getVotes(user);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Calculate tokens awarded for yield sharing
     * @param amount The amount of yield shared
     * @param user The user sharing yield
     * @return tokensAwarded The tokens to award
     */
    function _calculateTokensAwarded(
        uint256 amount,
        address user
    )
        internal
        view
        returns (uint256 tokensAwarded)
    {
        tokensAwarded = amount * s_yieldSharingRate;

        // Apply bonus for early participants
        if (block.timestamp < s_yieldSharingStartTime + 30 days) {
            tokensAwarded = (tokensAwarded * s_bonusMultiplier) / 100;
        }

        // Apply bonus for frequent sharers
        YieldSharingInfo memory userInfo = s_yieldSharingInfo[user];
        if (userInfo.shareCount >= 10) {
            tokensAwarded = (tokensAwarded * 110) / 100; // 10% bonus for 10+ shares
        } else if (userInfo.shareCount >= 5) {
            tokensAwarded = (tokensAwarded * 105) / 100; // 5% bonus for 5+ shares
        }
    }

    /**
     * @notice Override required by Solidity for multiple inheritance
     */
    function _update(
        address from,
        address to,
        uint256 amount
    )
        internal
        override(ERC20, ERC20Votes)
    {
        super._update(from, to, amount);
    }

    /**
     * @notice Override required by Solidity for multiple inheritance
     */
    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Get proposal information
     * @param proposalId The proposal ID
     * @return proposer The proposer address
     * @return description The proposal description
     * @return startTime The voting start time
     * @return endTime The voting end time
     * @return forVotes Votes in favor
     * @return againstVotes Votes against
     * @return totalVotes Total votes cast
     * @return executed Whether proposal was executed
     * @return canceled Whether proposal was canceled
     */
    function getProposal(uint256 proposalId)
        external
        view
        validProposal(proposalId)
        returns (
            address proposer,
            string memory description,
            uint256 startTime,
            uint256 endTime,
            uint256 forVotes,
            uint256 againstVotes,
            uint256 totalVotes,
            bool executed,
            bool canceled
        )
    {
        Proposal storage proposal = s_proposals[proposalId];
        return (
            proposal.proposer,
            proposal.description,
            proposal.startTime,
            proposal.endTime,
            proposal.forVotes,
            proposal.againstVotes,
            proposal.totalVotes,
            proposal.executed,
            proposal.canceled
        );
    }

    /**
     * @notice Check if user has voted on a proposal
     * @param proposalId The proposal ID
     * @param user The user address
     * @return hasVoted Whether user has voted
     * @return voteChoice The user's vote (if voted)
     */
    function getUserVote(
        uint256 proposalId,
        address user
    )
        external
        view
        validProposal(proposalId)
        returns (bool hasVoted, bool voteChoice)
    {
        Proposal storage proposal = s_proposals[proposalId];
        hasVoted = proposal.hasVoted[user];
        voteChoice = proposal.userVote[user];
    }

    /**
     * @notice Get user's yield sharing information
     * @param user The user address
     * @return info The yield sharing information
     */
    function getYieldSharingInfo(address user)
        external
        view
        returns (YieldSharingInfo memory info)
    {
        info = s_yieldSharingInfo[user];
    }

    /**
     * @notice Get governance configuration
     * @return config The governance configuration
     */
    function getGovernanceConfig() external view returns (GovernanceConfig memory config) {
        config = s_governanceConfig;
    }

    /**
     * @notice Get current proposal counter
     * @return counter The current proposal counter
     */
    function getProposalCounter() external view returns (uint256 counter) {
        counter = s_proposalCounter;
    }

    /**
     * @notice Get all proposal IDs
     * @return proposalIds Array of all proposal IDs
     */
    function getAllProposalIds() external view returns (uint256[] memory proposalIds) {
        proposalIds = s_proposalIds;
    }

    /**
     * @notice Get active proposals
     * @return activeProposals Array of active proposal IDs
     */
    function getActiveProposals() external view returns (uint256[] memory activeProposals) {
        uint256 activeCount = 0;

        // Count active proposals
        for (uint256 i = 0; i < s_proposalIds.length; i++) {
            uint256 proposalId = s_proposalIds[i];
            Proposal storage proposal = s_proposals[proposalId];

            if (
                !proposal.executed && !proposal.canceled && block.timestamp >= proposal.startTime
                    && block.timestamp <= proposal.endTime
            ) {
                activeCount++;
            }
        }

        // Create array of active proposals
        activeProposals = new uint256[](activeCount);
        uint256 index = 0;

        for (uint256 i = 0; i < s_proposalIds.length; i++) {
            uint256 proposalId = s_proposalIds[i];
            Proposal storage proposal = s_proposals[proposalId];

            if (
                !proposal.executed && !proposal.canceled && block.timestamp >= proposal.startTime
                    && block.timestamp <= proposal.endTime
            ) {
                activeProposals[index] = proposalId;
                index++;
            }
        }
    }

    /**
     * @notice Get community yield pool balance
     * @return balance The community yield pool balance
     */
    function getCommunityYieldPool() external view returns (uint256 balance) {
        balance = s_communityYieldPool;
    }

    /**
     * @notice Get total tokens distributed through yield sharing
     * @return total The total tokens distributed
     */
    function getTotalTokensDistributed() external view returns (uint256 total) {
        total = s_totalTokensDistributed;
    }

    /**
     * @notice Get total yield collected
     * @return total The total yield collected
     */
    function getTotalYieldCollected() external view returns (uint256 total) {
        total = s_totalYieldCollected;
    }

    /**
     * @notice Check if yield sharing is active
     * @return active Whether yield sharing is active
     */
    function isYieldSharingActive() external view returns (bool active) {
        active = s_yieldSharingActive;
    }

    /**
     * @notice Get bonus multiplier
     * @return multiplier The current bonus multiplier
     */
    function getBonusMultiplier() external view returns (uint256 multiplier) {
        multiplier = s_bonusMultiplier;
    }

    /**
     * @notice Get yield sharing start time
     * @return startTime The yield sharing start time
     */
    function getYieldSharingStartTime() external view returns (uint256 startTime) {
        startTime = s_yieldSharingStartTime;
    }

    /**
     * @notice Preview tokens that would be awarded for yield sharing
     * @param amount The amount of yield to share
     * @param user The user sharing yield
     * @return tokensAwarded The tokens that would be awarded
     */
    function previewYieldShare(
        uint256 amount,
        address user
    )
        external
        view
        returns (uint256 tokensAwarded)
    {
        tokensAwarded = _calculateTokensAwarded(amount, user);
    }

    /**
     * @notice Get proposal state
     * @param proposalId The proposal ID
     * @return state The proposal state (0: pending, 1: active, 2: passed, 3: failed, 4: executed,
     * 5: canceled)
     */
    function getProposalState(uint256 proposalId)
        external
        view
        validProposal(proposalId)
        returns (uint256 state)
    {
        Proposal storage proposal = s_proposals[proposalId];

        if (proposal.canceled) {
            return 5; // Canceled
        }

        if (proposal.executed) {
            return 4; // Executed
        }

        if (block.timestamp < proposal.startTime) {
            return 0; // Pending
        }

        if (block.timestamp <= proposal.endTime) {
            return 1; // Active
        }

        // Check if passed
        uint256 quorum = (totalSupply() * s_governanceConfig.quorumThreshold) / BASIS_POINTS;
        if (proposal.totalVotes >= quorum && proposal.forVotes > proposal.againstVotes) {
            return 2; // Passed
        } else {
            return 3; // Failed
        }
    }

    /**
     * @notice Get top yield sharers
     * @param count Number of top sharers to return
     * @return sharers Array of top sharer addresses
     * @return amounts Array of yield amounts shared
     */
    function getTopYieldSharers(uint256 count)
        external
        pure
        returns (address[] memory sharers, uint256[] memory amounts)
    {
        // This is a simplified implementation
        // In production, you might want to maintain a sorted list
        sharers = new address[](count);
        amounts = new uint256[](count);

        // Return empty arrays for now - would need to track all users
        // and sort by yield shared in a real implementation
    }
}
