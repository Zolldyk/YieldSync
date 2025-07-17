/**
 * @fileoverview Configuration file for YieldSync DApp
 * @author YieldSync Team
 * @description Contains all contract addresses, network configuration, and constants
 */

// ============ Contract Addresses ============
// Updated with actual deployed addresses from BlockDAG Primordial Testnet
export const CONTRACTS = {
    // Mock BDAG Token (ERC20) - Deployed address
    MOCK_BDAG: '0x9589a024a960db2B63367a1e8bF659cBBa3215FD',
    
    // Core Protocol Contracts
    YIELD_VAULT: '0xE63cE0E709eB6E7f345133C681Ba177df603e804',
    YIELD_AGGREGATOR: '0xCB30C36cfaAa32b059138E302281dB4B8e50eD8c',
    FEE_OPTIMIZER: '0x90aF6FD2d47144a72B1e1D482C4208006Dba4f29',
    GOVERNANCE_TOKEN: '0x7412634B3189546549898000929A72600EF52b82',
    
    // Oracle and Pool Contracts
    MOCK_ORACLE: '0x4f910ef3996d7c4763efa2fef15265e8b918cd0b',
    MOCK_POOL_1: '0xAeAf07d2FcB5F7cB3d96A97FD872E1C12D455D38', // AMM Pool
    MOCK_POOL_2: '0x52BeC0b8025401e2ce84E1289C7dDCF8f290c474', // Lending Pool
    MOCK_POOL_3: '0x4469DDb94Ea2F5faF18F69e6ABb0E9E823ddf5Ca', // Staking Pool
};

// ============ BlockDAG Network Configuration ============
export const BLOCKDAG_CONFIG = {
    // Primordial Testnet Configuration
    chainId: '0x413', // 1043 in hexadecimal
    chainName: 'BlockDAG Primordial Testnet',
    nativeCurrency: {
        name: 'BDAG',
        symbol: 'BDAG',
        decimals: 18
    },
    rpcUrls: ['https://test-rpc.primordial.bdagscan.com'],
    blockExplorerUrls: ['https://primordial.bdagscan.com/']
};

// ============ Application Constants ============
export const APP_CONFIG = {
    // Application metadata
    APP_NAME: 'YieldSync',
    APP_VERSION: '1.0.0',
    APP_DESCRIPTION: 'Decentralized Yield Aggregator on BlockDAG',
    
    // UI Configuration
    UPDATE_INTERVAL: 10000, // 10 seconds for UI updates
    NOTIFICATION_TIMEOUT: 5000, // 5 seconds for notifications
    
    // Transaction Configuration
    DEFAULT_GAS_LIMIT: 300000,
    MAX_GAS_PRICE: '100000000000', // 100 gwei in wei
    SLIPPAGE_TOLERANCE: 50, // 0.5% in basis points
    
    // Pool refresh intervals
    POOL_DATA_REFRESH: 30000, // 30 seconds
    PRICE_REFRESH: 15000, // 15 seconds
    
    // Validation limits
    MIN_DEPOSIT_AMOUNT: '0.001', // Minimum deposit in BDAG
    MAX_DECIMAL_PLACES: 6,
    
    // Governance settings
    MIN_PROPOSAL_TOKENS: '1000', // Minimum tokens needed to create proposal
    VOTING_PERIOD_DAYS: 7,
    
    // Analytics
    ENABLE_ANALYTICS: false, // Set to true in production
    ANALYTICS_ID: '', // Add your analytics ID
};

// ============ Error Messages ============
export const ERROR_MESSAGES = {
    // Wallet errors
    WALLET_NOT_CONNECTED: 'Please connect your wallet first',
    WALLET_WRONG_NETWORK: 'Please switch to BlockDAG Primordial Testnet',
    WALLET_REJECTION: 'Transaction was rejected by user',
    WALLET_INSUFFICIENT_FUNDS: 'Insufficient balance for this transaction',
    
    // Contract errors
    CONTRACT_NOT_INITIALIZED: 'Smart contracts are not initialized',
    CONTRACT_INTERACTION_FAILED: 'Failed to interact with smart contract',
    
    // Input validation errors
    INVALID_AMOUNT: 'Please enter a valid amount',
    AMOUNT_TOO_LOW: 'Amount is below minimum threshold',
    AMOUNT_TOO_HIGH: 'Amount exceeds maximum limit',
    
    // Transaction errors
    TRANSACTION_FAILED: 'Transaction failed',
    INSUFFICIENT_ALLOWANCE: 'Insufficient token allowance',
    SLIPPAGE_TOO_HIGH: 'Slippage tolerance exceeded',
    
    // General errors
    NETWORK_ERROR: 'Network error - please try again',
    UNKNOWN_ERROR: 'An unknown error occurred',
};

// ============ Success Messages ============
export const SUCCESS_MESSAGES = {
    WALLET_CONNECTED: 'Wallet connected successfully!',
    TRANSACTION_SENT: 'Transaction sent! Waiting for confirmation...',
    DEPOSIT_SUCCESS: 'Deposit completed successfully!',
    WITHDRAWAL_SUCCESS: 'Withdrawal completed successfully!',
    APPROVAL_SUCCESS: 'Token approval completed!',
    PROPOSAL_CREATED: 'Governance proposal created successfully!',
    VOTE_CAST: 'Vote cast successfully!',
    YIELD_SHARED: 'Yield shared successfully! Governance tokens earned.',
};

// ============ API Endpoints ============
export const API_ENDPOINTS = {
    // BlockDAG endpoints
    BLOCKDAG_RPC: 'https://test-rpc.primordial.bdagscan.com',
    BLOCKDAG_EXPLORER: 'https://primordial.bdagscan.com',
    BLOCKDAG_FAUCET: 'https://primordial.bdagscan.com/faucet',
    
    // Price feeds (external APIs)
    COINGECKO_API: 'https://api.coingecko.com/api/v3',
    COINMARKETCAP_API: 'https://pro-api.coinmarketcap.com/v1',
    
    // Analytics (optional)
    ANALYTICS_ENDPOINT: '',
};

// ============ Feature Flags ============
export const FEATURES = {
    // Core features
    DEPOSITS_ENABLED: true,
    WITHDRAWALS_ENABLED: true,
    GOVERNANCE_ENABLED: true,
    
    // Advanced features
    AUTO_COMPOUND_ENABLED: true,
    YIELD_SHARING_ENABLED: true,
    MULTI_POOL_ENABLED: true,
    
    // Beta features
    FLASH_LOANS_ENABLED: false,
    CROSS_CHAIN_ENABLED: false,
    
    // UI features
    DARK_MODE_ENABLED: true,
    ADVANCED_CHARTS_ENABLED: false,
    NOTIFICATIONS_ENABLED: true,
};

// ============ Pool Configuration ============
export const POOL_CONFIG = {
    // Pool types and their characteristics
    POOL_TYPES: {
        AMM: {
            name: 'AMM Pool',
            description: 'Automated Market Maker',
            riskLevel: 'Medium',
            baseAPY: 8.5,
        },
        LENDING: {
            name: 'Lending Pool',
            description: 'Lending Protocol',
            riskLevel: 'Low',
            baseAPY: 12.3,
        },
        STAKING: {
            name: 'Staking Pool',
            description: 'Staking Rewards',
            riskLevel: 'High',
            baseAPY: 15.7,
        }
    },
    
    // Pool allocation limits
    MAX_POOL_ALLOCATION: 50, // Maximum 50% allocation to single pool
    MIN_POOL_ALLOCATION: 1,  // Minimum 1% allocation
    REBALANCE_THRESHOLD: 100, // 1% APY difference triggers rebalance
    
    // Pool update intervals
    APY_UPDATE_INTERVAL: 300000, // 5 minutes
    ALLOCATION_UPDATE_INTERVAL: 60000, // 1 minute
};

// ============ Utility Functions for Configuration ============

/**
 * @notice Get contract address by name
 * @param {string} contractName - Name of the contract
 * @returns {string} Contract address
 */
export function getContractAddress(contractName) {
    const address = CONTRACTS[contractName];
    if (!address) {
        throw new Error(`Contract address not found: ${contractName}`);
    }
    return address;
}

/**
 * @notice Check if a feature is enabled
 * @param {string} featureName - Name of the feature
 * @returns {boolean} Whether feature is enabled
 */
export function isFeatureEnabled(featureName) {
    return FEATURES[featureName] || false;
}

/**
 * @notice Get current environment configuration
 * @returns {string} Environment name
 */
export function getEnvironment() {
    // Detect environment based on hostname
    const hostname = window.location.hostname;
    
    if (hostname === 'localhost' || hostname === '127.0.0.1') {
        return 'development';
    } else if (hostname.includes('testnet') || hostname.includes('staging')) {
        return 'testnet';
    } else {
        return 'production';
    }
}

/**
 * @notice Get configuration for current environment
 * @returns {object} Environment-specific configuration
 */
export function getEnvConfig() {
    const env = getEnvironment();
    
    return {
        development: {
            debug: true,
            apiTimeout: 10000,
            enableMockData: true,
        },
        testnet: {
            debug: true,
            apiTimeout: 15000,
            enableMockData: false,
        },
        production: {
            debug: false,
            apiTimeout: 5000,
            enableMockData: false,
        }
    }[env];
}

// ============ Contract ABI Paths ============
export const ABI_PATHS = {
    YIELD_VAULT: './contracts/abis/YieldVault.json',
    GOVERNANCE_TOKEN: './contracts/abis/GovernanceToken.json',
    MOCK_TOKEN: './contracts/abis/MockToken.json',
    MOCK_ORACLE: './contracts/abis/MockOracle.json',
    YIELD_AGGREGATOR: './contracts/abis/YieldAggregator.json',
    FEE_OPTIMIZER: './contracts/abis/FeeOptimizer.json',
};

// ============ Export Default Configuration ============
export default {
    CONTRACTS,
    BLOCKDAG_CONFIG,
    APP_CONFIG,
    ERROR_MESSAGES,
    SUCCESS_MESSAGES,
    API_ENDPOINTS,
    FEATURES,
    POOL_CONFIG,
    ABI_PATHS,
    
    // Utility functions
    getContractAddress,
    isFeatureEnabled,
    getEnvironment,
    getEnvConfig,
};