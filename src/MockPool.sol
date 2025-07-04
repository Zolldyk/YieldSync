// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IMockPool } from "./interfaces/IMockPool.sol";

/**
 * @title MockPool
 * @author YieldSync Team
 * @notice Mock liquidity pool for testing yield aggregation functionality
 * @dev Simulates a liquidity pool with configurable APY and yield generation
 *
 * This contract simulates:
 * - Liquidity pool deposits and withdrawals
 * - Yield generation based on configurable APY
 * - Time-based yield accumulation
 * - Pool state management for testing scenarios
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
contract MockPool is IMockPool, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ Errors ============
    error MockPool__InsufficientFunds();
    error MockPool__InvalidAmount();
    error MockPool__Unauthorized();
    error MockPool__InvalidAddress();
    error MockPool__PoolPaused();
    error MockPool__InvalidAPY();

    // ============ Type Declarations ============
    struct UserDeposit {
        uint256 amount; // Amount deposited
        uint256 depositTime; // Time of deposit
        uint256 lastYieldClaim; // Last time yield was claimed
    }

    struct PoolConfig {
        uint256 apy; // Annual Percentage Yield in basis points
        uint256 totalDeposits; // Total deposits in the pool
        uint256 totalYield; // Total yield generated
        uint256 lastYieldUpdate; // Last time yield was calculated
        bool isPaused; // Whether the pool is paused
        uint256 maxDeposit; // Maximum deposit per user
        uint256 withdrawalFee; // Withdrawal fee in basis points
    }

    // ============ State Variables ============
    /// @notice The underlying asset token
    IERC20 public immutable asset;

    /// @notice Role identifier for pool managers
    bytes32 public constant POOL_MANAGER_ROLE = keccak256("POOL_MANAGER_ROLE");

    /// @notice Basis points for percentage calculations
    uint256 public constant BASIS_POINTS = 10_000;

    /// @notice Seconds in a year for APY calculations
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    /// @notice Pool configuration
    PoolConfig private s_poolConfig;

    /// @notice Mapping of user address to deposit information
    mapping(address => UserDeposit) private s_userDeposits;

    /// @notice Array of all depositors for iteration
    address[] private s_depositors;

    /// @notice Pool name for identification
    string public poolName;

    /// @notice Pool type (e.g., "AMM", "Lending", "Staking")
    string public poolType;

    // ============ Events ============
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event YieldGenerated(uint256 yieldAmount, uint256 timestamp);
    event YieldClaimed(address indexed user, uint256 yieldAmount);
    event APYUpdated(uint256 newAPY);
    event PoolConfigUpdated(uint256 maxDeposit, uint256 withdrawalFee);
    event PoolPaused(bool paused);

    // ============ Modifiers ============
    modifier onlyPoolManager() {
        if (!hasRole(POOL_MANAGER_ROLE, msg.sender)) {
            revert MockPool__Unauthorized();
        }
        _;
    }

    modifier whenNotPaused() {
        if (s_poolConfig.isPaused) {
            revert MockPool__PoolPaused();
        }
        _;
    }

    modifier validAmount(uint256 amount) {
        if (amount == 0) {
            revert MockPool__InvalidAmount();
        }
        _;
    }

    modifier validAddress(address addr) {
        if (addr == address(0)) {
            revert MockPool__InvalidAddress();
        }
        _;
    }

    // ============ Constructor ============
    /**
     * @notice Initialize the MockPool contract
     * @param _asset The underlying asset token
     * @param _apy Initial APY in basis points
     * @param _poolName Name of the pool
     * @param _poolType Type of the pool
     */
    constructor(
        address _asset,
        uint256 _apy,
        string memory _poolName,
        string memory _poolType
    )
        validAddress(_asset)
    {
        asset = IERC20(_asset);
        poolName = _poolName;
        poolType = _poolType;

        // Initialize pool configuration
        s_poolConfig = PoolConfig({
            apy: _apy,
            totalDeposits: 0,
            totalYield: 0,
            lastYieldUpdate: block.timestamp,
            isPaused: false,
            maxDeposit: 100_000 * 10 ** 18, // 100k tokens max deposit
            withdrawalFee: 50 // 0.5% withdrawal fee
         });

        // Grant roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(POOL_MANAGER_ROLE, msg.sender);
    }

    // ============ External Functions ============
    /**
     * @notice Deposit assets into the mock pool
     * @param amount The amount to deposit
     */
    function deposit(uint256 amount)
        external
        override
        nonReentrant
        whenNotPaused
        validAmount(amount)
    {
        // Check deposit limit
        UserDeposit storage userDeposit = s_userDeposits[msg.sender];
        if (userDeposit.amount + amount > s_poolConfig.maxDeposit) {
            revert MockPool__InvalidAmount();
        }

        // Update yield before deposit
        _updatePoolYield();

        // If first deposit, add to depositors array
        if (userDeposit.amount == 0) {
            s_depositors.push(msg.sender);
            userDeposit.depositTime = block.timestamp;
            userDeposit.lastYieldClaim = block.timestamp;
        }

        // Update user deposit
        userDeposit.amount += amount;

        // Update pool totals
        s_poolConfig.totalDeposits += amount;

        // Transfer tokens from user to pool
        asset.safeTransferFrom(msg.sender, address(this), amount);

        emit Deposited(msg.sender, amount);
    }

    /**
     * @notice Withdraw assets from the mock pool
     * @param amount The amount to withdraw
     */
    function withdraw(uint256 amount) external override nonReentrant validAmount(amount) {
        UserDeposit storage userDeposit = s_userDeposits[msg.sender];

        // Check user has sufficient deposits
        if (userDeposit.amount < amount) {
            revert MockPool__InsufficientFunds();
        }

        // Update yield before withdrawal
        _updatePoolYield();

        // Calculate withdrawal fee
        uint256 fee = (amount * s_poolConfig.withdrawalFee) / BASIS_POINTS;
        uint256 amountAfterFee = amount - fee;

        // Update user deposit
        userDeposit.amount -= amount;

        // Update pool totals
        s_poolConfig.totalDeposits -= amount;

        // Remove from depositors array if no more deposits
        if (userDeposit.amount == 0) {
            _removeDepositor(msg.sender);
        }

        // Transfer tokens to user (minus fee)
        asset.safeTransfer(msg.sender, amountAfterFee);

        emit Withdrawn(msg.sender, amountAfterFee);
    }

    /**
     * @notice Claim accumulated yield
     * @return yieldAmount The amount of yield claimed
     */
    function claimYield() external nonReentrant returns (uint256 yieldAmount) {
        UserDeposit storage userDeposit = s_userDeposits[msg.sender];

        if (userDeposit.amount == 0) {
            revert MockPool__InsufficientFunds();
        }

        // Update pool yield
        _updatePoolYield();

        // Calculate user's yield
        yieldAmount = _calculateUserYield(msg.sender);

        if (yieldAmount > 0) {
            // Update user's last claim time
            userDeposit.lastYieldClaim = block.timestamp;

            // Transfer yield to user
            asset.safeTransfer(msg.sender, yieldAmount);

            emit YieldClaimed(msg.sender, yieldAmount);
        }
    }

    /**
     * @notice Update pool APY (only pool manager)
     * @param newAPY The new APY in basis points
     */
    function setAPY(uint256 newAPY) external onlyPoolManager {
        if (newAPY > 50_000) {
            // Max 500% APY
            revert MockPool__InvalidAPY();
        }

        // Update yield before changing APY
        _updatePoolYield();

        s_poolConfig.apy = newAPY;
        emit APYUpdated(newAPY);
    }

    /**
     * @notice Update pool configuration
     * @param maxDeposit Maximum deposit per user
     * @param withdrawalFee Withdrawal fee in basis points
     */
    function updatePoolConfig(uint256 maxDeposit, uint256 withdrawalFee) external onlyPoolManager {
        if (withdrawalFee > 1000) {
            // Max 10% withdrawal fee
            revert MockPool__InvalidAmount();
        }

        s_poolConfig.maxDeposit = maxDeposit;
        s_poolConfig.withdrawalFee = withdrawalFee;

        emit PoolConfigUpdated(maxDeposit, withdrawalFee);
    }

    /**
     * @notice Pause/unpause the pool
     * @param paused Whether to pause the pool
     */
    function setPaused(bool paused) external onlyPoolManager {
        s_poolConfig.isPaused = paused;
        emit PoolPaused(paused);
    }

    /**
     * @notice Simulate yield generation (for testing)
     * @param yieldAmount The amount of yield to generate
     */
    function simulateYieldGeneration(uint256 yieldAmount)
        external
        onlyPoolManager
        validAmount(yieldAmount)
    {
        s_poolConfig.totalYield += yieldAmount;
        emit YieldGenerated(yieldAmount, block.timestamp);
    }

    /**
     * @notice Emergency withdraw for pool manager
     * @param to The address to send funds to
     * @param amount The amount to withdraw
     */
    function emergencyWithdraw(
        address to,
        uint256 amount
    )
        external
        onlyPoolManager
        validAddress(to)
        validAmount(amount)
    {
        asset.safeTransfer(to, amount);
    }

    // ============ Public Functions ============
    /**
     * @notice Get the current APY of the pool
     * @return apy The current APY in basis points
     */
    function getAPY() public view override returns (uint256 apy) {
        apy = s_poolConfig.apy;
    }

    /**
     * @notice Get total assets in the pool
     * @return totalAssets The total amount of assets
     */
    function totalAssets() public view override returns (uint256) {
        return s_poolConfig.totalDeposits;
    }

    /**
     * @notice Get user's balance in the pool
     * @param user The user address
     * @return balance The user's balance
     */
    function balanceOf(address user) public view override returns (uint256 balance) {
        balance = s_userDeposits[user].amount;
    }

    // ============ Internal Functions ============
    /**
     * @notice Update pool yield based on time elapsed and APY
     */
    function _updatePoolYield() internal {
        uint256 timeElapsed = block.timestamp - s_poolConfig.lastYieldUpdate;

        if (timeElapsed > 0 && s_poolConfig.totalDeposits > 0) {
            // Calculate yield: (totalDeposits * APY * timeElapsed) / (BASIS_POINTS *
            // SECONDS_PER_YEAR)
            uint256 yieldGenerated = (s_poolConfig.totalDeposits * s_poolConfig.apy * timeElapsed)
                / (BASIS_POINTS * SECONDS_PER_YEAR);

            if (yieldGenerated > 0) {
                s_poolConfig.totalYield += yieldGenerated;
                s_poolConfig.lastYieldUpdate = block.timestamp;

                emit YieldGenerated(yieldGenerated, block.timestamp);
            }
        }
    }

    /**
     * @notice Calculate yield for a specific user
     * @param user The user address
     * @return userYield The user's accumulated yield
     */
    function _calculateUserYield(address user) internal view returns (uint256 userYield) {
        UserDeposit memory userDeposit = s_userDeposits[user];

        if (userDeposit.amount == 0) {
            return 0;
        }

        // Calculate time since last claim
        uint256 timeElapsed = block.timestamp - userDeposit.lastYieldClaim;

        // Calculate user's proportional yield
        if (timeElapsed > 0) {
            userYield = (userDeposit.amount * s_poolConfig.apy * timeElapsed)
                / (BASIS_POINTS * SECONDS_PER_YEAR);
        }
    }

    /**
     * @notice Remove depositor from array
     * @param depositor The depositor to remove
     */
    function _removeDepositor(address depositor) internal {
        for (uint256 i = 0; i < s_depositors.length; i++) {
            if (s_depositors[i] == depositor) {
                s_depositors[i] = s_depositors[s_depositors.length - 1];
                s_depositors.pop();
                break;
            }
        }
    }

    // ============ View Functions ============
    /**
     * @notice Get pool configuration
     * @return config The pool configuration struct
     */
    function getPoolConfig() external view returns (PoolConfig memory config) {
        config = s_poolConfig;
    }

    /**
     * @notice Get user deposit information
     * @param user The user address
     * @return userDeposit The user deposit struct
     */
    function getUserDeposit(address user) external view returns (UserDeposit memory userDeposit) {
        userDeposit = s_userDeposits[user];
    }

    /**
     * @notice Get all depositors
     * @return depositors Array of all depositor addresses
     */
    function getDepositors() external view returns (address[] memory depositors) {
        depositors = s_depositors;
    }

    /**
     * @notice Get number of depositors
     * @return count The number of depositors
     */
    function getDepositorCount() external view returns (uint256 count) {
        count = s_depositors.length;
    }

    /**
     * @notice Get total yield generated
     * @return totalYield The total yield generated by the pool
     */
    function getTotalYield() external view returns (uint256 totalYield) {
        totalYield = s_poolConfig.totalYield;
    }

    /**
     * @notice Get pool utilization rate
     * @return utilizationRate The utilization rate in basis points
     */
    function getUtilizationRate() external view returns (uint256 utilizationRate) {
        uint256 poolBalance = asset.balanceOf(address(this));
        if (poolBalance == 0) {
            return 0;
        }

        utilizationRate = (s_poolConfig.totalDeposits * BASIS_POINTS) / poolBalance;
    }

    /**
     * @notice Get pending yield for a user
     * @param user The user address
     * @return pendingYield The pending yield amount
     */
    function getPendingYield(address user) external view returns (uint256 pendingYield) {
        pendingYield = _calculateUserYield(user);
    }

    /**
     * @notice Get pool statistics
     * @return totalDeposits Total deposits in the pool
     * @return totalYield Total yield generated
     * @return depositorCount Number of depositors
     * @return averageDeposit Average deposit size
     */
    function getPoolStatistics()
        external
        view
        returns (
            uint256 totalDeposits,
            uint256 totalYield,
            uint256 depositorCount,
            uint256 averageDeposit
        )
    {
        totalDeposits = s_poolConfig.totalDeposits;
        totalYield = s_poolConfig.totalYield;
        depositorCount = s_depositors.length;

        if (depositorCount > 0) {
            averageDeposit = totalDeposits / depositorCount;
        }
    }

    /**
     * @notice Get real-time pool data including pending yield
     * @return apy Current APY
     * @return totalDeposits Total deposits
     * @return totalYield Total yield (including pending)
     * @return lastUpdate Last yield update time
     */
    function getRealTimePoolData()
        external
        view
        returns (uint256 apy, uint256 totalDeposits, uint256 totalYield, uint256 lastUpdate)
    {
        apy = s_poolConfig.apy;
        totalDeposits = s_poolConfig.totalDeposits;
        lastUpdate = s_poolConfig.lastYieldUpdate;

        // Calculate pending yield
        uint256 timeElapsed = block.timestamp - s_poolConfig.lastYieldUpdate;
        uint256 pendingYield = 0;

        if (timeElapsed > 0 && s_poolConfig.totalDeposits > 0) {
            pendingYield = (s_poolConfig.totalDeposits * s_poolConfig.apy * timeElapsed)
                / (BASIS_POINTS * SECONDS_PER_YEAR);
        }

        totalYield = s_poolConfig.totalYield + pendingYield;
    }

    /**
     * @notice Check if pool is healthy (has sufficient liquidity)
     * @return isHealthy Whether the pool is healthy
     * @return healthRatio Health ratio (0-100)
     */
    function getPoolHealth() external view returns (bool isHealthy, uint256 healthRatio) {
        uint256 poolBalance = asset.balanceOf(address(this));
        uint256 totalClaims = s_poolConfig.totalDeposits + s_poolConfig.totalYield;

        if (totalClaims == 0) {
            return (true, 100);
        }

        healthRatio = (poolBalance * 100) / totalClaims;
        isHealthy = healthRatio >= 100; // Pool is healthy if it can cover all claims
    }

    /**
     * @notice Get maximum withdrawable amount for a user
     * @param user The user address
     * @return maxWithdrawable Maximum amount the user can withdraw
     */
    function getMaxWithdrawable(address user) external view returns (uint256 maxWithdrawable) {
        uint256 userBalance = s_userDeposits[user].amount;
        uint256 poolBalance = asset.balanceOf(address(this));

        // User can withdraw up to their balance or pool balance, whichever is smaller
        maxWithdrawable = userBalance < poolBalance ? userBalance : poolBalance;
    }

    /**
     * @notice Calculate withdrawal amount after fees
     * @param amount The withdrawal amount before fees
     * @return amountAfterFee The amount after deducting fees
     * @return fee The fee amount
     */
    function calculateWithdrawalFee(uint256 amount)
        external
        view
        returns (uint256 amountAfterFee, uint256 fee)
    {
        fee = (amount * s_poolConfig.withdrawalFee) / BASIS_POINTS;
        amountAfterFee = amount - fee;
    }

    /**
     * @notice Get pool performance metrics
     * @return annualizedReturn Annualized return based on current APY
     * @return totalReturn Total return since pool inception
     * @return timeWeightedReturn Time-weighted return
     */
    function getPerformanceMetrics()
        external
        view
        returns (uint256 annualizedReturn, uint256 totalReturn, uint256 timeWeightedReturn)
    {
        annualizedReturn = s_poolConfig.apy;

        // Calculate total return (simplified)
        if (s_poolConfig.totalDeposits > 0) {
            totalReturn = (s_poolConfig.totalYield * BASIS_POINTS) / s_poolConfig.totalDeposits;
        }

        // Time-weighted return (simplified - actual implementation would be more complex)
        uint256 timeElapsed = block.timestamp - s_poolConfig.lastYieldUpdate;
        if (timeElapsed > 0) {
            timeWeightedReturn = (totalReturn * SECONDS_PER_YEAR) / timeElapsed;
        }
    }

    /**
     * @notice Get pool asset information
     * @return assetAddress The asset token address
     * @return assetBalance Current asset balance in pool
     * @return name Pool name
     * @return poolType_ Pool type
     */
    function getPoolInfo()
        external
        view
        returns (
            address assetAddress,
            uint256 assetBalance,
            string memory name,
            string memory poolType_
        )
    {
        assetAddress = address(asset);
        assetBalance = asset.balanceOf(address(this));
        name = poolName;
        poolType_ = poolType;
    }

    /**
     * @notice Check if user can deposit a specific amount
     * @param user The user address
     * @param amount The amount to check
     * @return canDeposit Whether the user can deposit this amount
     * @return reason Reason if cannot deposit (0: can deposit, 1: exceeds max, 2: pool paused)
     */
    function canUserDeposit(
        address user,
        uint256 amount
    )
        external
        view
        returns (bool canDeposit, uint256 reason)
    {
        if (s_poolConfig.isPaused) {
            return (false, 2);
        }

        UserDeposit memory userDeposit = s_userDeposits[user];
        if (userDeposit.amount + amount > s_poolConfig.maxDeposit) {
            return (false, 1);
        }

        return (true, 0);
    }
}
