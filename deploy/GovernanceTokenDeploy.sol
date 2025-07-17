// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Import statements - you'll need to flatten the contract for BlockDAG IDE
// This is a flattened version ready for direct deployment

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Nonces.sol";

/**
 * @title IGovernanceToken
 * @notice Interface for governance token functionality
 */
interface IGovernanceToken {
    function shareYield(uint256 amount) external returns (uint256 tokensAwarded);
    function createProposal(string calldata description) external returns (uint256 proposalId);
    function vote(uint256 proposalId, bool support) external;
    function getYieldSharingRate() external view returns (uint256 rate);
    function getVotingPower(address user) external view returns (uint256 votingPower);
}

/**
 * @title GovernanceToken
 * @notice Updated governance token with full voting functionality
 */
contract GovernanceToken is IGovernanceToken, ERC20, ERC20Votes, ERC20Permit, AccessControl {
    error InvalidAmount();
    error Unauthorized();
    error YieldSharingNotActive();
    error InsufficientYield();

    struct YieldSharingInfo {
        uint256 totalYieldShared;
        uint256 tokensEarned;
        uint256 lastShareTime;
        uint256 shareCount;
    }

    struct Proposal {
        address proposer;
        string description;
        uint256 startTime;
        uint256 endTime;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 totalVotes;
        bool executed;
        bool canceled;
        mapping(address => bool) hasVoted;
        mapping(address => bool) voteChoice;
    }

    IERC20 public immutable yieldToken;
    bytes32 public constant YIELD_DISTRIBUTOR_ROLE = keccak256("YIELD_DISTRIBUTOR_ROLE");
    bytes32 public constant GOVERNANCE_MANAGER_ROLE = keccak256("GOVERNANCE_MANAGER_ROLE");

    uint256 private _yieldSharingRate;
    uint256 private _communityYieldPool;
    mapping(address => YieldSharingInfo) private _yieldSharingInfo;
    bool private _yieldSharingActive;
    uint256 private _totalTokensDistributed;
    
    // Governance state variables
    uint256 private _proposalCounter;
    mapping(uint256 => Proposal) private _proposals;
    uint256 public constant VOTING_PERIOD = 7 days;
    uint256 public constant MIN_PROPOSAL_THRESHOLD = 1000 * 10**18; // Minimum tokens to create proposal

    event YieldShared(address indexed user, uint256 amount, uint256 tokensAwarded);
    event YieldSharingRateUpdated(uint256 newRate);
    event YieldSharingToggled(bool active);
    
    // Governance events
    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, string description);
    event VoteCast(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight);

    modifier onlyYieldDistributor() {
        if (!hasRole(YIELD_DISTRIBUTOR_ROLE, msg.sender)) {
            revert Unauthorized();
        }
        _;
    }

    modifier validAmount(uint256 amount) {
        if (amount == 0) {
            revert InvalidAmount();
        }
        _;
    }

    /**
     * @notice Constructor - Deploy with these parameters:
     * @param _yieldToken: 0xE63cE0E709eB6E7f345133C681Ba177df603e804 (YieldVault address)
     * @param _name: "YieldSync Governance"
     * @param _symbol: "YSG"
     */
    constructor(
        address _yieldToken,
        string memory _name,
        string memory _symbol
    )
        ERC20(_name, _symbol)
        ERC20Permit(_name)
    {
        require(_yieldToken != address(0));
        yieldToken = IERC20(_yieldToken);

        _yieldSharingRate = 1000;
        _yieldSharingActive = true;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(YIELD_DISTRIBUTOR_ROLE, msg.sender);

        _mint(msg.sender, 1_000_000 * 10 ** decimals());
    }

    function shareYield(uint256 amount)
        external
        override
        validAmount(amount)
        returns (uint256 tokensAwarded)
    {
        if (!_yieldSharingActive) {
            revert YieldSharingNotActive();
        }

        if (yieldToken.balanceOf(msg.sender) < amount) {
            revert InsufficientYield();
        }

        tokensAwarded = amount * _yieldSharingRate;

        YieldSharingInfo storage userInfo = _yieldSharingInfo[msg.sender];
        userInfo.totalYieldShared += amount;
        userInfo.tokensEarned += tokensAwarded;
        userInfo.lastShareTime = block.timestamp;
        userInfo.shareCount += 1;

        _communityYieldPool += amount;
        _totalTokensDistributed += tokensAwarded;

        yieldToken.transferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, tokensAwarded);

        emit YieldShared(msg.sender, amount, tokensAwarded);
    }

    function createProposal(string calldata description) external override returns (uint256 proposalId) {
        // Check if user has enough voting power to create proposal
        require(getVotes(msg.sender) >= MIN_PROPOSAL_THRESHOLD, "Insufficient voting power");
        require(bytes(description).length > 0, "Empty description");
        
        _proposalCounter++;
        proposalId = _proposalCounter;
        
        Proposal storage proposal = _proposals[proposalId];
        proposal.proposer = msg.sender;
        proposal.description = description;
        proposal.startTime = block.timestamp;
        proposal.endTime = block.timestamp + VOTING_PERIOD;
        proposal.executed = false;
        proposal.canceled = false;
        
        emit ProposalCreated(proposalId, msg.sender, description);
    }

    function vote(uint256 proposalId, bool support) external override {
        Proposal storage proposal = _proposals[proposalId];
        require(proposal.proposer != address(0), "Proposal does not exist");
        require(block.timestamp >= proposal.startTime, "Voting not started");
        require(block.timestamp <= proposal.endTime, "Voting period ended");
        require(!proposal.hasVoted[msg.sender], "Already voted");
        
        uint256 weight = getVotes(msg.sender);
        require(weight > 0, "No voting power");
        
        proposal.hasVoted[msg.sender] = true;
        proposal.voteChoice[msg.sender] = support;
        proposal.totalVotes += weight;
        
        if (support) {
            proposal.forVotes += weight;
        } else {
            proposal.againstVotes += weight;
        }
        
        emit VoteCast(proposalId, msg.sender, support, weight);
    }

    function distributeCommunityYield(uint256 amount)
        external
        onlyYieldDistributor
        validAmount(amount)
    {
        if (amount > _communityYieldPool) {
            revert InsufficientYield();
        }

        _communityYieldPool -= amount;
        yieldToken.transfer(msg.sender, amount);
    }

    function setYieldSharingRate(uint256 newRate)
        external
        onlyYieldDistributor
        validAmount(newRate)
    {
        _yieldSharingRate = newRate;
        emit YieldSharingRateUpdated(newRate);
    }

    function toggleYieldSharing(bool active) external onlyYieldDistributor {
        _yieldSharingActive = active;
        emit YieldSharingToggled(active);
    }

    function getYieldSharingRate() public view override returns (uint256 rate) {
        rate = _yieldSharingRate;
    }

    function getVotingPower(address user) public view override returns (uint256 votingPower) {
        votingPower = getVotes(user);
    }

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

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }

    function getProposal(uint256 proposalId)
        external
        view
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
        Proposal storage proposal = _proposals[proposalId];
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

    function getYieldSharingInfo(address user)
        external
        view
        returns (YieldSharingInfo memory info)
    {
        info = _yieldSharingInfo[user];
    }

    function getCommunityYieldPool() external view returns (uint256 balance) {
        balance = _communityYieldPool;
    }

    function getTotalTokensDistributed() external view returns (uint256 total) {
        total = _totalTokensDistributed;
    }

    function isYieldSharingActive() external view returns (bool active) {
        active = _yieldSharingActive;
    }
    
    function getProposalCount() external view returns (uint256) {
        return _proposalCounter;
    }
    
    function hasVoted(uint256 proposalId, address voter) external view returns (bool) {
        return _proposals[proposalId].hasVoted[voter];
    }
    
    function getVoteChoice(uint256 proposalId, address voter) external view returns (bool) {
        require(_proposals[proposalId].hasVoted[voter], "User has not voted");
        return _proposals[proposalId].voteChoice[voter];
    }
}