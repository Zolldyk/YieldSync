/**
 * @fileoverview Wallet connection and management functionality
 * @author YieldSync Team
 * @description Handles MetaMask connection, network switching, and wallet state management
 */

import { BLOCKDAG_CONFIG, ERROR_MESSAGES, SUCCESS_MESSAGES } from './config.js';
import { showNotification } from './app.js';

// ============ Wallet State Management ============
class WalletManager {
    constructor() {
        this.web3 = null;
        this.userAccount = null;
        this.isConnected = false;
        this.chainId = null;
        this.balance = '0';
        
        // Event listeners array for cleanup
        this.eventListeners = [];
    }

    /**
     * @notice Initialize wallet connection and event listeners
     * @returns {Promise<boolean>} Success status
     */
    async initialize() {
        try {
            // Check if MetaMask is installed
            if (!this.isMetaMaskInstalled()) {
                showNotification('Please install MetaMask to use YieldSync', 'error');
                return false;
            }

            // Initialize ethers provider
            this.web3 = new ethers.BrowserProvider(window.ethereum);

            // Check if already connected
            const accounts = await ethereum.request({ method: 'eth_accounts' });
            if (accounts.length > 0) {
                await this.handleConnection(accounts[0]);
            }

            // Setup event listeners
            this.setupEventListeners();

            return true;

        } catch (error) {
            console.error('Failed to initialize wallet:', error);
            showNotification('Failed to initialize wallet connection', 'error');
            return false;
        }
    }

    /**
     * @notice Check if MetaMask is installed
     * @returns {boolean} Whether MetaMask is available
     */
    isMetaMaskInstalled() {
        return typeof window.ethereum !== 'undefined' && window.ethereum.isMetaMask;
    }

    /**
     * @notice Connect to MetaMask wallet
     * @returns {Promise<boolean>} Success status
     */
    async connect() {
        try {
            if (!this.isMetaMaskInstalled()) {
                showNotification('Please install MetaMask to connect your wallet', 'error');
                return false;
            }

            // Request account access
            const accounts = await ethereum.request({ 
                method: 'eth_requestAccounts' 
            });

            if (accounts.length === 0) {
                showNotification('No accounts found. Please unlock MetaMask.', 'error');
                return false;
            }

            // Handle successful connection
            await this.handleConnection(accounts[0]);
            
            return true;

        } catch (error) {
            console.error('Failed to connect wallet:', error);
            
            // Handle specific error types
            if (error.code === 4001) {
                showNotification('Connection request was rejected', 'error');
            } else if (error.code === -32002) {
                showNotification('Connection request is already pending', 'info');
            } else {
                showNotification('Failed to connect wallet', 'error');
            }
            
            return false;
        }
    }

    /**
     * @notice Handle successful wallet connection
     * @param {string} account - Connected account address
     */
    async handleConnection(account) {
        try {
            this.userAccount = account;
            this.isConnected = true;

            // Get current chain ID
            const network = await this.web3.getNetwork();
            this.chainId = `0x${network.chainId.toString(16)}`;

            // Switch to BlockDAG network if needed
            await this.switchToBlockDAG();

            // Update balance
            await this.updateBalance();

            // Update UI
            this.updateWalletUI();

            // Notify success
            showNotification(SUCCESS_MESSAGES.WALLET_CONNECTED, 'success');

            // Dispatch custom event for other components
            window.dispatchEvent(new CustomEvent('walletConnected', {
                detail: { account: this.userAccount }
            }));

        } catch (error) {
            console.error('Error handling wallet connection:', error);
            showNotification('Error completing wallet connection', 'error');
        }
    }

    /**
     * @notice Switch to BlockDAG Primordial Testnet
     * @returns {Promise<boolean>} Success status
     */
    async switchToBlockDAG() {
        try {
            // Check if already on correct network
            if (this.chainId === BLOCKDAG_CONFIG.chainId) {
                return true;
            }

            // Try to switch to BlockDAG network
            await ethereum.request({
                method: 'wallet_switchEthereumChain',
                params: [{ chainId: BLOCKDAG_CONFIG.chainId }],
            });

            this.chainId = BLOCKDAG_CONFIG.chainId;
            return true;

        } catch (switchError) {
            // Network doesn't exist, try to add it
            if (switchError.code === 4902) {
                return await this.addBlockDAGNetwork();
            } else {
                console.error('Failed to switch network:', switchError);
                showNotification('Failed to switch to BlockDAG network', 'error');
                return false;
            }
        }
    }

    /**
     * @notice Add BlockDAG network to MetaMask
     * @returns {Promise<boolean>} Success status
     */
    async addBlockDAGNetwork() {
        try {
            await ethereum.request({
                method: 'wallet_addEthereumChain',
                params: [BLOCKDAG_CONFIG],
            });

            this.chainId = BLOCKDAG_CONFIG.chainId;
            showNotification('BlockDAG network added successfully!', 'success');
            return true;

        } catch (addError) {
            console.error('Failed to add network:', addError);
            showNotification('Failed to add BlockDAG network', 'error');
            return false;
        }
    }

    /**
     * @notice Update user's BDAG balance
     */
    async updateBalance() {
        try {
            if (!this.userAccount || !this.web3) {
                return;
            }

            const balanceWei = await this.web3.getBalance(this.userAccount);
            this.balance = ethers.formatEther(balanceWei);

            // Update UI if balance element exists
            const balanceElement = document.getElementById('walletBalance');
            if (balanceElement) {
                balanceElement.textContent = `${this.formatBalance(this.balance)} BDAG`;
            }

        } catch (error) {
            console.error('Failed to update balance:', error);
        }
    }

    /**
     * @notice Format balance for display
     * @param {string} balance - Balance in ether
     * @returns {string} Formatted balance
     */
    formatBalance(balance) {
        const num = parseFloat(balance);
        if (num === 0) return '0';
        if (num < 0.001) return '< 0.001';
        if (num < 1) return num.toFixed(6);
        if (num < 1000) return num.toFixed(4);
        return num.toFixed(2);
    }

    /**
     * @notice Update wallet UI elements
     */
    updateWalletUI() {
        const elements = {
            walletAddress: document.getElementById('walletAddress'),
            connectWallet: document.getElementById('connectWallet'),
            userBalance: document.getElementById('userBalance'),
        };

        if (this.isConnected && this.userAccount) {
            // Update address display
            if (elements.walletAddress) {
                elements.walletAddress.textContent = 
                    `${this.userAccount.slice(0, 6)}...${this.userAccount.slice(-4)}`;
            }

            // Update connect button
            if (elements.connectWallet) {
                elements.connectWallet.textContent = 'Connected';
                elements.connectWallet.disabled = true;
                elements.connectWallet.classList.add('button-connected');
            }

            // Update balance displays
            if (elements.userBalance) {
                elements.userBalance.textContent = `${this.formatBalance(this.balance)} BDAG`;
            }

        } else {
            // Reset UI for disconnected state
            if (elements.walletAddress) {
                elements.walletAddress.textContent = 'Not Connected';
            }

            if (elements.connectWallet) {
                elements.connectWallet.textContent = 'Connect Wallet';
                elements.connectWallet.disabled = false;
                elements.connectWallet.classList.remove('button-connected');
            }

            if (elements.userBalance) {
                elements.userBalance.textContent = '0 BDAG';
            }
        }
    }

    /**
     * @notice Setup MetaMask event listeners
     */
    setupEventListeners() {
        // Account change listener
        const accountsChangedHandler = (accounts) => {
            this.handleAccountsChanged(accounts);
        };

        // Chain change listener
        const chainChangedHandler = (chainId) => {
            this.handleChainChanged(chainId);
        };

        // Add event listeners
        ethereum.on('accountsChanged', accountsChangedHandler);
        ethereum.on('chainChanged', chainChangedHandler);

        // Store listeners for cleanup
        this.eventListeners = [
            { event: 'accountsChanged', handler: accountsChangedHandler },
            { event: 'chainChanged', handler: chainChangedHandler }
        ];
    }

    /**
     * @notice Handle account changes from MetaMask
     * @param {Array} accounts - Array of account addresses
     */
    handleAccountsChanged(accounts) {
        if (accounts.length === 0) {
            // User disconnected wallet
            this.disconnect();
            showNotification('Wallet disconnected', 'info');
        } else if (accounts[0] !== this.userAccount) {
            // User switched to different account
            this.handleConnection(accounts[0]);
            showNotification('Account switched', 'info');
        }
    }

    /**
     * @notice Handle network/chain changes from MetaMask
     * @param {string} chainId - New chain ID
     */
    handleChainChanged(chainId) {
        this.chainId = chainId;

        // Check if on correct network
        if (chainId !== BLOCKDAG_CONFIG.chainId) {
            showNotification(ERROR_MESSAGES.WALLET_WRONG_NETWORK, 'error');
        } else {
            showNotification('Connected to BlockDAG network', 'success');
        }

        // Refresh page to ensure proper state
        setTimeout(() => {
            window.location.reload();
        }, 1000);
    }

    /**
     * @notice Disconnect wallet
     */
    disconnect() {
        this.userAccount = null;
        this.isConnected = false;
        this.balance = '0';
        this.updateWalletUI();

        // Dispatch disconnect event
        window.dispatchEvent(new CustomEvent('walletDisconnected'));
    }

    /**
     * @notice Check if wallet is connected and on correct network
     * @returns {boolean} Whether wallet is properly connected
     */
    isReady() {
        return this.isConnected && 
               this.userAccount && 
               this.chainId === BLOCKDAG_CONFIG.chainId;
    }

    /**
     * @notice Get current wallet state
     * @returns {object} Wallet state object
     */
    getState() {
        return {
            isConnected: this.isConnected,
            account: this.userAccount,
            chainId: this.chainId,
            balance: this.balance,
            web3: this.web3
        };
    }

    /**
     * @notice Request user signature for message
     * @param {string} message - Message to sign
     * @returns {Promise<string>} Signature
     */
    async signMessage(message) {
        try {
            if (!this.isReady()) {
                throw new Error(ERROR_MESSAGES.WALLET_NOT_CONNECTED);
            }

            const signature = await ethereum.request({
                method: 'personal_sign',
                params: [message, this.userAccount]
            });

            return signature;

        } catch (error) {
            console.error('Failed to sign message:', error);
            throw error;
        }
    }

    /**
     * @notice Send transaction with proper error handling
     * @param {object} transactionConfig - Transaction configuration
     * @returns {Promise<string>} Transaction hash
     */
    async sendTransaction(transactionConfig) {
        try {
            if (!this.isReady()) {
                throw new Error(ERROR_MESSAGES.WALLET_NOT_CONNECTED);
            }

            // Add from address if not specified
            if (!transactionConfig.from) {
                transactionConfig.from = this.userAccount;
            }

            const txHash = await ethereum.request({
                method: 'eth_sendTransaction',
                params: [transactionConfig]
            });

            return txHash;

        } catch (error) {
            console.error('Transaction failed:', error);
            
            // Handle common error types
            if (error.code === 4001) {
                throw new Error(ERROR_MESSAGES.WALLET_REJECTION);
            } else if (error.message.includes('insufficient funds')) {
                throw new Error(ERROR_MESSAGES.WALLET_INSUFFICIENT_FUNDS);
            } else {
                throw new Error(ERROR_MESSAGES.TRANSACTION_FAILED);
            }
        }
    }

    /**
     * @notice Clean up event listeners
     */
    cleanup() {
        this.eventListeners.forEach(({ event, handler }) => {
            if (ethereum && ethereum.removeListener) {
                ethereum.removeListener(event, handler);
            }
        });
        this.eventListeners = [];
    }
}

// ============ Export Wallet Manager Instance ============
export const walletManager = new WalletManager();

// ============ Utility Functions ============

/**
 * @notice Check if user has sufficient balance for transaction
 * @param {string} requiredAmount - Required amount in ether
 * @returns {boolean} Whether user has sufficient balance
 */
export function hasSufficientBalance(requiredAmount) {
    if (!walletManager.isReady()) {
        return false;
    }

    const required = parseFloat(requiredAmount);
    const available = parseFloat(walletManager.balance);
    
    return available >= required;
}

/**
 * @notice Format address for display
 * @param {string} address - Full address
 * @param {number} startChars - Characters to show at start
 * @param {number} endChars - Characters to show at end
 * @returns {string} Formatted address
 */
export function formatAddress(address, startChars = 6, endChars = 4) {
    if (!address) return '';
    if (address.length <= startChars + endChars) return address;
    
    return `${address.slice(0, startChars)}...${address.slice(-endChars)}`;
}

/**
 * @notice Convert wei to ether with proper formatting
 * @param {string} weiAmount - Amount in wei
 * @param {number} decimals - Number of decimal places
 * @returns {string} Formatted ether amount
 */
export function formatEther(weiAmount, decimals = 6) {
    if (!walletManager.web3) return '0';
    
    const ether = ethers.formatEther(weiAmount);
    const num = parseFloat(ether);
    
    if (num === 0) return '0';
    if (num < Math.pow(10, -decimals)) return `< ${Math.pow(10, -decimals)}`;
    
    return num.toFixed(decimals);
}

/**
 * @notice Convert ether to wei
 * @param {string} etherAmount - Amount in ether
 * @returns {string} Amount in wei
 */
export function toWei(etherAmount) {
    if (!walletManager.web3) return '0';
    return ethers.parseEther(etherAmount);
}

// ============ Export Default ============
export default walletManager;