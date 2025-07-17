// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IYieldVault } from "./interfaces/IYieldVault.sol";
import { IYieldAggregator } from "./interfaces/IYieldAggregator.sol";
import { IFeeOptimizer } from "./interfaces/IFeeOptimizer.sol";

/**
 * @title YieldVault
 * @author Zoll - YieldSync Team
 * @notice Main vault contract that handles user deposits and withdrawals
 * @dev Implements ERC20 for share tokens with yield optimization through aggregator
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
contract YieldVault is IYieldVault, ERC20, ReentrancyGuard, AccessControl, Pausable {
    using SafeERC20 for IERC20;

    // ============ Errors ============
    error YieldVault__InsufficientBalance(uint256 requested, uint256 available);
    error YieldVault__InvalidAmount();
    error YieldVault__TransferFailed();
    error YieldVault__Unauthorized();
    error YieldVault__InvalidAddress();
    error YieldVault__ExcessiveSlippage();
    error YieldVault__DepositCapExceeded();

    // ============ Type declarations ============
    struct UserInfo {
        uint256 shares;
        uint256 lastInteractionTime;
        uint256 totalDeposited;
        uint256 totalWithdrawn;
    }

    // ============ State variables ============
    /// @notice The underlying asset token (e.g., BDAG, USDC)
    IERC20 public immutable asset;

    /// @notice The yield aggregator contract
    IYieldAggregator public immutable aggregator;

    /// @notice The fee optimizer contract
    IFeeOptimizer public immutable feeOptimizer;

    /// @notice Role identifier for managers who can perform admin functions
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice Role identifier for the aggregator contract
    bytes32 public constant AGGREGATOR_ROLE = keccak256("AGGREGATOR_ROLE");

    /// @notice Maximum deposit cap to prevent excessive concentration
    uint256 public constant MAX_DEPOSIT_CAP = 1_000_000 * 1e18; // 1M tokens

    /// @notice Minimum shares to prevent dust attacks
    uint256 public constant MIN_SHARES = 1000;

    /// @notice Basis points for percentage calculations (10000 = 100%)
    uint256 public constant BASIS_POINTS = 10_000;

    /// @notice Maximum slippage tolerance for withdrawals (1% = 100 basis points)
    uint256 public constant MAX_SLIPPAGE = 100;

    /// @notice Total assets deposited in the vault
    uint256 private s_totalAssets;

    /// @notice Total fees collected
    uint256 private s_totalFeesCollected;

    /// @notice Fee collector address
    address private s_feeCollector;

    /// @notice User information mapping
    mapping(address => UserInfo) private s_userInfo;

    /// @notice Performance fee in basis points (e.g., 200 = 2%)
    uint256 private s_performanceFee;

    /// @notice Management fee in basis points (e.g., 100 = 1% annually)
    uint256 private s_managementFee;

    /// @notice Last fee collection timestamp
    uint256 private s_lastFeeCollection;

    /// @notice Current deposit cap
    uint256 private s_depositCap;

    // ============ Events ============
    event Deposited(address indexed user, uint256 amount, uint256 shares);
    event Withdrawn(address indexed user, uint256 amount, uint256 shares);
    event YieldHarvested(uint256 totalYield, uint256 timestamp);
    event FeeCollected(uint256 feeAmount, address indexed feeCollector);
    event PerformanceFeeUpdated(uint256 newFee);
    event ManagementFeeUpdated(uint256 newFee);
    event FeeCollectorUpdated(address indexed newFeeCollector);
    event DepositCapUpdated(uint256 newCap);

    // ============ Modifiers ============
    modifier onlyManager() {
        if (!hasRole(MANAGER_ROLE, msg.sender)) {
            revert YieldVault__Unauthorized();
        }
        _;
    }

    modifier onlyAggregator() {
        if (!hasRole(AGGREGATOR_ROLE, msg.sender)) {
            revert YieldVault__Unauthorized();
        }
        _;
    }

    modifier validAmount(uint256 amount) {
        if (amount == 0) {
            revert YieldVault__InvalidAmount();
        }
        _;
    }

    modifier validAddress(address addr) {
        if (addr == address(0)) {
            revert YieldVault__InvalidAddress();
        }
        _;
    }

    // ============ Constructor ============
    /**
     * @notice Initialize the YieldVault contract
     * @param _asset The underlying asset token
     * @param _aggregator The yield aggregator contract
     * @param _feeOptimizer The fee optimizer contract
     * @param _feeCollector The fee collector address
     * @param _name The name of the vault share token
     * @param _symbol The symbol of the vault share token
     */
    constructor(
        address _asset,
        address _aggregator,
        address _feeOptimizer,
        address _feeCollector,
        string memory _name,
        string memory _symbol
    )
        ERC20(_name, _symbol)
        validAddress(_asset)
        validAddress(_aggregator)
        validAddress(_feeOptimizer)
        validAddress(_feeCollector)
    {
        asset = IERC20(_asset);
        aggregator = IYieldAggregator(_aggregator);
        feeOptimizer = IFeeOptimizer(_feeOptimizer);
        s_feeCollector = _feeCollector;

        // Set initial parameters
        s_performanceFee = 200; // 2%
        s_managementFee = 100; // 1%
        s_depositCap = MAX_DEPOSIT_CAP;
        s_lastFeeCollection = block.timestamp;

        // Grant roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, msg.sender);
        _grantRole(AGGREGATOR_ROLE, _aggregator);
    }

    // ============ External Functions ============

    /**
     * @notice Override balanceOf due to multiple inheritance (ERC20, IYieldVault)
     * @param account The address to query
     * @return The balance of the account
     */
    function balanceOf(address account)
        public
        view
        override(ERC20, IYieldVault)
        returns (uint256)
    {
        return super.balanceOf(account);
    }

    /**
     * @notice Deposit assets into the vault and receive shares
     * @param amount The amount of assets to deposit
     * @return shares The number of shares minted to the user
     */
    function deposit(uint256 amount)
        external
        override
        nonReentrant
        whenNotPaused
        validAmount(amount)
        returns (uint256 shares)
    {
        // Check deposit cap
        if (s_totalAssets + amount > s_depositCap) {
            revert YieldVault__DepositCapExceeded();
        }

        // Calculate shares to mint
        shares = convertToShares(amount);

        // Ensure minimum shares requirement
        if (shares < MIN_SHARES && totalSupply() == 0) {
            revert YieldVault__InvalidAmount();
        }

        // Update user information
        UserInfo storage userInfo = s_userInfo[msg.sender];
        userInfo.shares += shares;
        userInfo.lastInteractionTime = block.timestamp;
        userInfo.totalDeposited += amount;

        // Update total assets
        s_totalAssets += amount;

        // Transfer assets from user to vault
        asset.safeTransferFrom(msg.sender, address(this), amount);

        // Mint shares to user
        _mint(msg.sender, shares);

        // Allocate funds through aggregator
        _allocateFunds(amount);

        emit Deposited(msg.sender, amount, shares);
    }

    /**
     * @notice Withdraw assets from the vault by burning shares
     * @param shares The number of shares to burn
     * @return amount The amount of assets withdrawn
     */
    function withdraw(uint256 shares)
        external
        override
        nonReentrant
        whenNotPaused
        validAmount(shares)
        returns (uint256 amount)
    {
        // Check user has sufficient shares
        if (balanceOf(msg.sender) < shares) {
            revert YieldVault__InsufficientBalance(shares, balanceOf(msg.sender));
        }

        // Calculate amount to withdraw
        amount = convertToAssets(shares);

        // Check vault has sufficient assets
        if (amount > s_totalAssets) {
            revert YieldVault__InsufficientBalance(amount, s_totalAssets);
        }

        // Calculate and apply withdrawal fee
        uint256 fee = feeOptimizer.calculateFee(amount);
        uint256 amountAfterFee = amount - fee;

        // Ensure vault has sufficient balance for withdrawal + fee
        uint256 vaultBalance = asset.balanceOf(address(this));
        if (vaultBalance < amount) {
            // Request funds from aggregator
            aggregator.withdrawForVault(amount - vaultBalance);
            vaultBalance = asset.balanceOf(address(this));
        }

        // Check if we actually have enough after aggregator withdrawal
        // (pool withdrawal fees may reduce the amount we get back)
        if (vaultBalance < amount) {
            // Adjust the withdrawal amount based on what's actually available
            amount = vaultBalance;
            fee = feeOptimizer.calculateFee(amount);
            amountAfterFee = amount - fee;
        }

        // Update user information
        UserInfo storage userInfo = s_userInfo[msg.sender];
        userInfo.shares -= shares;
        userInfo.lastInteractionTime = block.timestamp;
        userInfo.totalWithdrawn += amountAfterFee;

        // Update total assets
        s_totalAssets -= amount;

        // Burn shares from user
        _burn(msg.sender, shares);

        // Collect fee
        if (fee > 0) {
            s_totalFeesCollected += fee;
            asset.safeTransfer(s_feeCollector, fee);
            emit FeeCollected(fee, s_feeCollector);
        }

        // Transfer assets to user
        asset.safeTransfer(msg.sender, amountAfterFee);

        emit Withdrawn(msg.sender, amountAfterFee, shares);
    }

    /**
     * @notice Emergency withdrawal function for users (bypasses normal flow)
     * @param shares The number of shares to burn
     * @return amount The amount of assets withdrawn
     */
    function emergencyWithdraw(uint256 shares)
        external
        nonReentrant
        validAmount(shares)
        returns (uint256 amount)
    {
        // Check user has sufficient shares
        if (balanceOf(msg.sender) < shares) {
            revert YieldVault__InsufficientBalance(shares, balanceOf(msg.sender));
        }

        // Calculate amount to withdraw (no fees in emergency)
        amount = convertToAssets(shares);

        // Ensure vault has sufficient balance for withdrawal
        uint256 vaultBalance = asset.balanceOf(address(this));
        if (vaultBalance < amount) {
            // Request funds from aggregator
            aggregator.withdrawForVault(amount - vaultBalance);
            vaultBalance = asset.balanceOf(address(this));
        }

        // Check if we actually have enough after aggregator withdrawal
        // (pool withdrawal fees may reduce the amount we get back)
        if (vaultBalance < amount) {
            // Adjust the withdrawal amount based on what's actually available
            amount = vaultBalance;
        }

        // Update user information
        UserInfo storage userInfo = s_userInfo[msg.sender];
        userInfo.shares -= shares;
        userInfo.lastInteractionTime = block.timestamp;
        userInfo.totalWithdrawn += amount;

        // Update total assets
        s_totalAssets -= amount;

        // Burn shares from user
        _burn(msg.sender, shares);

        // Transfer assets to user
        asset.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount, shares);
    }

    // ============ Admin Functions ============
    /**
     * @notice Harvest yield from the aggregator
     * @dev Only callable by managers or aggregator
     */
    function harvestYield() external onlyManager {
        uint256 yieldAmount = _harvestYield();

        if (yieldAmount > 0) {
            // Update total assets
            s_totalAssets += yieldAmount;

            // Collect performance fee
            uint256 performanceFeeAmount = (yieldAmount * s_performanceFee) / BASIS_POINTS;
            if (performanceFeeAmount > 0) {
                s_totalFeesCollected += performanceFeeAmount;
                asset.safeTransfer(s_feeCollector, performanceFeeAmount);
                emit FeeCollected(performanceFeeAmount, s_feeCollector);
            }

            emit YieldHarvested(yieldAmount, block.timestamp);
        }
    }

    /**
     * @notice Collect management fees
     * @dev Only callable by managers
     */
    function collectManagementFees() external onlyManager {
        uint256 timeElapsed = block.timestamp - s_lastFeeCollection;
        uint256 annualFee = (s_totalAssets * s_managementFee) / BASIS_POINTS;
        uint256 feeAmount = (annualFee * timeElapsed) / 365 days;

        if (feeAmount > 0) {
            s_totalFeesCollected += feeAmount;
            s_lastFeeCollection = block.timestamp;

            asset.safeTransfer(s_feeCollector, feeAmount);
            emit FeeCollected(feeAmount, s_feeCollector);
        }
    }

    /**
     * @notice Pause the vault (emergency function)
     * @dev Only callable by managers
     */
    function pause() external onlyManager {
        _pause();
    }

    /**
     * @notice Unpause the vault
     * @dev Only callable by managers
     */
    function unpause() external onlyManager {
        _unpause();
    }

    /**
     * @notice Update performance fee
     * @param newFee The new performance fee in basis points
     * @dev Only callable by managers, max 10%
     */
    function setPerformanceFee(uint256 newFee) external onlyManager {
        if (newFee > 1000) revert YieldVault__InvalidAmount(); // Max 10%
        s_performanceFee = newFee;
        emit PerformanceFeeUpdated(newFee);
    }

    /**
     * @notice Update management fee
     * @param newFee The new management fee in basis points
     * @dev Only callable by managers, max 5%
     */
    function setManagementFee(uint256 newFee) external onlyManager {
        if (newFee > 500) revert YieldVault__InvalidAmount(); // Max 5%
        s_managementFee = newFee;
        emit ManagementFeeUpdated(newFee);
    }

    /**
     * @notice Update fee collector address
     * @param newFeeCollector The new fee collector address
     * @dev Only callable by managers
     */
    function setFeeCollector(address newFeeCollector)
        external
        onlyManager
        validAddress(newFeeCollector)
    {
        s_feeCollector = newFeeCollector;
        emit FeeCollectorUpdated(newFeeCollector);
    }

    /**
     * @notice Update deposit cap
     * @param newCap The new deposit cap
     * @dev Only callable by managers
     */
    function setDepositCap(uint256 newCap) external onlyManager {
        s_depositCap = newCap;
        emit DepositCapUpdated(newCap);
    }

    // ============ Public Functions ============
    /**
     * @notice Get the current exchange rate between assets and shares
     * @return rate The current exchange rate (assets per share)
     */
    function getExchangeRate() public view override returns (uint256 rate) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            rate = 1e18; // 1:1 ratio initially
        } else {
            rate = (s_totalAssets * 1e18) / supply;
        }
    }

    /**
     * @notice Get the total assets managed by the vault
     * @return totalAssets The total amount of assets under management
     */
    function totalAssets() public view override returns (uint256) {
        return s_totalAssets;
    }

    /**
     * @notice Convert asset amount to shares
     * @param assets The amount of assets
     * @return shares The equivalent amount of shares
     */
    function convertToShares(uint256 assets) public view returns (uint256 shares) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            shares = assets; // 1:1 ratio initially
        } else {
            shares = (assets * supply) / s_totalAssets;
        }
    }

    /**
     * @notice Convert shares to asset amount
     * @param shares The amount of shares
     * @return assets The equivalent amount of assets
     */
    function convertToAssets(uint256 shares) public view returns (uint256 assets) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            assets = shares; // 1:1 ratio initially
        } else {
            assets = (shares * s_totalAssets) / supply;
        }
    }

    // ============ Internal Functions ============

    /*//////////////////////////////////////////////////////////////
        // Reset allowance to zero first for safety, then increase
        asset.safeApprove(address(aggregator), 0);
        // Reset allowance to zero first for safety, then set to amount
        IERC20(address(asset)).safeApprove(address(aggregator), 0);
        IERC20(address(asset)).safeApprove(address(aggregator), amount);
        
        // Allocate funds through aggregator
        aggregator.allocateFunds(amount);
     * @param amount The amount to allocate
     */

    /**
     * @notice Allocate funds to the aggregator for yield farming
     * @param amount The amount to allocate
     */
    function _allocateFunds(uint256 amount) internal {
        // Approve aggregator to spend our tokens
        asset.forceApprove(address(aggregator), amount);

        // Allocate funds through aggregator
        aggregator.allocateFunds(amount);
    }

    /**
     * @notice Harvest yield from the aggregator
     * @return yieldAmount The amount of yield harvested
     */
    function _harvestYield() internal returns (uint256 yieldAmount) {
        uint256 balanceBefore = asset.balanceOf(address(this));

        // Trigger rebalancing in aggregator to realize gains
        aggregator.rebalancePools();

        uint256 balanceAfter = asset.balanceOf(address(this));
        yieldAmount = balanceAfter - balanceBefore;
    }

    /**
     * @notice Override transfer to update user interaction time
     * @param from The sender address
     * @param to The recipient address
     * @param amount The amount to transfer
     */
    function _update(address from, address to, uint256 amount) internal override {
        super._update(from, to, amount);

        // Update interaction times
        if (from != address(0)) {
            s_userInfo[from].lastInteractionTime = block.timestamp;
        }
        if (to != address(0)) {
            s_userInfo[to].lastInteractionTime = block.timestamp;
        }
    }

    // ============ View Functions ============
    /**
     * @notice Get user information
     * @param user The user address
     * @return userInfo The user information struct
     */
    function getUserInfo(address user) external view returns (UserInfo memory userInfo) {
        userInfo = s_userInfo[user];
    }

    /**
     * @notice Get current performance fee
     * @return performanceFee The current performance fee in basis points
     */
    function getPerformanceFee() external view returns (uint256 performanceFee) {
        performanceFee = s_performanceFee;
    }

    /**
     * @notice Get current management fee
     * @return managementFee The current management fee in basis points
     */
    function getManagementFee() external view returns (uint256 managementFee) {
        managementFee = s_managementFee;
    }

    /**
     * @notice Get fee collector address
     * @return feeCollector The current fee collector address
     */
    function getFeeCollector() external view returns (address feeCollector) {
        feeCollector = s_feeCollector;
    }

    /**
     * @notice Get total fees collected
     * @return totalFees The total amount of fees collected
     */
    function getTotalFeesCollected() external view returns (uint256 totalFees) {
        totalFees = s_totalFeesCollected;
    }

    /**
     * @notice Get current deposit cap
     * @return depositCap The current deposit cap
     */
    function getDepositCap() external view returns (uint256 depositCap) {
        depositCap = s_depositCap;
    }

    /**
     * @notice Get user's asset balance equivalent
     * @param user The user address
     * @return assetBalance The user's asset balance equivalent
     */
    function getUserAssetBalance(address user) external view returns (uint256 assetBalance) {
        assetBalance = convertToAssets(balanceOf(user));
    }
    /**
     * @notice Preview withdrawal - calculate assets for given shares
     * @param shares The amount of shares to burn
     * @return assets The assets that would be withdrawn (before fees)
     */

    function previewWithdraw(uint256 shares) external view returns (uint256 assets) {
        assets = convertToAssets(shares);
    }

    /**
     * @notice Get maximum deposit amount for a user
     * @return maxDeposit The maximum deposit amount
     */
    function getMaxDeposit() external view returns (uint256 maxDeposit) {
        if (paused()) {
            maxDeposit = 0;
        } else {
            maxDeposit = s_depositCap - s_totalAssets;
        }
    }

    /**
     * @notice Get maximum withdrawal amount for a user (ERC4626-style)
     * @param user The user address
     * @return maxWithdrawAmount The maximum withdrawal amount
     */
    function maxWithdraw(address user) external view returns (uint256 maxWithdrawAmount) {
        if (paused()) {
            maxWithdrawAmount = 0;
        } else {
            maxWithdrawAmount = convertToAssets(balanceOf(user));
        }
    }
}
