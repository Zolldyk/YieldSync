/**
 * @fileoverview Smart contract interaction manager
 * @author YieldSync Team
 * @description Handles all smart contract interactions with proper error handling
 */

import { CONTRACTS, ABI_PATHS, ERROR_MESSAGES } from './config.js';
import { walletManager } from './wallet.js';
import { showNotification } from './app.js';

// ============ Contract Manager Class ============
class ContractManager {
    constructor() {
        this.contracts = {};
        this.abis = {};
        this.isInitialized = false;
    }

    /**
     * @notice Initialize all contract instances
     * @returns {Promise<boolean>} Success status
     */
    async initialize() {
        try {
            // Wait for wallet to be ready
            if (!walletManager.isReady()) {
                throw new Error('Wallet not ready');
            }

            // Load all ABIs
            await this.loadABIs();

            // Initialize contract instances
            await this.initializeContracts();

            this.isInitialized = true;
            console.log('Contracts initialized successfully');
            return true;

        } catch (error) {
            console.error('Failed to initialize contracts:', error);
            this.isInitialized = false;
            return false;
        }
    }

    /**
     * @notice Load contract ABIs from JSON files
     */
    async loadABIs() {
        try {
            // Load YieldVault ABI
            this.abis.vault = await this.loadABI(ABI_PATHS.YIELD_VAULT);
            
            // Load GovernanceToken ABI
            this.abis.governance = await this.loadABI(ABI_PATHS.GOVERNANCE_TOKEN);
            
            // Load MockToken ABI (for BDAG token)
            this.abis.token = await this.loadABI(ABI_PATHS.MOCK_TOKEN);
            
            // Load MockOracle ABI
            this.abis.oracle = await this.loadABI(ABI_PATHS.MOCK_ORACLE);
            
            // Load YieldAggregator ABI
            this.abis.aggregator = await this.loadABI(ABI_PATHS.YIELD_AGGREGATOR);
            
            // Load FeeOptimizer ABI
            this.abis.feeOptimizer = await this.loadABI(ABI_PATHS.FEE_OPTIMIZER);

        } catch (error) {
            console.error('Failed to load ABIs:', error);
            // Use fallback minimal ABIs if files not found
            this.useFallbackABIs();
        }
    }

    /**
     * @notice Load single ABI from JSON file
     * @param {string} path - Path to ABI file
     * @returns {Promise<Array>} Contract ABI
     */
    async loadABI(path) {
        try {
            const response = await fetch(path);
            if (!response.ok) {
                throw new Error(`Failed to fetch ABI: ${response.status}`);
            }
            const data = await response.json();
            return data.abi || data; // Handle both formats
        } catch (error) {
            console.warn(`Failed to load ABI from ${path}:`, error);
            return null;
        }
    }

    /**
     * @notice Use fallback minimal ABIs when files are not available
     */
    useFallbackABIs() {
        console.log('Using fallback minimal ABIs');
        
        // Minimal YieldVault ABI with essential functions
        this.abis.vault = [
            "function deposit(uint256 amount) external returns (uint256 shares)",
            "function withdraw(uint256 shares) external returns (uint256 amount)",
            "function balanceOf(address user) external view returns (uint256)",
            "function totalAssets() external view returns (uint256)",
            "function getExchangeRate() external view returns (uint256)",
            "function convertToShares(uint256 assets) external view returns (uint256)",
            "function convertToAssets(uint256 shares) external view returns (uint256)",
            "function getUserAssetBalance(address user) external view returns (uint256)",
            "function previewWithdraw(uint256 shares) external view returns (uint256)",
            "function approve(address spender, uint256 amount) external returns (bool)"
        ];

        // Minimal ERC20 ABI for token interactions
        this.abis.token = [
            "function balanceOf(address owner) external view returns (uint256)",
            "function approve(address spender, uint256 amount) external returns (bool)",
            "function allowance(address owner, address spender) external view returns (uint256)",
            "function transfer(address to, uint256 amount) external returns (bool)",
            "function decimals() external view returns (uint8)",
            "function symbol() external view returns (string)",
            "function name() external view returns (string)"
        ];

        // Minimal GovernanceToken ABI
        this.abis.governance = [
            "function shareYield(uint256 amount) external returns (uint256)",
            "function balanceOf(address user) external view returns (uint256)",
            "function getVotingPower(address user) external view returns (uint256)",
            "function createProposal(string calldata description) external returns (uint256)",
            "function vote(uint256 proposalId, bool support) external",
            "function getActiveProposals() external view returns (uint256[] memory)",
            "function getProposal(uint256 proposalId) external view returns (address, string memory, uint256, uint256, uint256, uint256, uint256, bool, bool)",
            "function getCommunityYieldPool() external view returns (uint256)",
            "function previewYieldShare(uint256 amount, address user) external view returns (uint256)"
        ];

        // Minimal Oracle ABI
        this.abis.oracle = [
            "function getPoolAPY(address poolAddress) external view returns (uint256)",
            "function getGasPrice() external view returns (uint256)",
            "function getNetworkCongestion() external view returns (uint256)",
            "function getActivePools() external view returns (address[] memory)"
        ];

        // Minimal Aggregator ABI
        this.abis.aggregator = [
            "function getBestPool() external view returns (address, uint256)",
            "function getPoolInfo(address poolAddress) external view returns (address, uint256, uint256, uint256, bool)",
            "function getActivePools() external view returns (address[] memory)",
            "function getTotalAllocated() external view returns (uint256)"
        ];

        // Minimal FeeOptimizer ABI
        this.abis.feeOptimizer = [
            "function getCurrentFee() external view returns (uint256)",
            "function calculateFee(uint256 amount) external view returns (uint256)",
            "function updateFee() external"
        ];
    }

    /**
     * @notice Initialize contract instances with ethers
     */
    async initializeContracts() {
        const provider = walletManager.web3;
        if (!provider) {
            throw new Error('Ethers provider not available');
        }

        try {
            const signer = await provider.getSigner();

            // Initialize YieldVault contract
            if (CONTRACTS.YIELD_VAULT && this.abis.vault) {
                this.contracts.vault = new ethers.Contract(
                    CONTRACTS.YIELD_VAULT,
                    this.abis.vault, 
                    signer
                );
            }

            // Initialize MockToken (BDAG) contract
            if (CONTRACTS.MOCK_BDAG && this.abis.token) {
                this.contracts.token = new ethers.Contract(
                    CONTRACTS.MOCK_BDAG,
                    this.abis.token, 
                    signer
                );
            }

            // Initialize GovernanceToken contract
            if (CONTRACTS.GOVERNANCE_TOKEN && this.abis.governance) {
                this.contracts.governance = new ethers.Contract(
                    CONTRACTS.GOVERNANCE_TOKEN,
                    this.abis.governance, 
                    signer
                );
            }

            // Initialize MockOracle contract
            if (CONTRACTS.MOCK_ORACLE && this.abis.oracle) {
                this.contracts.oracle = new ethers.Contract(
                    CONTRACTS.MOCK_ORACLE,
                    this.abis.oracle, 
                    signer
                );
            }

            // Initialize YieldAggregator contract
            if (CONTRACTS.YIELD_AGGREGATOR && this.abis.aggregator) {
                this.contracts.aggregator = new ethers.Contract(
                    CONTRACTS.YIELD_AGGREGATOR,
                    this.abis.aggregator, 
                    signer
                );
            }

            // Initialize FeeOptimizer contract
            if (CONTRACTS.FEE_OPTIMIZER && this.abis.feeOptimizer) {
                this.contracts.feeOptimizer = new ethers.Contract(
                    CONTRACTS.FEE_OPTIMIZER,
                    this.abis.feeOptimizer, 
                    signer
                );
            }

        } catch (error) {
            console.error('Error initializing contracts:', error);
            throw error;
        }
    }

    /**
     * @notice Get contract instance by name
     * @param {string} contractName - Name of the contract
     * @returns {object} Web3 contract instance
     */
    getContract(contractName) {
        if (!this.isInitialized) {
            throw new Error(ERROR_MESSAGES.CONTRACT_NOT_INITIALIZED);
        }

        const contract = this.contracts[contractName];
        if (!contract) {
            throw new Error(`Contract not found: ${contractName}`);
        }

        return contract;
    }

    /**
     * @notice Execute contract call with error handling
     * @param {string} contractName - Name of the contract
     * @param {string} methodName - Name of the method
     * @param {Array} params - Method parameters
     * @param {object} options - Transaction options
     * @returns {Promise<any>} Transaction result
     */
    async executeTransaction(contractName, methodName, params = [], options = {}) {
        try {
            if (!walletManager.isReady()) {
                throw new Error(ERROR_MESSAGES.WALLET_NOT_CONNECTED);
            }

            const contract = this.getContract(contractName);
            const method = contract[methodName];

            if (!method) {
                throw new Error(`Method ${methodName} not found on contract ${contractName}`);
            }

            // Set default transaction options
            const txOptions = {
                gasLimit: options.gas || 300000,
                ...options
            };

            // Execute transaction
            const result = await method(...params, txOptions);
            
            return result;

        } catch (error) {
            console.error(`Transaction failed for ${contractName}.${methodName}:`, error);
            throw this.handleContractError(error);
        }
    }

    /**
     * @notice Execute contract view call
     * @param {string} contractName - Name of the contract
     * @param {string} methodName - Name of the method
     * @param {Array} params - Method parameters
     * @returns {Promise<any>} Call result
     */
    async executeCall(contractName, methodName, params = []) {
        try {
            const contract = this.getContract(contractName);
            const method = contract[methodName];

            if (!method) {
                throw new Error(`Method ${methodName} not found on contract ${contractName}`);
            }

            const result = await method(...params);
            return result;

        } catch (error) {
            console.error(`Call failed for ${contractName}.${methodName}:`, error);
            throw this.handleContractError(error);
        }
    }

    /**
     * @notice Handle and format contract errors
     * @param {Error} error - Original error
     * @returns {Error} Formatted error
     */
    handleContractError(error) {
        // Check for specific error types
        if (error.message.includes('User denied')) {
            return new Error(ERROR_MESSAGES.WALLET_REJECTION);
        }
        
        if (error.message.includes('insufficient funds')) {
            return new Error(ERROR_MESSAGES.WALLET_INSUFFICIENT_FUNDS);
        }
        
        if (error.message.includes('execution reverted')) {
            // Extract revert reason if available
            const revertReason = this.extractRevertReason(error.message);
            return new Error(`Transaction reverted: ${revertReason || 'Unknown reason'}`);
        }
        
        if (error.message.includes('gas')) {
            return new Error('Transaction failed due to gas issues. Try increasing gas limit.');
        }

        // Return original error if no specific handling
        return error;
    }

    /**
     * @notice Extract revert reason from error message
     * @param {string} errorMessage - Full error message
     * @returns {string} Revert reason
     */
    extractRevertReason(errorMessage) {
        const revertMatch = errorMessage.match(/execution reverted: (.+)/);
        return revertMatch ? revertMatch[1] : null;
    }

    /**
     * @notice Estimate gas for transaction
     * @param {string} contractName - Name of the contract
     * @param {string} methodName - Name of the method
     * @param {Array} params - Method parameters
     * @param {object} options - Transaction options
     * @returns {Promise<number>} Estimated gas
     */
    async estimateGas(contractName, methodName, params = [], options = {}) {
        try {
            const contract = this.getContract(contractName);
            const method = contract[methodName];

            if (!method) {
                throw new Error(`Method ${methodName} not found on contract ${contractName}`);
            }

            const gasEstimate = await method.estimateGas(...params, options);
            
            // Add 20% buffer to gas estimate
            return Math.floor(Number(gasEstimate) * 1.2);

        } catch (error) {
            console.error(`Gas estimation failed for ${contractName}.${methodName}:`, error);
            // Return default gas limit if estimation fails
            return 300000;
        }
    }

    /**
     * @notice Check if contracts are properly initialized
     * @returns {boolean} Initialization status
     */
    isReady() {
        return this.isInitialized && 
               walletManager.isReady() && 
               Object.keys(this.contracts).length > 0;
    }

    /**
     * @notice Get all initialized contracts
     * @returns {object} Contract instances
     */
    getAllContracts() {
        return { ...this.contracts };
    }

    /**
     * @notice Reset contract manager
     */
    reset() {
        this.contracts = {};
        this.abis = {};
        this.isInitialized = false;
    }
}

// ============ Create Contract Manager Instance ============
export const contractManager = new ContractManager();

// ============ Specific Contract Interaction Functions ============

/**
 * @notice Get user token balance
 * @param {string} userAddress - User's wallet address
 * @returns {Promise<string>} Token balance in ether
 */
export async function getUserTokenBalance(userAddress) {
    try {
        const balance = await contractManager.executeCall('token', 'balanceOf', [userAddress]);
        return ethers.formatEther(balance);
    } catch (error) {
        console.error('Failed to get token balance:', error);
        return '0';
    }
}

/**
 * @notice Get user vault shares
 * @param {string} userAddress - User's wallet address
 * @returns {Promise<string>} Vault shares in ether
 */
export async function getUserVaultShares(userAddress) {
    try {
        const shares = await contractManager.executeCall('vault', 'balanceOf', [userAddress]);
        return ethers.formatEther(shares);
    } catch (error) {
        console.error('Failed to get vault shares:', error);
        return '0';
    }
}

/**
 * @notice Get user's asset value in vault
 * @param {string} userAddress - User's wallet address
 * @returns {Promise<string>} Asset value in ether
 */
export async function getUserAssetValue(userAddress) {
    try {
        const value = await contractManager.executeCall('vault', 'getUserAssetBalance', [userAddress]);
        return ethers.formatEther(value);
    } catch (error) {
        console.error('Failed to get user asset value:', error);
        return '0';
    }
}

/**
 * @notice Get current vault exchange rate
 * @returns {Promise<string>} Exchange rate
 */
export async function getVaultExchangeRate() {
    try {
        const rate = await contractManager.executeCall('vault', 'getExchangeRate', []);
        return ethers.formatEther(rate);
    } catch (error) {
        console.error('Failed to get exchange rate:', error);
        return '1';
    }
}

/**
 * @notice Get governance token balance
 * @param {string} userAddress - User's wallet address
 * @returns {Promise<string>} Governance token balance in ether
 */
export async function getGovernanceTokenBalance(userAddress) {
    try {
        const balance = await contractManager.executeCall('governance', 'balanceOf', [userAddress]);
        return ethers.formatEther(balance);
    } catch (error) {
        console.error('Failed to get governance token balance:', error);
        return '0';
    }
}

/**
 * @notice Get user's voting power
 * @param {string} userAddress - User's wallet address
 * @returns {Promise<string>} Voting power
 */
export async function getVotingPower(userAddress) {
    try {
        const power = await contractManager.executeCall('governance', 'getVotingPower', [userAddress]);
        return ethers.formatEther(power);
    } catch (error) {
        console.error('Failed to get voting power:', error);
        return '0';
    }
}

/**
 * @notice Get community yield pool balance
 * @returns {Promise<string>} Pool balance in ether
 */
export async function getCommunityYieldPool() {
    try {
        const balance = await contractManager.executeCall('governance', 'getCommunityYieldPool', []);
        return ethers.formatEther(balance);
    } catch (error) {
        console.error('Failed to get community yield pool:', error);
        return '0';
    }
}

/**
 * @notice Preview yield sharing rewards
 * @param {string} amount - Amount to share in ether
 * @param {string} userAddress - User's address
 * @returns {Promise<string>} Expected governance tokens
 */
export async function previewYieldShare(amount, userAddress) {
    try {
        const amountWei = ethers.parseEther(amount);
        const tokens = await contractManager.executeCall('governance', 'previewYieldShare', [amountWei, userAddress]);
        return ethers.formatEther(tokens);
    } catch (error) {
        console.error('Failed to preview yield share:', error);
        return '0';
    }
}

/**
 * @notice Get active pools from aggregator
 * @returns {Promise<Array>} Array of active pool addresses
 */
export async function getActivePools() {
    try {
        const pools = await contractManager.executeCall('aggregator', 'getActivePools', []);
        return pools;
    } catch (error) {
        console.error('Failed to get active pools:', error);
        return [];
    }
}

/**
 * @notice Get best performing pool
 * @returns {Promise<object>} Best pool info
 */
export async function getBestPool() {
    try {
        const [address, apy] = await contractManager.executeCall('aggregator', 'getBestPool', []);
        return {
            address,
            apy: apy.toString()
        };
    } catch (error) {
        console.error('Failed to get best pool:', error);
        return { address: '', apy: '0' };
    }
}

/**
 * @notice Get current fee from fee optimizer
 * @returns {Promise<string>} Current fee in basis points
 */
export async function getCurrentFee() {
    try {
        const fee = await contractManager.executeCall('feeOptimizer', 'getCurrentFee', []);
        return fee.toString();
    } catch (error) {
        console.error('Failed to get current fee:', error);
        return '50'; // Default 0.5%
    }
}

// ============ Export Contract Manager ============
export default contractManager;