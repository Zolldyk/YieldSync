/**
 * @fileoverview Vault operations for deposits and withdrawals
 * @author YieldSync Team
 * @description Handles all vault-related operations with proper validation and error handling
 */

import { contractManager, getUserTokenBalance, getUserVaultShares, getUserAssetValue } from './contracts.js';
import { walletManager, toWei, formatEther } from './wallet.js';
import { APP_CONFIG, ERROR_MESSAGES, SUCCESS_MESSAGES } from './config.js';
import { showNotification, showLoading, updateUserData } from './app.js';

// ============ Vault Operations Class ============
class VaultManager {
    constructor() {
        this.isProcessing = false;
        this.lastUpdateTime = 0;
    }

    /**
     * @notice Deposit assets into the yield vault
     * @param {string} amount - Amount to deposit in ether
     * @returns {Promise<boolean>} Success status
     */
    async deposit(amount) {
        // Prevent multiple simultaneous deposits
        if (this.isProcessing) {
            showNotification('Another transaction is in progress', 'info');
            return false;
        }

        try {
            this.isProcessing = true;
            showLoading('deposit', true);

            // Validate inputs
            const validation = await this.validateDepositInputs(amount);
            if (!validation.isValid) {
                showNotification(validation.error, 'error');
                return false;
            }

            const amountWei = toWei(amount);
            const userAccount = walletManager.userAccount;

            // Step 1: Check and handle token allowance
            const allowanceResult = await this.handleTokenAllowance(amountWei);
            if (!allowanceResult) {
                return false;
            }

            // Step 2: Estimate gas for deposit
            const estimatedGas = await contractManager.estimateGas(
                'vault', 
                'deposit', 
                [amountWei],
                { from: userAccount }
            );

            // Step 3: Execute deposit transaction
            showNotification('Executing deposit transaction...', 'info');
            
            const txResult = await contractManager.executeTransaction(
                'vault',
                'deposit',
                [amountWei],
                { 
                    from: userAccount,
                    gas: estimatedGas
                }
            );

            // Step 4: Handle successful transaction
            if (txResult && txResult.transactionHash) {
                showNotification(SUCCESS_MESSAGES.DEPOSIT_SUCCESS, 'success');
                
                // Log transaction details
                console.log('Deposit successful:', {
                    amount: amount,
                    txHash: txResult.transactionHash,
                    gasUsed: txResult.gasUsed
                });

                // Update UI data
                await this.scheduleDataUpdate();
                
                return true;
            } else {
                throw new Error('Transaction failed - no transaction hash received');
            }

        } catch (error) {
            console.error('Deposit failed:', error);
            this.handleTransactionError(error, 'deposit');
            return false;

        } finally {
            this.isProcessing = false;
            showLoading('deposit', false);
        }
    }

    /**
     * @notice Withdraw assets from the yield vault
     * @param {string} shares - Amount of shares to withdraw
     * @returns {Promise<boolean>} Success status
     */
    async withdraw(shares) {
        // Prevent multiple simultaneous withdrawals
        if (this.isProcessing) {
            showNotification('Another transaction is in progress', 'info');
            return false;
        }

        try {
            this.isProcessing = true;
            showLoading('withdraw', true);

            // Validate inputs
            const validation = await this.validateWithdrawInputs(shares);
            if (!validation.isValid) {
                showNotification(validation.error, 'error');
                return false;
            }

            const sharesWei = toWei(shares);
            const userAccount = walletManager.userAccount;

            // Step 1: Estimate gas for withdrawal
            const estimatedGas = await contractManager.estimateGas(
                'vault',
                'withdraw',
                [sharesWei],
                { from: userAccount }
            );

            // Step 2: Execute withdrawal transaction
            showNotification('Executing withdrawal transaction...', 'info');
            
            const txResult = await contractManager.executeTransaction(
                'vault',
                'withdraw',
                [sharesWei],
                {
                    from: userAccount,
                    gas: estimatedGas
                }
            );

            // Step 3: Handle successful transaction
            if (txResult && txResult.transactionHash) {
                showNotification(SUCCESS_MESSAGES.WITHDRAWAL_SUCCESS, 'success');
                
                // Log transaction details
                console.log('Withdrawal successful:', {
                    shares: shares,
                    txHash: txResult.transactionHash,
                    gasUsed: txResult.gasUsed
                });

                // Update UI data
                await this.scheduleDataUpdate();
                
                return true;
            } else {
                throw new Error('Transaction failed - no transaction hash received');
            }

        } catch (error) {
            console.error('Withdrawal failed:', error);
            this.handleTransactionError(error, 'withdraw');
            return false;

        } finally {
            this.isProcessing = false;
            showLoading('withdraw', false);
        }
    }

    /**
     * @notice Emergency withdrawal (no fees)
     * @param {string} shares - Amount of shares to withdraw
     * @returns {Promise<boolean>} Success status
     */
    async emergencyWithdraw(shares) {
        try {
            showNotification('Executing emergency withdrawal...', 'info');
            
            const sharesWei = toWei(shares);
            const userAccount = walletManager.userAccount;

            const txResult = await contractManager.executeTransaction(
                'vault',
                'emergencyWithdraw',
                [sharesWei],
                { from: userAccount }
            );

            if (txResult && txResult.transactionHash) {
                showNotification('Emergency withdrawal completed!', 'success');
                await this.scheduleDataUpdate();
                return true;
            }

            return false;

        } catch (error) {
            console.error('Emergency withdrawal failed:', error);
            showNotification('Emergency withdrawal failed: ' + error.message, 'error');
            return false;
        }
    }

    /**
     * @notice Validate deposit inputs
     * @param {string} amount - Deposit amount
     * @returns {Promise<object>} Validation result
     */
    async validateDepositInputs(amount) {
        try {
            // Check if contracts are ready
            if (!contractManager.isReady()) {
                return { isValid: false, error: ERROR_MESSAGES.CONTRACT_NOT_INITIALIZED };
            }

            // Check if wallet is connected
            if (!walletManager.isReady()) {
                return { isValid: false, error: ERROR_MESSAGES.WALLET_NOT_CONNECTED };
            }

            // Validate amount format
            if (!amount || isNaN(amount) || parseFloat(amount) <= 0) {
                return { isValid: false, error: ERROR_MESSAGES.INVALID_AMOUNT };
            }

            // Check minimum deposit amount
            if (parseFloat(amount) < parseFloat(APP_CONFIG.MIN_DEPOSIT_AMOUNT)) {
                return { 
                    isValid: false, 
                    error: `Minimum deposit amount is ${APP_CONFIG.MIN_DEPOSIT_AMOUNT} BDAG` 
                };
            }

            // Check user balance
            const userBalance = await getUserTokenBalance(walletManager.userAccount);
            if (parseFloat(amount) > parseFloat(userBalance)) {
                return { isValid: false, error: ERROR_MESSAGES.WALLET_INSUFFICIENT_FUNDS };
            }

            // Check vault deposit cap (if implemented)
            const maxDeposit = await this.getMaxDepositAmount();
            if (maxDeposit && parseFloat(amount) > parseFloat(maxDeposit)) {
                return { 
                    isValid: false, 
                    error: `Maximum deposit amount is ${maxDeposit} BDAG` 
                };
            }

            return { isValid: true };

        } catch (error) {
            console.error('Deposit validation failed:', error);
            return { isValid: false, error: 'Validation failed: ' + error.message };
        }
    }

    /**
     * @notice Validate withdrawal inputs
     * @param {string} shares - Shares amount
     * @returns {Promise<object>} Validation result
     */
    async validateWithdrawInputs(shares) {
        try {
            // Check if contracts are ready
            if (!contractManager.isReady()) {
                return { isValid: false, error: ERROR_MESSAGES.CONTRACT_NOT_INITIALIZED };
            }

            // Check if wallet is connected
            if (!walletManager.isReady()) {
                return { isValid: false, error: ERROR_MESSAGES.WALLET_NOT_CONNECTED };
            }

            // Validate shares format
            if (!shares || isNaN(shares) || parseFloat(shares) <= 0) {
                return { isValid: false, error: 'Please enter a valid share amount' };
            }

            // Check user shares balance
            const userShares = await getUserVaultShares(walletManager.userAccount);
            if (parseFloat(shares) > parseFloat(userShares)) {
                return { 
                    isValid: false, 
                    error: `Insufficient shares. You have ${userShares} shares available` 
                };
            }

            return { isValid: true };

        } catch (error) {
            console.error('Withdrawal validation failed:', error);
            return { isValid: false, error: 'Validation failed: ' + error.message };
        }
    }

    /**
     * @notice Handle token allowance for deposits
     * @param {string} amountWei - Amount in wei
     * @returns {Promise<boolean>} Success status
     */
    async handleTokenAllowance(amountWei) {
        try {
            const userAccount = walletManager.userAccount;
            const vaultAddress = await contractManager.getContract('vault').getAddress();

            // Check current allowance
            const currentAllowance = await contractManager.executeCall(
                'token',
                'allowance',
                [userAccount, vaultAddress]
            );

            // If allowance is sufficient, return true
            if (BigInt(currentAllowance) >= BigInt(amountWei)) {
                return true;
            }

            // Request approval
            showNotification('Approving tokens for deposit...', 'info');
            
            const approvalTx = await contractManager.executeTransaction(
                'token',
                'approve',
                [vaultAddress, amountWei],
                { from: userAccount }
            );

            if (approvalTx && approvalTx.transactionHash) {
                showNotification(SUCCESS_MESSAGES.APPROVAL_SUCCESS, 'success');
                return true;
            } else {
                throw new Error('Approval transaction failed');
            }

        } catch (error) {
            console.error('Token approval failed:', error);
            this.handleTransactionError(error, 'approval');
            return false;
        }
    }

    /**
     * @notice Get maximum deposit amount allowed
     * @returns {Promise<string|null>} Maximum deposit amount or null if unlimited
     */
    async getMaxDepositAmount() {
        try {
            // This would call a vault method if implemented
            // const maxDeposit = await contractManager.executeCall('vault', 'getMaxDeposit', []);
            // return formatEther(maxDeposit);
            
            // For now, return null (unlimited)
            return null;

        } catch (error) {
            console.error('Failed to get max deposit amount:', error);
            return null;
        }
    }

    /**
     * @notice Preview deposit to show expected shares
     * @param {string} amount - Deposit amount in ether
     * @returns {Promise<string>} Expected shares
     */
    async previewDeposit(amount) {
        try {
            if (!amount || parseFloat(amount) <= 0) {
                return '0';
            }

            const amountWei = toWei(amount);
            const shares = await contractManager.executeCall('vault', 'convertToShares', [amountWei]);
            return formatEther(shares);

        } catch (error) {
            console.error('Failed to preview deposit:', error);
            return '0';
        }
    }

    /**
     * @notice Preview withdrawal to show expected assets
     * @param {string} shares - Shares amount in ether
     * @returns {Promise<string>} Expected asset amount
     */
    async previewWithdraw(shares) {
        try {
            if (!shares || parseFloat(shares) <= 0) {
                return '0';
            }

            const sharesWei = toWei(shares);
            const assets = await contractManager.executeCall('vault', 'convertToAssets', [sharesWei]);
            return formatEther(assets);

        } catch (error) {
            console.error('Failed to preview withdrawal:', error);
            return '0';
        }
    }

    /**
     * @notice Calculate withdrawal fee
     * @param {string} amount - Withdrawal amount in ether
     * @returns {Promise<string>} Fee amount
     */
    async calculateWithdrawalFee(amount) {
        try {
            if (!amount || parseFloat(amount) <= 0) {
                return '0';
            }

            // Get current fee from fee optimizer
            const feeOptimizer = contractManager.getContract('feeOptimizer');
            if (feeOptimizer) {
                const amountWei = toWei(amount);
                const feeWei = await contractManager.executeCall('feeOptimizer', 'calculateFee', [amountWei]);
                return formatEther(feeWei);
            }

            // Default fee calculation (0.5%)
            const defaultFeeRate = 0.005;
            return (parseFloat(amount) * defaultFeeRate).toString();

        } catch (error) {
            console.error('Failed to calculate withdrawal fee:', error);
            return '0';
        }
    }

    /**
     * @notice Get vault statistics
     * @returns {Promise<object>} Vault statistics
     */
    async getVaultStats() {
        try {
            const stats = {};

            // Get total assets in vault
            const totalAssets = await contractManager.executeCall('vault', 'totalAssets', []);
            stats.totalAssets = formatEther(totalAssets);

            // Get exchange rate
            const exchangeRate = await contractManager.executeCall('vault', 'getExchangeRate', []);
            stats.exchangeRate = formatEther(exchangeRate);

            // Get total supply of shares
            const totalSupply = await contractManager.executeCall('vault', 'totalSupply', []);
            stats.totalSupply = formatEther(totalSupply);

            // Calculate APY (simplified - would need more complex calculation in production)
            stats.currentAPY = await this.calculateCurrentAPY();

            return stats;

        } catch (error) {
            console.error('Failed to get vault stats:', error);
            return {
                totalAssets: '0',
                exchangeRate: '1',
                totalSupply: '0',
                currentAPY: '0'
            };
        }
    }

    /**
     * @notice Calculate current APY (simplified calculation)
     * @returns {Promise<string>} Current APY percentage
     */
    async calculateCurrentAPY() {
        try {
            // This is a simplified calculation
            // In production, this would involve more complex calculations
            // based on historical performance and current yields
            
            // Get best pool APY as baseline
            const bestPool = await contractManager.executeCall('aggregator', 'getBestPool', []);
            if (bestPool && bestPool[1]) {
                // Convert from basis points to percentage
                const apyBasisPoints = bestPool[1];
                const apyPercentage = parseFloat(apyBasisPoints) / 100;
                return apyPercentage.toFixed(2);
            }

            return '12.5'; // Default APY

        } catch (error) {
            console.error('Failed to calculate APY:', error);
            return '0';
        }
    }

    /**
     * @notice Handle transaction errors with user-friendly messages
     * @param {Error} error - Transaction error
     * @param {string} operation - Operation type (deposit, withdraw, etc.)
     */
    handleTransactionError(error, operation) {
        let errorMessage = `${operation} failed: `;

        if (error.message.includes('User denied')) {
            errorMessage += 'Transaction was cancelled by user';
        } else if (error.message.includes('insufficient funds')) {
            errorMessage += 'Insufficient funds for transaction';
        } else if (error.message.includes('gas')) {
            errorMessage += 'Transaction failed due to gas issues';
        } else if (error.message.includes('slippage')) {
            errorMessage += 'Transaction failed due to price slippage';
        } else if (error.message.includes('allowance')) {
            errorMessage += 'Token allowance insufficient';
        } else {
            errorMessage += error.message || 'Unknown error occurred';
        }

        showNotification(errorMessage, 'error');
    }

    /**
     * @notice Schedule a delayed UI data update
     */
    async scheduleDataUpdate() {
        // Prevent too frequent updates
        const now = Date.now();
        if (now - this.lastUpdateTime < 2000) { // 2 second minimum between updates
            return;
        }

        this.lastUpdateTime = now;

        // Update immediately and then schedule periodic updates
        setTimeout(async () => {
            if (typeof updateUserData === 'function') {
                await updateUserData();
            }
        }, 1000); // 1 second delay to allow blockchain state to update
    }

    /**
     * @notice Set maximum deposit amount in UI
     */
    async setMaxDeposit() {
        try {
            const userBalance = await getUserTokenBalance(walletManager.userAccount);
            const depositInput = document.getElementById('depositAmount');
            
            if (depositInput && userBalance) {
                // Leave a small buffer for gas fees
                const maxAmount = Math.max(0, parseFloat(userBalance) - 0.001);
                depositInput.value = maxAmount.toFixed(6);
                
                // Trigger input event to update preview
                depositInput.dispatchEvent(new Event('input'));
            }

        } catch (error) {
            console.error('Failed to set max deposit:', error);
        }
    }

    /**
     * @notice Set maximum withdrawal amount in UI
     */
    async setMaxWithdraw() {
        try {
            const userShares = await getUserVaultShares(walletManager.userAccount);
            const withdrawInput = document.getElementById('withdrawAmount');
            
            if (withdrawInput && userShares) {
                withdrawInput.value = parseFloat(userShares).toFixed(6);
                
                // Trigger input event to update preview
                withdrawInput.dispatchEvent(new Event('input'));
            }

        } catch (error) {
            console.error('Failed to set max withdrawal:', error);
        }
    }

    /**
     * @notice Get user's portfolio summary
     * @param {string} userAddress - User's wallet address
     * @returns {Promise<object>} Portfolio summary
     */
    async getUserPortfolio(userAddress) {
        try {
            const portfolio = {};

            // Get current balances
            portfolio.tokenBalance = await getUserTokenBalance(userAddress);
            portfolio.vaultShares = await getUserVaultShares(userAddress);
            portfolio.currentValue = await getUserAssetValue(userAddress);

            // Calculate total deposited (this would need to be tracked in contract or off-chain)
            // For now, we'll use a placeholder calculation
            portfolio.totalDeposited = portfolio.currentValue; // Simplified

            // Calculate total earned
            const deposited = parseFloat(portfolio.totalDeposited);
            const current = parseFloat(portfolio.currentValue);
            portfolio.totalEarned = Math.max(0, current - deposited).toFixed(6);

            // Calculate user's personal APY (simplified)
            if (deposited > 0) {
                const earnedPercentage = ((current - deposited) / deposited) * 100;
                portfolio.userAPY = earnedPercentage.toFixed(2);
            } else {
                portfolio.userAPY = '0';
            }

            return portfolio;

        } catch (error) {
            console.error('Failed to get user portfolio:', error);
            return {
                tokenBalance: '0',
                vaultShares: '0',
                currentValue: '0',
                totalDeposited: '0',
                totalEarned: '0',
                userAPY: '0'
            };
        }
    }

    /**
     * @notice Check if vault is in emergency mode
     * @returns {Promise<boolean>} Emergency mode status
     */
    async isEmergencyMode() {
        try {
            // This would check a contract state if implemented
            // const emergencyMode = await contractManager.executeCall('vault', 'emergencyMode', []);
            // return emergencyMode;
            
            return false; // Default to false

        } catch (error) {
            console.error('Failed to check emergency mode:', error);
            return false;
        }
    }

    /**
     * @notice Get vault health metrics
     * @returns {Promise<object>} Health metrics
     */
    async getVaultHealth() {
        try {
            const health = {};

            // Get total value locked
            const stats = await this.getVaultStats();
            health.tvl = stats.totalAssets;

            // Get liquidity ratio (simplified)
            health.liquidityRatio = '85'; // Placeholder

            // Get utilization rate
            health.utilizationRate = '75'; // Placeholder

            // Overall health score (simplified calculation)
            const liquidity = parseFloat(health.liquidityRatio);
            const utilization = parseFloat(health.utilizationRate);
            
            if (liquidity > 80 && utilization < 90) {
                health.status = 'Healthy';
                health.score = 95;
            } else if (liquidity > 60 && utilization < 95) {
                health.status = 'Good';
                health.score = 75;
            } else {
                health.status = 'Caution';
                health.score = 50;
            }

            return health;

        } catch (error) {
            console.error('Failed to get vault health:', error);
            return {
                tvl: '0',
                liquidityRatio: '0',
                utilizationRate: '0',
                status: 'Unknown',
                score: 0
            };
        }
    }
}

// ============ Export Vault Manager Instance ============
export const vaultManager = new VaultManager();

// ============ Utility Functions ============

/**
 * @notice Format APY for display
 * @param {string} apy - APY in basis points or percentage
 * @returns {string} Formatted APY
 */
export function formatAPY(apy) {
    const apyNum = parseFloat(apy);
    if (apyNum === 0) return '0%';
    if (apyNum < 0.01) return '< 0.01%';
    return `${apyNum.toFixed(2)}%`;
}

/**
 * @notice Format currency amounts for display
 * @param {string} amount - Amount to format
 * @param {number} decimals - Number of decimal places
 * @returns {string} Formatted amount
 */
export function formatCurrency(amount, decimals = 6) {
    const num = parseFloat(amount);
    if (num === 0) return '0';
    if (num < Math.pow(10, -decimals)) return `< ${Math.pow(10, -decimals)}`;
    
    return num.toFixed(decimals);
}

/**
 * @notice Calculate percentage change
 * @param {string} oldValue - Previous value
 * @param {string} newValue - Current value
 * @returns {string} Percentage change
 */
export function calculatePercentageChange(oldValue, newValue) {
    const old = parseFloat(oldValue);
    const current = parseFloat(newValue);
    
    if (old === 0) return '0';
    
    const change = ((current - old) / old) * 100;
    return change.toFixed(2);
}

/**
 * @notice Validate amount input
 * @param {string} amount - Amount to validate
 * @param {string} maxAmount - Maximum allowed amount
 * @returns {object} Validation result
 */
export function validateAmountInput(amount, maxAmount = null) {
    if (!amount || amount.trim() === '') {
        return { isValid: false, error: 'Amount is required' };
    }

    if (isNaN(amount)) {
        return { isValid: false, error: 'Please enter a valid number' };
    }

    const num = parseFloat(amount);
    
    if (num <= 0) {
        return { isValid: false, error: 'Amount must be greater than 0' };
    }

    if (maxAmount && num > parseFloat(maxAmount)) {
        return { isValid: false, error: `Amount exceeds maximum of ${maxAmount}` };
    }

    // Check decimal places
    const decimalPlaces = (amount.split('.')[1] || '').length;
    if (decimalPlaces > APP_CONFIG.MAX_DECIMAL_PLACES) {
        return { 
            isValid: false, 
            error: `Maximum ${APP_CONFIG.MAX_DECIMAL_PLACES} decimal places allowed` 
        };
    }

    return { isValid: true };
}

// ============ Export Functions ============
export {
    formatAPY,
    formatCurrency,
    calculatePercentageChange,
    validateAmountInput
};

// ============ Export Default ============
export default vaultManager;