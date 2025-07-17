/**
 * @fileoverview Main application controller
 * @author YieldSync Team
 * @description Coordinates all modules and handles UI interactions
 */

import { APP_CONFIG, FEATURES } from './config.js';
import { walletManager } from './wallet.js';
import { contractManager } from './contracts.js';
import { vaultManager } from './vault.js';

// ============ Application State ============
class AppManager {
    constructor() {
        this.isInitialized = false;
        this.updateInterval = null;
        this.notifications = new Map();
        this.currentTab = 'deposit';
    }

    /**
     * @notice Initialize the application
     */
    async initialize() {
        try {
            console.log('Initializing YieldSync DApp...');

            // Initialize wallet manager
            const walletInitialized = await walletManager.initialize();
            if (!walletInitialized) {
                throw new Error('Failed to initialize wallet manager');
            }

            // Setup event listeners
            this.setupEventListeners();

            // Setup periodic updates
            this.setupPeriodicUpdates();

            // Initialize UI
            this.initializeUI();

            this.isInitialized = true;
            console.log('YieldSync DApp initialized successfully');

        } catch (error) {
            console.error('Failed to initialize application:', error);
            this.showNotification('Failed to initialize application', 'error');
        }
    }

    /**
     * @notice Setup all event listeners
     */
    setupEventListeners() {
        // Wallet connection events
        window.addEventListener('walletConnected', this.handleWalletConnected.bind(this));
        window.addEventListener('walletDisconnected', this.handleWalletDisconnected.bind(this));

        // Connect wallet button
        const connectBtn = document.getElementById('connectWallet');
        if (connectBtn) {
            connectBtn.addEventListener('click', this.connectWallet.bind(this));
        }

        // Deposit tab events
        this.setupDepositEvents();

        // Withdraw tab events
        this.setupWithdrawEvents();

        // Governance tab events
        this.setupGovernanceEvents();

        // Tab switching events
        this.setupTabEvents();

        // Input validation events
        this.setupInputValidation();
    }

    /**
     * @notice Setup deposit-related event listeners
     */
    setupDepositEvents() {
        const depositBtn = document.getElementById('depositBtn');
        const depositAmount = document.getElementById('depositAmount');
        const maxDepositBtn = document.querySelector('[onclick="setMaxDeposit()"]');

        if (depositBtn) {
            depositBtn.addEventListener('click', this.handleDeposit.bind(this));
        }

        if (depositAmount) {
            depositAmount.addEventListener('input', this.updateDepositPreview.bind(this));
        }

        if (maxDepositBtn) {
            maxDepositBtn.addEventListener('click', this.setMaxDeposit.bind(this));
        }
    }

    /**
     * @notice Setup withdraw-related event listeners
     */
    setupWithdrawEvents() {
        const withdrawBtn = document.getElementById('withdrawBtn');
        const withdrawAmount = document.getElementById('withdrawAmount');
        const maxWithdrawBtn = document.querySelector('[onclick="setMaxWithdraw()"]');

        if (withdrawBtn) {
            withdrawBtn.addEventListener('click', this.handleWithdraw.bind(this));
        }

        if (withdrawAmount) {
            withdrawAmount.addEventListener('input', this.updateWithdrawPreview.bind(this));
        }

        if (maxWithdrawBtn) {
            maxWithdrawBtn.addEventListener('click', this.setMaxWithdraw.bind(this));
        }
    }

    /**
     * @notice Setup governance-related event listeners
     */
    setupGovernanceEvents() {
        const shareYieldBtn = document.getElementById('shareYieldBtn');
        const createProposalBtn = document.getElementById('createProposalBtn');
        const yieldShareAmount = document.getElementById('yieldShareAmount');

        if (shareYieldBtn) {
            shareYieldBtn.addEventListener('click', this.handleYieldShare.bind(this));
        }

        if (createProposalBtn) {
            createProposalBtn.addEventListener('click', this.handleCreateProposal.bind(this));
        }

        if (yieldShareAmount) {
            yieldShareAmount.addEventListener('input', this.updateYieldSharePreview.bind(this));
        }
    }

    /**
     * @notice Setup tab switching events
     */
    setupTabEvents() {
        const tabs = document.querySelectorAll('.tab');
        tabs.forEach(tab => {
            tab.addEventListener('click', (e) => {
                const tabName = e.target.textContent.toLowerCase().includes('deposit') ? 'deposit' :
                               e.target.textContent.toLowerCase().includes('withdraw') ? 'withdraw' :
                               e.target.textContent.toLowerCase().includes('governance') ? 'governance' : 'pools';
                this.showTab(tabName);
            });
        });
    }

    /**
     * @notice Setup input validation events
     */
    setupInputValidation() {
        const numberInputs = document.querySelectorAll('input[type="number"]');
        numberInputs.forEach(input => {
            input.addEventListener('blur', this.validateNumberInput.bind(this));
            input.addEventListener('input', this.formatNumberInput.bind(this));
        });
    }

    /**
     * @notice Setup periodic UI updates
     */
    setupPeriodicUpdates() {
        // Clear existing interval if any
        if (this.updateInterval) {
            clearInterval(this.updateInterval);
        }

        // Setup new interval
        this.updateInterval = setInterval(async () => {
            if (walletManager.isReady()) {
                await this.updateUI();
            }
        }, APP_CONFIG.UPDATE_INTERVAL);
    }

    /**
     * @notice Initialize UI elements
     */
    initializeUI() {
        // Set app version
        this.setAppVersion();

        // Initialize feature flags
        this.applyFeatureFlags();

        // Update protocol stats with initial values
        this.updateProtocolStats();

        // Initialize pools data
        this.updatePoolsData();
    }

    /**
     * @notice Handle wallet connection
     */
    async connectWallet() {
        try {
            const connected = await walletManager.connect();
            if (connected) {
                // Initialize contracts after wallet connection
                await contractManager.initialize();
            }
        } catch (error) {
            console.error('Error connecting wallet:', error);
            this.showNotification('Failed to connect wallet', 'error');
        }
    }

    /**
     * @notice Handle wallet connected event
     */
    async handleWalletConnected(event) {
        try {
            console.log('Wallet connected:', event.detail.account);
            
            // Initialize contracts
            await contractManager.initialize();
            
            // Update UI with user data
            await this.updateUserData();
            
            // Enable UI elements
            this.enableUserInterface();

        } catch (error) {
            console.error('Error handling wallet connection:', error);
        }
    }

    /**
     * @notice Handle wallet disconnected event
     */
    handleWalletDisconnected() {
        console.log('Wallet disconnected');
        
        // Reset contracts
        contractManager.reset();
        
        // Disable UI elements
        this.disableUserInterface();
        
        // Clear user data
        this.clearUserData();
    }

    /**
     * @notice Handle deposit transaction
     */
    async handleDeposit() {
        try {
            const amountInput = document.getElementById('depositAmount');
            const amount = amountInput.value;

            if (!amount) {
                this.showNotification('Please enter a deposit amount', 'error');
                return;
            }

            const success = await vaultManager.deposit(amount);
            if (success) {
                amountInput.value = '';
                this.updateDepositPreview();
            }

        } catch (error) {
            console.error('Deposit error:', error);
            this.showNotification('Deposit failed: ' + error.message, 'error');
        }
    }

    /**
     * @notice Handle withdraw transaction
     */
    async handleWithdraw() {
        try {
            const amountInput = document.getElementById('withdrawAmount');
            const shares = amountInput.value;

            if (!shares) {
                this.showNotification('Please enter withdrawal amount', 'error');
                return;
            }

            const success = await vaultManager.withdraw(shares);
            if (success) {
                amountInput.value = '';
                this.updateWithdrawPreview();
            }

        } catch (error) {
            console.error('Withdraw error:', error);
            this.showNotification('Withdrawal failed: ' + error.message, 'error');
        }
    }

    /**
     * @notice Handle yield sharing
     */
    async handleYieldShare() {
        try {
            if (!FEATURES.YIELD_SHARING_ENABLED) {
                this.showNotification('Yield sharing is currently disabled', 'info');
                return;
            }

            const amountInput = document.getElementById('yieldShareAmount');
            const amount = amountInput.value;

            if (!amount) {
                this.showNotification('Please enter yield share amount', 'error');
                return;
            }

            // Implementation would go here
            this.showNotification('Yield sharing feature coming soon!', 'info');

        } catch (error) {
            console.error('Yield share error:', error);
            this.showNotification('Yield sharing failed: ' + error.message, 'error');
        }
    }

    /**
     * @notice Handle proposal creation
     */
    async handleCreateProposal() {
        try {
            if (!FEATURES.GOVERNANCE_ENABLED) {
                this.showNotification('Governance is currently disabled', 'info');
                return;
            }

            const descriptionInput = document.getElementById('proposalDescription');
            const description = descriptionInput.value;

            if (!description) {
                this.showNotification('Please enter proposal description', 'error');
                return;
            }

            // Implementation would go here
            this.showNotification('Governance feature coming soon!', 'info');

        } catch (error) {
            console.error('Create proposal error:', error);
            this.showNotification('Failed to create proposal: ' + error.message, 'error');
        }
    }

    /**
     * @notice Update deposit preview
     */
    async updateDepositPreview() {
        try {
            const amountInput = document.getElementById('depositAmount');
            const expectedSharesElement = document.getElementById('expectedShares');

            if (!amountInput || !expectedSharesElement) return;

            const amount = amountInput.value;
            if (!amount || parseFloat(amount) <= 0) {
                expectedSharesElement.textContent = '0 YSV';
                return;
            }

            const expectedShares = await vaultManager.previewDeposit(amount);
            expectedSharesElement.textContent = `${parseFloat(expectedShares).toFixed(6)} YSV`;

        } catch (error) {
            console.error('Error updating deposit preview:', error);
        }
    }

    /**
     * @notice Update withdraw preview
     */
    async updateWithdrawPreview() {
        try {
            const sharesInput = document.getElementById('withdrawAmount');
            const expectedAmountElement = document.getElementById('expectedAmount');
            const withdrawalFeeElement = document.getElementById('withdrawalFee');

            if (!sharesInput || !expectedAmountElement) return;

            const shares = sharesInput.value;
            if (!shares || parseFloat(shares) <= 0) {
                expectedAmountElement.textContent = '0 BDAG';
                if (withdrawalFeeElement) withdrawalFeeElement.textContent = '0 BDAG';
                return;
            }

            const expectedAmount = await vaultManager.previewWithdraw(shares);
            const fee = await vaultManager.calculateWithdrawalFee(expectedAmount);

            expectedAmountElement.textContent = `${parseFloat(expectedAmount).toFixed(6)} BDAG`;
            if (withdrawalFeeElement) {
                withdrawalFeeElement.textContent = `${parseFloat(fee).toFixed(6)} BDAG`;
            }

        } catch (error) {
            console.error('Error updating withdraw preview:', error);
        }
    }

    /**
     * @notice Update yield share preview
     */
    async updateYieldSharePreview() {
        try {
            const amountInput = document.getElementById('yieldShareAmount');
            const expectedTokensElement = document.getElementById('expectedGovTokens');

            if (!amountInput || !expectedTokensElement) return;

            const amount = amountInput.value;
            if (!amount || parseFloat(amount) <= 0) {
                expectedTokensElement.textContent = '0 YSG';
                return;
            }

            // Placeholder calculation - would use actual contract call
            const expectedTokens = parseFloat(amount) * 1000; // 1000x multiplier
            expectedTokensElement.textContent = `${expectedTokens.toFixed(0)} YSG`;

        } catch (error) {
            console.error('Error updating yield share preview:', error);
        }
    }

    /**
     * @notice Update all UI data
     */
    async updateUI() {
        try {
            await Promise.all([
                this.updateUserData(),
                this.updateProtocolStats(),
                this.updatePoolsData()
            ]);
        } catch (error) {
            console.error('Error updating UI:', error);
        }
    }

    /**
     * @notice Update user-specific data
     */
    async updateUserData() {
        if (!walletManager.isReady() || !contractManager.isReady()) {
            return;
        }

        try {
            // Update wallet balance
            await walletManager.updateBalance();

            // Get user portfolio
            const portfolio = await vaultManager.getUserPortfolio(walletManager.userAccount);

            // Update portfolio display
            this.updatePortfolioDisplay(portfolio);

            // Update form displays
            this.updateFormDisplays(portfolio);

        } catch (error) {
            console.error('Error updating user data:', error);
        }
    }

    /**
     * @notice Update portfolio display
     */
    updatePortfolioDisplay(portfolio) {
        const elements = {
            userTotalDeposited: document.getElementById('userTotalDeposited'),
            userCurrentValue: document.getElementById('userCurrentValue'),
            userTotalEarned: document.getElementById('userTotalEarned'),
            userAPY: document.getElementById('userAPY')
        };

        if (elements.userTotalDeposited) {
            elements.userTotalDeposited.textContent = `${parseFloat(portfolio.totalDeposited).toFixed(4)} BDAG`;
        }

        if (elements.userCurrentValue) {
            elements.userCurrentValue.textContent = `${parseFloat(portfolio.currentValue).toFixed(4)} BDAG`;
        }

        if (elements.userTotalEarned) {
            elements.userTotalEarned.textContent = `${parseFloat(portfolio.totalEarned).toFixed(4)} BDAG`;
        }

        if (elements.userAPY) {
            elements.userAPY.textContent = `${portfolio.userAPY}%`;
        }
    }

    /**
     * @notice Update form display elements
     */
    updateFormDisplays(portfolio) {
        const userBalanceElement = document.getElementById('userBalance');
        const userSharesElement = document.getElementById('userShares');

        if (userBalanceElement) {
            userBalanceElement.textContent = `${parseFloat(portfolio.tokenBalance).toFixed(6)} BDAG`;
        }

        if (userSharesElement) {
            userSharesElement.textContent = `${parseFloat(portfolio.vaultShares).toFixed(6)} YSV`;
        }
    }

    /**
     * @notice Update protocol statistics
     */
    async updateProtocolStats() {
        try {
            // These would be real contract calls in production
            const stats = {
                totalTVL: '$1,234,567',
                totalUsers: '1,337',
                avgAPY: '12.5%',
                totalYield: '$98,765'
            };

            // Update display elements
            const elements = {
                totalTVL: document.getElementById('totalTVL'),
                totalUsers: document.getElementById('totalUsers'),
                avgAPY: document.getElementById('avgAPY'),
                totalYield: document.getElementById('totalYield')
            };

            Object.keys(stats).forEach(key => {
                if (elements[key]) {
                    elements[key].textContent = stats[key];
                }
            });

        } catch (error) {
            console.error('Error updating protocol stats:', error);
        }
    }

    /**
     * @notice Update pools data
     */
    async updatePoolsData() {
        try {
            // Mock pools data - would come from contracts in production
            const poolsData = [
                { 
                    name: 'AMM Pool', 
                    type: 'Automated Market Maker', 
                    apy: '8.5%', 
                    tvl: '$456,789', 
                    allocation: '30%',
                    risk: 'Medium',
                    address: '0x1234...5678'
                },
                { 
                    name: 'Lending Pool', 
                    type: 'Lending Protocol', 
                    apy: '12.3%', 
                    tvl: '$654,321', 
                    allocation: '45%',
                    risk: 'Low',
                    address: '0x2345...6789'
                },
                { 
                    name: 'Staking Pool', 
                    type: 'Staking Rewards', 
                    apy: '15.7%', 
                    tvl: '$987,654', 
                    allocation: '25%',
                    risk: 'High',
                    address: '0x3456...7890'
                }
            ];

            this.renderPoolsData(poolsData);

        } catch (error) {
            console.error('Error updating pools data:', error);
        }
    }

    /**
     * @notice Render pools data in the UI
     */
    renderPoolsData(poolsData) {
        const poolsList = document.getElementById('poolsList');
        if (!poolsList) return;

        poolsList.innerHTML = poolsData.map(pool => `
            <div class="pool-card" data-address="${pool.address}">
                <div class="pool-header">
                    <div class="pool-name">${pool.name}</div>
                    <div class="pool-apy">${pool.apy} APY</div>
                </div>
                <div class="pool-stats">
                    <div class="pool-stat">
                        <div class="pool-stat-value">${pool.tvl}</div>
                        <div class="pool-stat-label">TVL</div>
                    </div>
                    <div class="pool-stat">
                        <div class="pool-stat-value">${pool.allocation}</div>
                        <div class="pool-stat-label">Allocation</div>
                    </div>
                </div>
                <div class="pool-details">
                    <div class="pool-type">${pool.type}</div>
                    <div class="pool-risk risk-${pool.risk.toLowerCase()}">Risk: ${pool.risk}</div>
                </div>
            </div>
        `).join('');
    }

    /**
     * @notice Show specific tab
     */
    showTab(tabName) {
        // Hide all tabs
        document.querySelectorAll('.tab-content').forEach(tab => {
            tab.classList.remove('active');
        });
        document.querySelectorAll('.tab').forEach(tab => {
            tab.classList.remove('active');
        });

        // Show selected tab
        const targetTab = document.getElementById(tabName + 'Tab');
        const targetButton = document.querySelector(`.tab[onclick*="${tabName}"], .tab:nth-child(${this.getTabIndex(tabName)})`);
        
        if (targetTab) {
            targetTab.classList.add('active');
        }
        
        if (targetButton) {
            targetButton.classList.add('active');
        }

        this.currentTab = tabName;

        // Update tab-specific data
        this.updateTabData(tabName);
    }

    /**
     * @notice Get tab index for selection
     */
    getTabIndex(tabName) {
        const tabMap = { deposit: 1, withdraw: 2, governance: 3, pools: 4 };
        return tabMap[tabName] || 1;
    }

    /**
     * @notice Update data for specific tab
     */
    async updateTabData(tabName) {
        try {
            switch (tabName) {
                case 'deposit':
                    await this.updateDepositPreview();
                    break;
                case 'withdraw':
                    await this.updateWithdrawPreview();
                    break;
                case 'governance':
                    await this.updateGovernanceData();
                    break;
                case 'pools':
                    await this.updatePoolsData();
                    break;
            }
        } catch (error) {
            console.error(`Error updating ${tabName} tab data:`, error);
        }
    }

    /**
     * @notice Update governance tab data
     */
    async updateGovernanceData() {
        try {
            if (!contractManager.isReady()) return;

            // Update governance-specific elements
            const votingPowerElement = document.getElementById('votingPower');
            const communityPoolElement = document.getElementById('communityPool');

            if (votingPowerElement) {
                // This would be a real contract call
                votingPowerElement.textContent = '0 YSG';
            }

            if (communityPoolElement) {
                // This would be a real contract call
                communityPoolElement.textContent = '0 BDAG';
            }

            // Update proposals list
            await this.updateProposalsList();

        } catch (error) {
            console.error('Error updating governance data:', error);
        }
    }

    /**
     * @notice Update proposals list
     */
    async updateProposalsList() {
        const proposalsList = document.getElementById('proposalsList');
        if (!proposalsList) return;

        try {
            // Mock proposals data - would come from contract
            const proposals = [];

            if (proposals.length === 0) {
                proposalsList.innerHTML = '<p>No active proposals</p>';
            } else {
                proposalsList.innerHTML = proposals.map(proposal => `
                    <div class="proposal-card" data-id="${proposal.id}">
                        <div class="proposal-header">
                            <h4>${proposal.title}</h4>
                            <span class="proposal-status">${proposal.status}</span>
                        </div>
                        <p class="proposal-description">${proposal.description}</p>
                        <div class="proposal-votes">
                            <span>For: ${proposal.forVotes}</span>
                            <span>Against: ${proposal.againstVotes}</span>
                        </div>
                        <div class="proposal-actions">
                            <button class="button" onclick="voteOnProposal(${proposal.id}, true)">Vote For</button>
                            <button class="button button-secondary" onclick="voteOnProposal(${proposal.id}, false)">Vote Against</button>
                        </div>
                    </div>
                `).join('');
            }

        } catch (error) {
            console.error('Error updating proposals list:', error);
        }
    }

    /**
     * @notice Set maximum deposit amount
     */
    async setMaxDeposit() {
        await vaultManager.setMaxDeposit();
    }

    /**
     * @notice Set maximum withdrawal amount
     */
    async setMaxWithdraw() {
        await vaultManager.setMaxWithdraw();
    }

    /**
     * @notice Enable user interface elements
     */
    enableUserInterface() {
        const elements = [
            'depositBtn', 'withdrawBtn', 'shareYieldBtn', 'createProposalBtn'
        ];

        elements.forEach(id => {
            const element = document.getElementById(id);
            if (element) {
                element.disabled = false;
            }
        });
    }

    /**
     * @notice Disable user interface elements
     */
    disableUserInterface() {
        const elements = [
            'depositBtn', 'withdrawBtn', 'shareYieldBtn', 'createProposalBtn'
        ];

        elements.forEach(id => {
            const element = document.getElementById(id);
            if (element) {
                element.disabled = true;
            }
        });
    }

    /**
     * @notice Clear user data from UI
     */
    clearUserData() {
        const elements = {
            walletBalance: '0 BDAG',
            userBalance: '0 BDAG',
            userShares: '0 YSV',
            userTotalDeposited: '0',
            userCurrentValue: '0',
            userTotalEarned: '0',
            userAPY: '0%',
            votingPower: '0 YSG',
            communityPool: '0 BDAG'
        };

        Object.keys(elements).forEach(id => {
            const element = document.getElementById(id);
            if (element) {
                element.textContent = elements[id];
            }
        });
    }

    /**
     * @notice Validate number input
     */
    validateNumberInput(event) {
        const input = event.target;
        const value = input.value;

        if (value && isNaN(value)) {
            input.setCustomValidity('Please enter a valid number');
            input.reportValidity();
        } else {
            input.setCustomValidity('');
        }
    }

    /**
     * @notice Format number input
     */
    formatNumberInput(event) {
        const input = event.target;
        let value = input.value;

        // Remove any non-numeric characters except decimal point
        value = value.replace(/[^0-9.]/g, '');

        // Ensure only one decimal point
        const parts = value.split('.');
        if (parts.length > 2) {
            value = parts[0] + '.' + parts.slice(1).join('');
        }

        // Limit decimal places
        if (parts[1] && parts[1].length > APP_CONFIG.MAX_DECIMAL_PLACES) {
            value = parts[0] + '.' + parts[1].substring(0, APP_CONFIG.MAX_DECIMAL_PLACES);
        }

        input.value = value;
    }

    /**
     * @notice Set app version in UI
     */
    setAppVersion() {
        const versionElement = document.getElementById('appVersion');
        if (versionElement) {
            versionElement.textContent = APP_CONFIG.APP_VERSION;
        }
    }

    /**
     * @notice Apply feature flags to UI
     */
    applyFeatureFlags() {
        // Hide/show features based on flags
        if (!FEATURES.GOVERNANCE_ENABLED) {
            const governanceTab = document.querySelector('.tab:nth-child(3)');
            if (governanceTab) {
                governanceTab.style.display = 'none';
            }
        }

        if (!FEATURES.YIELD_SHARING_ENABLED) {
            const yieldShareSection = document.querySelector('#governanceTab h3');
            if (yieldShareSection) {
                yieldShareSection.parentElement.style.display = 'none';
            }
        }
    }

    /**
     * @notice Show notification to user
     */
    showNotification(message, type = 'info', duration = APP_CONFIG.NOTIFICATION_TIMEOUT) {
        const notifications = document.getElementById('notifications');
        if (!notifications) return;

        const id = Date.now().toString();
        const notification = document.createElement('div');
        notification.className = `notification ${type}`;
        notification.textContent = message;
        notification.id = id;

        notifications.appendChild(notification);

        // Store notification reference
        this.notifications.set(id, notification);

        // Auto-remove after duration
        setTimeout(() => {
            this.removeNotification(id);
        }, duration);

        return id;
    }

    /**
     * @notice Remove notification
     */
    removeNotification(id) {
        const notification = this.notifications.get(id);
        if (notification && notification.parentNode) {
            notification.parentNode.removeChild(notification);
            this.notifications.delete(id);
        }
    }

    /**
     * @notice Show loading state for buttons
     */
    showLoading(action, show) {
        const btn = document.getElementById(action + 'Btn');
        const text = document.getElementById(action + 'BtnText');
        const loading = document.getElementById(action + 'Loading');

        if (!btn) return;

        if (show) {
            btn.disabled = true;
            if (text) text.classList.add('hidden');
            if (loading) loading.classList.remove('hidden');
        } else {
            btn.disabled = false;
            if (text) text.classList.remove('hidden');
            if (loading) loading.classList.add('hidden');
        }
    }

    /**
     * @notice Clean up resources
     */
    cleanup() {
        // Clear intervals
        if (this.updateInterval) {
            clearInterval(this.updateInterval);
            this.updateInterval = null;
        }

        // Clear notifications
        this.notifications.clear();

        // Clean up wallet manager
        walletManager.cleanup();

        // Reset state
        this.isInitialized = false;
    }
}

// ============ Global App Instance ============
const appManager = new AppManager();

// ============ Global Functions (for HTML onclick handlers) ============
window.showTab = (tabName) => {
    appManager.showTab(tabName);
};

window.setMaxDeposit = () => {
    appManager.setMaxDeposit();
};

window.setMaxWithdraw = () => {
    appManager.setMaxWithdraw();
};

window.deposit = () => {
    appManager.handleDeposit();
};

window.withdraw = () => {
    appManager.handleWithdraw();
};

window.shareYield = () => {
    appManager.handleYieldShare();
};

window.createProposal = () => {
    appManager.handleCreateProposal();
};

// ============ Export Functions ============
export const showNotification = (message, type, duration) => {
    return appManager.showNotification(message, type, duration);
};

export const showLoading = (action, show) => {
    appManager.showLoading(action, show);
};

export const updateUserData = () => {
    return appManager.updateUserData();
};

// ============ Initialize App on Load ============
window.addEventListener('load', async () => {
    console.log('DOM loaded, initializing YieldSync DApp...');
    await appManager.initialize();
});

// ============ Handle Page Unload ============
window.addEventListener('beforeunload', () => {
    appManager.cleanup();
});

// ============ Export App Manager ============
export default appManager;