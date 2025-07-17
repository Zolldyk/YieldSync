/**
 * @fileoverview Governance operations and yield sharing
 * @author YieldSync Team
 * @description Handles governance token interactions, proposals, and voting
 */

import { contractManager } from './contracts.js';
import { walletManager, toWei, formatEther } from './wallet.js';
import { APP_CONFIG, SUCCESS_MESSAGES, ERROR_MESSAGES } from './config.js';
import { showNotification, showLoading } from './app.js';

// ============ Governance Manager Class ============
class GovernanceManager {
    constructor() {
        this.isProcessing = false;
        this.proposals = new Map();
        this.userVotes = new Map();
    }

    /**
     * @notice Share yield with community pool to earn governance tokens
     * @param {string} amount - Amount of vault shares to share
     * @returns {Promise<boolean>} Success status
     */
    async shareYield(amount) {
        if (this.isProcessing) {
            showNotification('Another transaction is in progress', 'info');
            return false;
        }

        try {
            this.isProcessing = true;
            showLoading('shareYield', true);

            // Validate inputs
            const validation = await this.validateYieldShareInputs(amount);
            if (!validation.isValid) {
                showNotification(validation.error, 'error');
                return false;
            }

            const amountWei = toWei(amount);
            const userAccount = walletManager.userAccount;

            // Step 1: Check vault share allowance for governance contract
            const allowanceResult = await this.handleVaultShareAllowance(amountWei);
            if (!allowanceResult) {
                return false;
            }

            // Step 2: Execute yield sharing transaction
            showNotification('Sharing yield with community...', 'info');
            
            const txResult = await contractManager.executeTransaction(
                'governance',
                'shareYield',
                [amountWei],
                { from: userAccount }
            );

            if (txResult && txResult.transactionHash) {
                showNotification(SUCCESS_MESSAGES.YIELD_SHARED, 'success');
                
                // Log transaction details
                console.log('Yield sharing successful:', {
                    amount: amount,
                    txHash: txResult.transactionHash,
                    gasUsed: txResult.gasUsed
                });

                return true;
            } else {
                throw new Error('Transaction failed - no transaction hash received');
            }

        } catch (error) {
            console.error('Yield sharing failed:', error);
            this.handleTransactionError(error, 'yield sharing');
            return false;

        } finally {
            this.isProcessing = false;
            showLoading('shareYield', false);
        }
    }

    /**
     * @notice Create a new governance proposal
     * @param {string} description - Proposal description
     * @returns {Promise<boolean>} Success status
     */
    async createProposal(description) {
        if (this.isProcessing) {
            showNotification('Another transaction is in progress', 'info');
            return false;
        }

        try {
            this.isProcessing = true;
            showLoading('createProposal', true);

            // Validate inputs
            const validation = await this.validateProposalInputs(description);
            if (!validation.isValid) {
                showNotification(validation.error, 'error');
                return false;
            }

            const userAccount = walletManager.userAccount;

            // Execute proposal creation
            showNotification('Creating governance proposal...', 'info');
            
            const txResult = await contractManager.executeTransaction(
                'governance',
                'createProposal',
                [description],
                { from: userAccount }
            );

            if (txResult && txResult.transactionHash) {
                showNotification(SUCCESS_MESSAGES.PROPOSAL_CREATED, 'success');
                
                // Log transaction details
                console.log('Proposal created successfully:', {
                    description: description,
                    txHash: txResult.transactionHash
                });

                return true;
            } else {
                throw new Error('Transaction failed - no transaction hash received');
            }

        } catch (error) {
            console.error('Proposal creation failed:', error);
            this.handleTransactionError(error, 'proposal creation');
            return false;

        } finally {
            this.isProcessing = false;
            showLoading('createProposal', false);
        }
    }

    /**
     * @notice Vote on a governance proposal
     * @param {number} proposalId - ID of the proposal
     * @param {boolean} support - Whether to vote in favor
     * @returns {Promise<boolean>} Success status
     */
    async voteOnProposal(proposalId, support) {
        try {
            showLoading('vote', true);

            // Check if user has already voted
            if (this.userVotes.has(proposalId)) {
                showNotification('You have already voted on this proposal', 'error');
                return false;
            }

            // Check voting power
            const votingPower = await this.getVotingPower(walletManager.userAccount);
            if (parseFloat(votingPower) <= 0) {
                showNotification('You need governance tokens to vote', 'error');
                return false;
            }

            const userAccount = walletManager.userAccount;

            // Execute vote
            showNotification(`Casting ${support ? 'YES' : 'NO'} vote...`, 'info');
            
            const txResult = await contractManager.executeTransaction(
                'governance',
                'vote',
                [proposalId, support],
                { from: userAccount }
            );

            if (txResult && txResult.transactionHash) {
                showNotification(SUCCESS_MESSAGES.VOTE_CAST, 'success');
                
                // Track user vote
                this.userVotes.set(proposalId, support);
                
                return true;
            } else {
                throw new Error('Voting transaction failed');
            }

        } catch (error) {
            console.error('Voting failed:', error);
            this.handleTransactionError(error, 'voting');
            return false;

        } finally {
            showLoading('vote', false);
        }
    }

    /**
     * @notice Validate yield sharing inputs
     * @param {string} amount - Amount to share
     * @returns {Promise<object>} Validation result
     */
    async validateYieldShareInputs(amount) {
        try {
            // Check if contracts are ready
            if (!contractManager.isReady()) {
                return { isValid: false, error: ERROR_MESSAGES.CONTRACT_NOT_INITIALIZED };
            }

            // Validate amount format
            if (!amount || isNaN(amount) || parseFloat(amount) <= 0) {
                return { isValid: false, error: 'Please enter a valid amount to share' };
            }

            // Check user has sufficient vault shares
            const userShares = await contractManager.executeCall('vault', 'balanceOf', [walletManager.userAccount]);
            const userSharesEth = formatEther(userShares);
            
            if (parseFloat(amount) > parseFloat(userSharesEth)) {
                return { 
                    isValid: false, 
                    error: `Insufficient vault shares. You have ${userSharesEth} shares available` 
                };
            }

            return { isValid: true };

        } catch (error) {
            console.error('Yield share validation failed:', error);
            return { isValid: false, error: 'Validation failed: ' + error.message };
        }
    }

    /**
     * @notice Validate proposal inputs
     * @param {string} description - Proposal description
     * @returns {Promise<object>} Validation result
     */
    async validateProposalInputs(description) {
        try {
            // Check if contracts are ready
            if (!contractManager.isReady()) {
                return { isValid: false, error: ERROR_MESSAGES.CONTRACT_NOT_INITIALIZED };
            }

            // Validate description
            if (!description || description.trim().length === 0) {
                return { isValid: false, error: 'Please enter a proposal description' };
            }

            if (description.length < 10) {
                return { isValid: false, error: 'Proposal description must be at least 10 characters' };
            }

            if (description.length > 500) {
                return { isValid: false, error: 'Proposal description must be less than 500 characters' };
            }

            // Check user has sufficient governance tokens to create proposal
            const votingPower = await this.getVotingPower(walletManager.userAccount);
            const minTokens = parseFloat(APP_CONFIG.MIN_PROPOSAL_TOKENS);
            
            if (parseFloat(votingPower) < minTokens) {
                return { 
                    isValid: false, 
                    error: `You need at least ${minTokens} governance tokens to create a proposal` 
                };
            }

            return { isValid: true };

        } catch (error) {
            console.error('Proposal validation failed:', error);
            return { isValid: false, error: 'Validation failed: ' + error.message };
        }
    }

    /**
     * @notice Handle vault share allowance for governance contract
     * @param {string} amountWei - Amount in wei
     * @returns {Promise<boolean>} Success status
     */
    async handleVaultShareAllowance(amountWei) {
        try {
            const userAccount = walletManager.userAccount;
            const governanceAddress = contractManager.getContract('governance').options.address;

            // Check current allowance
            const currentAllowance = await contractManager.executeCall(
                'vault',
                'allowance',
                [userAccount, governanceAddress]
            );

            // If allowance is sufficient, return true
            if (walletManager.web3.utils.toBN(currentAllowance).gte(walletManager.web3.utils.toBN(amountWei))) {
                return true;
            }

            // Request approval
            showNotification('Approving vault shares for yield sharing...', 'info');
            
            const approvalTx = await contractManager.executeTransaction(
                'vault',
                'approve',
                [governanceAddress, amountWei],
                { from: userAccount }
            );

            if (approvalTx && approvalTx.transactionHash) {
                showNotification('Vault shares approved successfully!', 'success');
                return true;
            } else {
                throw new Error('Approval transaction failed');
            }

        } catch (error) {
            console.error('Vault share approval failed:', error);
            this.handleTransactionError(error, 'approval');
            return false;
        }
    }

    /**
     * @notice Get user's voting power
     * @param {string} userAddress - User's wallet address
     * @returns {Promise<string>} Voting power in tokens
     */
    async getVotingPower(userAddress) {
        try {
            const votingPower = await contractManager.executeCall('governance', 'getVotingPower', [userAddress]);
            return formatEther(votingPower);
        } catch (error) {
            console.error('Failed to get voting power:', error);
            return '0';
        }
    }

    /**
     * @notice Get governance token balance
     * @param {string} userAddress - User's wallet address
     * @returns {Promise<string>} Token balance
     */
    async getGovernanceTokenBalance(userAddress) {
        try {
            const balance = await contractManager.executeCall('governance', 'balanceOf', [userAddress]);
            return formatEther(balance);
        } catch (error) {
            console.error('Failed to get governance token balance:', error);
            return '0';
        }
    }

    /**
     * @notice Get community yield pool balance
     * @returns {Promise<string>} Pool balance
     */
    async getCommunityYieldPool() {
        try {
            const balance = await contractManager.executeCall('governance', 'getCommunityYieldPool', []);
            return formatEther(balance);
        } catch (error) {
            console.error('Failed to get community yield pool:', error);
            return '0';
        }
    }

    /**
     * @notice Preview yield sharing rewards
     * @param {string} amount - Amount to share
     * @param {string} userAddress - User's address
     * @returns {Promise<string>} Expected governance tokens
     */
    async previewYieldShare(amount, userAddress) {
        try {
            if (!amount || parseFloat(amount) <= 0) {
                return '0';
            }

            const amountWei = toWei(amount);
            const tokens = await contractManager.executeCall('governance', 'previewYieldShare', [amountWei, userAddress]);
            return formatEther(tokens);
        } catch (error) {
            console.error('Failed to preview yield share:', error);
            return '0';
        }
    }

    /**
     * @notice Get active proposals
     * @returns {Promise<Array>} Array of active proposals
     */
    async getActiveProposals() {
        try {
            const proposalIds = await contractManager.executeCall('governance', 'getActiveProposals', []);
            const proposals = [];

            for (const id of proposalIds) {
                const proposal = await this.getProposal(id);
                if (proposal) {
                    proposals.push(proposal);
                }
            }

            return proposals;
        } catch (error) {
            console.error('Failed to get active proposals:', error);
            return [];
        }
    }

    /**
     * @notice Get proposal details
     * @param {number} proposalId - Proposal ID
     * @returns {Promise<object|null>} Proposal details
     */
    async getProposal(proposalId) {
        try {
            const proposal = await contractManager.executeCall('governance', 'getProposal', [proposalId]);
            
            return {
                id: proposalId,
                proposer: proposal[0],
                description: proposal[1],
                startTime: proposal[2],
                endTime: proposal[3],
                forVotes: formatEther(proposal[4]),
                againstVotes: formatEther(proposal[5]),
                totalVotes: formatEther(proposal[6]),
                executed: proposal[7],
                canceled: proposal[8]
            };
        } catch (error) {
            console.error('Failed to get proposal:', error);
            return null;
        }
    }

    /**
     * @notice Get proposal state
     * @param {number} proposalId - Proposal ID
     * @returns {Promise<string>} Proposal state
     */
    async getProposalState(proposalId) {
        try {
            const state = await contractManager.executeCall('governance', 'getProposalState', [proposalId]);
            const states = ['Pending', 'Active', 'Passed', 'Failed', 'Executed', 'Canceled'];
            return states[state] || 'Unknown';
        } catch (error) {
            console.error('Failed to get proposal state:', error);
            return 'Unknown';
        }
    }

    /**
     * @notice Check if user has voted on proposal
     * @param {number} proposalId - Proposal ID
     * @param {string} userAddress - User's address
     * @returns {Promise<object>} Vote information
     */
    async getUserVote(proposalId, userAddress) {
        try {
            const vote = await contractManager.executeCall('governance', 'getUserVote', [proposalId, userAddress]);
            return {
                hasVoted: vote[0],
                voteChoice: vote[1]
            };
        } catch (error) {
            console.error('Failed to get user vote:', error);
            return { hasVoted: false, voteChoice: false };
        }
    }

    /**
     * @notice Handle transaction errors
     * @param {Error} error - Transaction error
     * @param {string} operation - Operation type
     */
    handleTransactionError(error, operation) {
        let errorMessage = `${operation} failed: `;

        if (error.message.includes('User denied')) {
            errorMessage += 'Transaction was cancelled by user';
        } else if (error.message.includes('insufficient funds')) {
            errorMessage += 'Insufficient funds for transaction';
        } else if (error.message.includes('allowance')) {
            errorMessage += 'Insufficient allowance';
        } else {
            errorMessage += error.message || 'Unknown error occurred';
        }

        showNotification(errorMessage, 'error');
    }

    /**
     * @notice Format governance data for display
     * @param {object} data - Raw governance data
     * @returns {object} Formatted data
     */
    formatGovernanceData(data) {
        return {
            votingPower: this.formatTokenAmount(data.votingPower),
            communityPool: this.formatTokenAmount(data.communityPool),
            totalTokens: this.formatTokenAmount(data.totalTokens)
        };
    }

    /**
     * @notice Format token amounts for display
     * @param {string} amount - Token amount
     * @returns {string} Formatted amount
     */
    formatTokenAmount(amount) {
        const num = parseFloat(amount);
        if (num === 0) return '0';
        if (num < 0.001) return '< 0.001';
        if (num < 1000) return num.toFixed(3);
        if (num < 1000000) return (num / 1000).toFixed(2) + 'K';
        return (num / 1000000).toFixed(2) + 'M';
    }

    /**
     * @notice Calculate voting participation rate
     * @param {string} totalVotes - Total votes cast
     * @param {string} totalSupply - Total token supply
     * @returns {string} Participation rate percentage
     */
    calculateParticipationRate(totalVotes, totalSupply) {
        const votes = parseFloat(totalVotes);
        const supply = parseFloat(totalSupply);
        
        if (supply === 0) return '0';
        
        const rate = (votes / supply) * 100;
        return rate.toFixed(2);
    }

    /**
     * @notice Get governance statistics
     * @returns {Promise<object>} Governance statistics
     */
    async getGovernanceStats() {
        try {
            const stats = {};

            // Get total supply
            stats.totalSupply = await contractManager.executeCall('governance', 'totalSupply', []);
            
            // Get total tokens distributed
            stats.totalDistributed = await contractManager.executeCall('governance', 'getTotalTokensDistributed', []);
            
            // Get total yield collected
            stats.totalYieldCollected = await contractManager.executeCall('governance', 'getTotalYieldCollected', []);
            
            // Get community pool balance
            stats.communityPool = await this.getCommunityYieldPool();
            
            // Calculate participation metrics
            stats.participationRate = '12.5'; // Would be calculated from actual data
            stats.averageVotingPower = '2.3K'; // Would be calculated from actual data

            // Format for display
            return {
                totalSupply: this.formatTokenAmount(formatEther(stats.totalSupply)),
                totalDistributed: this.formatTokenAmount(formatEther(stats.totalDistributed)),
                totalYieldCollected: this.formatTokenAmount(stats.totalYieldCollected),
                communityPool: this.formatTokenAmount(stats.communityPool),
                participationRate: stats.participationRate + '%',
                averageVotingPower: stats.averageVotingPower
            };

        } catch (error) {
            console.error('Failed to get governance stats:', error);
            return {
                totalSupply: '0',
                totalDistributed: '0',
                totalYieldCollected: '0',
                communityPool: '0',
                participationRate: '0%',
                averageVotingPower: '0'
            };
        }
    }

    /**
     * @notice Get user's governance summary
     * @param {string} userAddress - User's wallet address
     * @returns {Promise<object>} User governance summary
     */
    async getUserGovernanceSummary(userAddress) {
        try {
            const summary = {};

            // Get governance token balance
            summary.tokenBalance = await this.getGovernanceTokenBalance(userAddress);
            
            // Get voting power
            summary.votingPower = await this.getVotingPower(userAddress);
            
            // Get yield sharing info
            summary.yieldSharingInfo = await contractManager.executeCall('governance', 'getYieldSharingInfo', [userAddress]);
            
            // Calculate user statistics
            summary.totalShared = formatEther(summary.yieldSharingInfo.totalYieldShared || '0');
            summary.tokensEarned = formatEther(summary.yieldSharingInfo.tokensEarned || '0');
            summary.shareCount = summary.yieldSharingInfo.shareCount || 0;
            
            return {
                tokenBalance: this.formatTokenAmount(summary.tokenBalance),
                votingPower: this.formatTokenAmount(summary.votingPower),
                totalShared: this.formatTokenAmount(summary.totalShared),
                tokensEarned: this.formatTokenAmount(summary.tokensEarned),
                shareCount: summary.shareCount.toString()
            };

        } catch (error) {
            console.error('Failed to get user governance summary:', error);
            return {
                tokenBalance: '0',
                votingPower: '0',
                totalShared: '0',
                tokensEarned: '0',
                shareCount: '0'
            };
        }
    }

    /**
     * @notice Check if yield sharing is active
     * @returns {Promise<boolean>} Whether yield sharing is active
     */
    async isYieldSharingActive() {
        try {
            const isActive = await contractManager.executeCall('governance', 'isYieldSharingActive', []);
            return isActive;
        } catch (error) {
            console.error('Failed to check yield sharing status:', error);
            return false;
        }
    }

    /**
     * @notice Get yield sharing rate
     * @returns {Promise<string>} Current yield sharing rate
     */
    async getYieldSharingRate() {
        try {
            const rate = await contractManager.executeCall('governance', 'getYieldSharingRate', []);
            return rate.toString();
        } catch (error) {
            console.error('Failed to get yield sharing rate:', error);
            return '1000'; // Default rate
        }
    }

    /**
     * @notice Get top yield sharers
     * @param {number} count - Number of top sharers to return
     * @returns {Promise<Array>} Array of top yield sharers
     */
    async getTopYieldSharers(count = 10) {
        try {
            const topSharers = await contractManager.executeCall('governance', 'getTopYieldSharers', [count]);
            return topSharers;
        } catch (error) {
            console.error('Failed to get top yield sharers:', error);
            return { sharers: [], amounts: [] };
        }
    }

    /**
     * @notice Calculate yield sharing incentives
     * @param {string} amount - Amount to share
     * @param {string} userAddress - User's address
     * @returns {Promise<object>} Incentive breakdown
     */
    async calculateYieldIncentives(amount, userAddress) {
        try {
            if (!amount || parseFloat(amount) <= 0) {
                return { baseTokens: '0', bonusTokens: '0', totalTokens: '0' };
            }

            // Get base token calculation
            const baseTokens = await this.previewYieldShare(amount, userAddress);
            
            // Calculate bonus (simplified - would be more complex in production)
            const userInfo = await contractManager.executeCall('governance', 'getYieldSharingInfo', [userAddress]);
            const shareCount = userInfo.shareCount || 0;
            
            let bonusMultiplier = 1;
            if (shareCount >= 10) {
                bonusMultiplier = 1.1; // 10% bonus for frequent sharers
            } else if (shareCount >= 5) {
                bonusMultiplier = 1.05; // 5% bonus
            }
            
            const totalTokens = parseFloat(baseTokens) * bonusMultiplier;
            const bonusTokens = totalTokens - parseFloat(baseTokens);

            return {
                baseTokens: baseTokens,
                bonusTokens: bonusTokens.toFixed(6),
                totalTokens: totalTokens.toFixed(6),
                bonusMultiplier: bonusMultiplier
            };

        } catch (error) {
            console.error('Failed to calculate yield incentives:', error);
            return { baseTokens: '0', bonusTokens: '0', totalTokens: '0' };
        }
    }

    /**
     * @notice Get proposal voting deadline
     * @param {object} proposal - Proposal object
     * @returns {string} Time remaining for voting
     */
    getVotingTimeRemaining(proposal) {
        try {
            const now = Math.floor(Date.now() / 1000);
            const endTime = parseInt(proposal.endTime);
            
            if (now >= endTime) {
                return 'Voting ended';
            }
            
            const remainingSeconds = endTime - now;
            const days = Math.floor(remainingSeconds / (24 * 60 * 60));
            const hours = Math.floor((remainingSeconds % (24 * 60 * 60)) / (60 * 60));
            const minutes = Math.floor((remainingSeconds % (60 * 60)) / 60);
            
            if (days > 0) {
                return `${days}d ${hours}h remaining`;
            } else if (hours > 0) {
                return `${hours}h ${minutes}m remaining`;
            } else {
                return `${minutes}m remaining`;
            }
            
        } catch (error) {
            console.error('Error calculating voting time:', error);
            return 'Unknown';
        }
    }

    /**
     * @notice Get proposal quorum status
     * @param {object} proposal - Proposal object
     * @returns {object} Quorum information
     */
    async getProposalQuorum(proposal) {
        try {
            // Get total supply for quorum calculation
            const totalSupply = await contractManager.executeCall('governance', 'totalSupply', []);
            const config = await contractManager.executeCall('governance', 'getGovernanceConfig', []);
            
            // Calculate required quorum (usually 4% of total supply)
            const quorumThreshold = config.quorumThreshold || 400; // 4% in basis points
            const requiredQuorum = (parseFloat(formatEther(totalSupply)) * quorumThreshold) / 10000;
            
            const currentParticipation = parseFloat(proposal.totalVotes);
            const quorumMet = currentParticipation >= requiredQuorum;
            const participationRate = (currentParticipation / parseFloat(formatEther(totalSupply))) * 100;
            
            return {
                required: requiredQuorum.toFixed(2),
                current: currentParticipation.toFixed(2),
                met: quorumMet,
                participationRate: participationRate.toFixed(2)
            };
            
        } catch (error) {
            console.error('Error calculating quorum:', error);
            return {
                required: '0',
                current: '0',
                met: false,
                participationRate: '0'
            };
        }
    }

    /**
     * @notice Reset processing state (for error recovery)
     */
    resetProcessingState() {
        this.isProcessing = false;
    }
}

// ============ Export Governance Manager Instance ============
export const governanceManager = new GovernanceManager();

// ============ Utility Functions ============

/**
 * @notice Format proposal description for display
 * @param {string} description - Raw description
 * @param {number} maxLength - Maximum length
 * @returns {string} Formatted description
 */
export function formatProposalDescription(description, maxLength = 100) {
    if (!description) return '';
    
    if (description.length <= maxLength) {
        return description;
    }
    
    return description.substring(0, maxLength - 3) + '...';
}

/**
 * @notice Get proposal status color
 * @param {string} status - Proposal status
 * @returns {string} CSS class for status color
 */
export function getProposalStatusColor(status) {
    const colorMap = {
        'Pending': 'status-pending',
        'Active': 'status-active',
        'Passed': 'status-passed',
        'Failed': 'status-failed',
        'Executed': 'status-executed',
        'Canceled': 'status-canceled'
    };
    
    return colorMap[status] || 'status-unknown';
}

/**
 * @notice Validate proposal description
 * @param {string} description - Proposal description
 * @returns {object} Validation result
 */
export function validateProposalDescription(description) {
    if (!description || description.trim().length === 0) {
        return { isValid: false, error: 'Description is required' };
    }
    
    if (description.length < 10) {
        return { isValid: false, error: 'Description must be at least 10 characters' };
    }
    
    if (description.length > 500) {
        return { isValid: false, error: 'Description must be less than 500 characters' };
    }
    
    // Check for inappropriate content (basic check)
    const inappropriateWords = ['spam', 'scam', 'hack'];
    const lowerDescription = description.toLowerCase();
    
    for (const word of inappropriateWords) {
        if (lowerDescription.includes(word)) {
            return { isValid: false, error: 'Description contains inappropriate content' };
        }
    }
    
    return { isValid: true };
}

/**
 * @notice Calculate vote percentage
 * @param {string} votes - Number of votes
 * @param {string} totalVotes - Total votes cast
 * @returns {string} Percentage
 */
export function calculateVotePercentage(votes, totalVotes) {
    const voteNum = parseFloat(votes);
    const totalNum = parseFloat(totalVotes);
    
    if (totalNum === 0) return '0';
    
    const percentage = (voteNum / totalNum) * 100;
    return percentage.toFixed(1);
}

/**
 * @notice Format time duration
 * @param {number} seconds - Duration in seconds
 * @returns {string} Formatted duration
 */
export function formatDuration(seconds) {
    const days = Math.floor(seconds / (24 * 60 * 60));
    const hours = Math.floor((seconds % (24 * 60 * 60)) / (60 * 60));
    const minutes = Math.floor((seconds % (60 * 60)) / 60);
    
    if (days > 0) {
        return `${days}d ${hours}h`;
    } else if (hours > 0) {
        return `${hours}h ${minutes}m`;
    } else {
        return `${minutes}m`;
    }
}

// ============ Export Functions ============
export {
    formatProposalDescription,
    getProposalStatusColor,
    validateProposalDescription,
    calculateVotePercentage,
    formatDuration
};

// ============ Export Default ============
export default governanceManager;