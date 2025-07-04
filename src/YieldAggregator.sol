// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IYieldAggregator } from "./interfaces/IYieldAggregator.sol";
import { IMockOracle } from "./interfaces/IMockOracle.sol";
import { IMockPool } from "./interfaces/IMockPool.sol";

/**
 * @title YieldAggregator
 * @author Zoll - YieldSync Team
 * @notice Aggregator contract that manages pool allocation and yield optimization
 * @dev Automatically allocates funds to highest yielding pools and rebalances based on APY changes
 *
 * This contract implements the core yield aggregation logic:
 * - Tracks multiple liquidity pools and their APYs
 * - Automatically allocates funds to best performing pools
 * - Rebalances allocations when APY changes occur
 * - Supports dynamic pool addition/removal
 * - Implements slippage protection for rebalancing
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
contract YieldAggregator is IYieldAggregator, ReentrancyGuard, AccessControl, Pausable {
    using SafeERC20 for IERC20;

    // ============ Errors ============
    error YieldAggregator__PoolNotFound(address poolAddress);
    error YieldAggregator__InvalidAllocation();
    error YieldAggregator__ReallocationFailed();
    error YieldAggregator__Unauthorized();
    error YieldAggregator__InvalidAddress();
    error YieldAggregator__PoolAlreadyExists();
    error YieldAggregator__InvalidAPY();
    error YieldAggregator__InsufficientFunds();
    error YieldAggregator__SlippageExceeded();
    error YieldAggregator__InvalidAmount();

    // ============ Type declarations ============

    struct RebalanceParams {
        uint256 minSlippage; // Minimum slippage tolerance
        uint256 maxSlippage; // Maximum slippage tolerance
        uint256 rebalanceThreshold; // Minimum APY difference to trigger rebalance
    }

    // ============ State variables ============
    /// @notice The underlying asset token
    IERC20 public immutable asset;

    /// @notice The mock oracle for APY data
    IMockOracle public immutable oracle;

    /// @notice The vault contract address
    address public immutable vault;

    /// @notice Role identifier for managers
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice Role identifier for the vault contract
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");

    /// @notice Basis points for percentage calculations
    uint256 public constant BASIS_POINTS = 10_000;

    /// @notice Maximum number of pools to prevent gas issues
    uint256 public constant MAX_POOLS = 20;

    /// @notice Minimum APY difference to trigger rebalance (1% = 100 basis points)
    uint256 public constant MIN_REBALANCE_THRESHOLD = 100;

    /// @notice Default slippage tolerance (0.5% = 50 basis points)
    uint256 public constant DEFAULT_SLIPPAGE = 50;

    /// @notice Array of all pool addresses
    address[] private s_poolAddresses;

    /// @notice Mapping of pool address to pool information
    mapping(address => PoolInfo) private s_poolInfo;

    /// @notice Total assets allocated across all pools
    uint256 private s_totalAllocated;

    /// @notice Rebalance parameters
    RebalanceParams private s_rebalanceParams;

    /// @notice Last rebalance timestamp
    uint256 private s_lastRebalanceTime;

    /// @notice Rebalance cooldown period (1 hour)
    uint256 private s_rebalanceCooldown = 1 hours;

    /// @notice Pool allocation limits (basis points)
    uint256 private s_maxPoolAllocation = 5000; // 50% max per pool

    /// @notice Minimum allocation amount to prevent dust
    uint256 private s_minAllocation = 1000; // Minimum 1000 wei

    // ============ Events ============
    event PoolAdded(address indexed poolAddress, uint256 initialApy);
    event PoolUpdated(address indexed poolAddress, uint256 newApy);
    event PoolRemoved(address indexed poolAddress);
    event FundsAllocated(address indexed poolAddress, uint256 amount);
    event FundsReallocated(address indexed fromPool, address indexed toPool, uint256 amount);
    event RebalanceCompleted(uint256 totalAllocated, uint256 timestamp);
    event RebalanceParametersUpdated(uint256 minSlippage, uint256 maxSlippage, uint256 threshold);
    event AllocationLimitsUpdated(uint256 maxPoolAllocation, uint256 minAllocation);

    // ============ Modifiers ============
    modifier onlyManager() {
        if (!hasRole(MANAGER_ROLE, msg.sender)) {
            revert YieldAggregator__Unauthorized();
        }
        _;
    }

    modifier onlyVault() {
        if (!hasRole(VAULT_ROLE, msg.sender)) {
            revert YieldAggregator__Unauthorized();
        }
        _;
    }

    modifier validPool(address poolAddress) {
        if (!s_poolInfo[poolAddress].isActive) {
            revert YieldAggregator__PoolNotFound(poolAddress);
        }
        _;
    }

    modifier validAddress(address addr) {
        if (addr == address(0)) {
            revert YieldAggregator__InvalidAddress();
        }
        _;
    }

    modifier validAmount(uint256 amount) {
        if (amount == 0) {
            revert YieldAggregator__InvalidAmount();
        }
        _;
    }

    // ============ Constructor ============
    /**
     * @notice Initialize the YieldAggregator contract
     * @param _asset The underlying asset token
     * @param _oracle The mock oracle contract
     * @param _vault The vault contract address
     */
    constructor(
        address _asset,
        address _oracle,
        address _vault
    )
        validAddress(_asset)
        validAddress(_oracle)
        validAddress(_vault)
    {
        asset = IERC20(_asset);
        oracle = IMockOracle(_oracle);
        vault = _vault;

        // Initialize rebalance parameters
        s_rebalanceParams = RebalanceParams({
            minSlippage: 10, // 0.1%
            maxSlippage: 200, // 2%
            rebalanceThreshold: MIN_REBALANCE_THRESHOLD
        });

        s_lastRebalanceTime = block.timestamp;

        // Grant roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, msg.sender);
        _grantRole(VAULT_ROLE, _vault);
    }

    // ============ External Functions ============
    /**
     * @notice Allocate funds to the best performing pools
     * @param amount The total amount to allocate
     */
    function allocateFunds(uint256 amount)
        external
        override
        onlyVault
        nonReentrant
        whenNotPaused
        validAmount(amount)
    {
        // Update pool APYs from oracle
        _updatePoolAPYs();

        // Get best pool for allocation
        (address bestPool,) = getBestPool();

        if (bestPool == address(0)) {
            revert YieldAggregator__PoolNotFound(address(0));
        }

        // Check allocation limits
        uint256 maxAllowedAllocation =
            (s_totalAllocated + amount) * s_maxPoolAllocation / BASIS_POINTS;
        uint256 currentAllocation = s_poolInfo[bestPool].allocation;

        if (currentAllocation + amount > maxAllowedAllocation) {
            // Distribute across multiple pools if single pool allocation would exceed limit
            _distributeAcrossPools(amount);
        } else {
            // Allocate to best pool
            _allocateToPool(bestPool, amount);
        }

        s_totalAllocated += amount;
    }

    /**
     * @notice Rebalance funds across pools based on current APYs
     */
    function rebalancePools() external override nonReentrant whenNotPaused {
        // Check cooldown period
        if (block.timestamp < s_lastRebalanceTime + s_rebalanceCooldown) {
            return; // Skip rebalance if in cooldown
        }

        // Update APYs from oracle
        _updatePoolAPYs();

        // Get current best pool
        (address bestPool, uint256 bestAPY) = getBestPool();

        if (bestPool == address(0)) {
            return; // No active pools
        }

        // Check if rebalancing is needed
        bool needsRebalance = false;
        uint256 totalReallocation = 0;

        // Calculate potential reallocations
        for (uint256 i = 0; i < s_poolAddresses.length; i++) {
            address poolAddress = s_poolAddresses[i];
            PoolInfo storage poolInfo = s_poolInfo[poolAddress];

            if (!poolInfo.isActive || poolInfo.allocation == 0) continue;

            // Check if APY difference is significant enough
            if (bestAPY > poolInfo.apy + s_rebalanceParams.rebalanceThreshold) {
                needsRebalance = true;

                // Calculate amount to reallocate (partial reallocation for gas efficiency)
                uint256 reallocationAmount = poolInfo.allocation / 2; // Reallocate 50%

                if (reallocationAmount >= s_minAllocation) {
                    totalReallocation += reallocationAmount;
                    _reallocateFromPool(poolAddress, bestPool, reallocationAmount);
                }
            }
        }

        if (needsRebalance) {
            s_lastRebalanceTime = block.timestamp;
            emit RebalanceCompleted(s_totalAllocated, block.timestamp);
        }
    }

    // ============ Pool Management Functions ============
    /**
     * @notice Add a new pool to the aggregator
     * @param poolAddress The address of the pool to add
     * @param initialAPY The initial APY of the pool
     */
    function addPool(
        address poolAddress,
        uint256 initialAPY
    )
        external
        onlyManager
        validAddress(poolAddress)
    {
        // Check if pool already exists
        if (s_poolInfo[poolAddress].isActive) {
            revert YieldAggregator__PoolAlreadyExists();
        }

        // Check maximum pools limit
        if (s_poolAddresses.length >= MAX_POOLS) {
            revert YieldAggregator__InvalidAllocation();
        }

        // Validate APY
        if (initialAPY > 50_000) {
            // Max 500% APY
            revert YieldAggregator__InvalidAPY();
        }

        // Add pool
        s_poolAddresses.push(poolAddress);
        s_poolInfo[poolAddress] = PoolInfo({
            poolAddress: poolAddress,
            apy: initialAPY,
            allocation: 0,
            lastUpdated: block.timestamp,
            isActive: true
        });

        emit PoolAdded(poolAddress, initialAPY);
    }

    /**
     * @notice Remove a pool from the aggregator
     * @param poolAddress The address of the pool to remove
     */
    function removePool(address poolAddress) external onlyManager validPool(poolAddress) {
        PoolInfo storage poolInfo = s_poolInfo[poolAddress];

        // Withdraw all funds from pool if any
        if (poolInfo.allocation > 0) {
            _withdrawFromPool(poolAddress, poolInfo.allocation);
        }

        // Mark pool as inactive
        poolInfo.isActive = false;

        // Remove from array
        for (uint256 i = 0; i < s_poolAddresses.length; i++) {
            if (s_poolAddresses[i] == poolAddress) {
                s_poolAddresses[i] = s_poolAddresses[s_poolAddresses.length - 1];
                s_poolAddresses.pop();
                break;
            }
        }

        emit PoolRemoved(poolAddress);
    }

    /**
     * @notice Update rebalance parameters
     * @param minSlippage Minimum slippage tolerance
     * @param maxSlippage Maximum slippage tolerance
     * @param threshold Minimum APY difference to trigger rebalance
     */
    function updateRebalanceParameters(
        uint256 minSlippage,
        uint256 maxSlippage,
        uint256 threshold
    )
        external
        onlyManager
    {
        if (minSlippage > maxSlippage || maxSlippage > 1000) {
            // Max 10% slippage
            revert YieldAggregator__InvalidAllocation();
        }

        s_rebalanceParams = RebalanceParams({
            minSlippage: minSlippage,
            maxSlippage: maxSlippage,
            rebalanceThreshold: threshold
        });

        emit RebalanceParametersUpdated(minSlippage, maxSlippage, threshold);
    }

    /**
     * @notice Update allocation limits
     * @param maxPoolAllocation Maximum allocation per pool (basis points)
     * @param minAllocation Minimum allocation amount
     */
    function updateAllocationLimits(
        uint256 maxPoolAllocation,
        uint256 minAllocation
    )
        external
        onlyManager
    {
        if (maxPoolAllocation > BASIS_POINTS) {
            revert YieldAggregator__InvalidAllocation();
        }

        s_maxPoolAllocation = maxPoolAllocation;
        s_minAllocation = minAllocation;

        emit AllocationLimitsUpdated(maxPoolAllocation, minAllocation);
    }

    /**
     * @notice Emergency withdraw from all pools
     * @dev Only callable by managers in emergency situations
     */
    function emergencyWithdrawAll() external onlyManager {
        for (uint256 i = 0; i < s_poolAddresses.length; i++) {
            address poolAddress = s_poolAddresses[i];
            PoolInfo storage poolInfo = s_poolInfo[poolAddress];

            if (poolInfo.isActive && poolInfo.allocation > 0) {
                _withdrawFromPool(poolAddress, poolInfo.allocation);
            }
        }

        // Transfer all assets back to vault
        uint256 balance = asset.balanceOf(address(this));
        if (balance > 0) {
            asset.safeTransfer(vault, balance);
        }
    }

    /**
     * @notice Pause the aggregator
     */
    function pause() external onlyManager {
        _pause();
    }

    /**
     * @notice Unpause the aggregator
     */
    function unpause() external onlyManager {
        _unpause();
    }

    // ============ Public Functions ============
    /**
     * @notice Get the best pool for allocation
     * @return poolAddress The address of the best performing pool
     * @return apy The APY of the best performing pool
     */
    function getBestPool() public view override returns (address poolAddress, uint256 apy) {
        uint256 bestAPY = 0;
        address bestPool = address(0);

        for (uint256 i = 0; i < s_poolAddresses.length; i++) {
            address currentPool = s_poolAddresses[i];
            PoolInfo memory poolInfo = s_poolInfo[currentPool];

            if (poolInfo.isActive && poolInfo.apy > bestAPY) {
                bestAPY = poolInfo.apy;
                bestPool = currentPool;
            }
        }

        return (bestPool, bestAPY);
    }

    /**
     * @notice Get information about a specific pool
     * @param poolAddress The address of the pool
     * @return poolInfo The pool information struct
     */
    function getPoolInfo(address poolAddress)
        external
        view
        override
        returns (PoolInfo memory poolInfo)
    {
        poolInfo = s_poolInfo[poolAddress];
    }

    /**
     * @notice Get all active pools
     * @return pools Array of active pool addresses
     */
    function getActivePools() public view override returns (address[] memory pools) {
        uint256 activeCount = 0;

        // Count active pools
        for (uint256 i = 0; i < s_poolAddresses.length; i++) {
            if (s_poolInfo[s_poolAddresses[i]].isActive) {
                activeCount++;
            }
        }

        // Create array of active pools
        pools = new address[](activeCount);
        uint256 index = 0;

        for (uint256 i = 0; i < s_poolAddresses.length; i++) {
            if (s_poolInfo[s_poolAddresses[i]].isActive) {
                pools[index] = s_poolAddresses[i];
                index++;
            }
        }
    }

    // ============ Internal Functions ============
    /**
     * @notice Update APYs for all pools from oracle
     */
    function _updatePoolAPYs() internal {
        for (uint256 i = 0; i < s_poolAddresses.length; i++) {
            address poolAddress = s_poolAddresses[i];
            PoolInfo storage poolInfo = s_poolInfo[poolAddress];

            if (poolInfo.isActive) {
                try oracle.getPoolAPY(poolAddress) returns (uint256 newAPY) {
                    if (newAPY != poolInfo.apy) {
                        poolInfo.apy = newAPY;
                        poolInfo.lastUpdated = block.timestamp;
                        emit PoolUpdated(poolAddress, newAPY);
                    }
                } catch {
                    // Handle oracle error gracefully
                    continue;
                }
            }
        }
    }

    /**
     * @notice Allocate funds to a specific pool
     * @param poolAddress The pool address
     * @param amount The amount to allocate
     */
    function _allocateToPool(address poolAddress, uint256 amount) internal {
        PoolInfo storage poolInfo = s_poolInfo[poolAddress];

        // Transfer funds to pool
        asset.safeTransfer(poolAddress, amount);

        // Deposit into pool
        IMockPool(poolAddress).deposit(amount);

        // Update allocation
        poolInfo.allocation += amount;

        emit FundsAllocated(poolAddress, amount);
    }

    /**
     * @notice Withdraw funds from a specific pool
     * @param poolAddress The pool address
     * @param amount The amount to withdraw
     */
    function _withdrawFromPool(address poolAddress, uint256 amount) internal {
        PoolInfo storage poolInfo = s_poolInfo[poolAddress];

        // Withdraw from pool
        IMockPool(poolAddress).withdraw(amount);

        // Update allocation
        poolInfo.allocation -= amount;
        s_totalAllocated -= amount;
    }

    /**
     * @notice Reallocate funds from one pool to another
     * @param fromPool The source pool
     * @param toPool The destination pool
     * @param amount The amount to reallocate
     */
    function _reallocateFromPool(address fromPool, address toPool, uint256 amount) internal {
        // Withdraw from source pool
        _withdrawFromPool(fromPool, amount);

        // Allocate to destination pool
        _allocateToPool(toPool, amount);

        emit FundsReallocated(fromPool, toPool, amount);
    }

    /**
     * @notice Distribute funds across multiple pools when single pool limit exceeded
     * @param amount The total amount to distribute
     */
    function _distributeAcrossPools(uint256 amount) internal {
        // Get sorted pools by APY (descending)
        address[] memory sortedPools = _getSortedPoolsByAPY();

        uint256 remainingAmount = amount;
        uint256 totalAllocatedAfter = s_totalAllocated + amount;

        for (uint256 i = 0; i < sortedPools.length && remainingAmount > 0; i++) {
            address poolAddress = sortedPools[i];
            PoolInfo storage poolInfo = s_poolInfo[poolAddress];

            if (!poolInfo.isActive) continue;

            // Calculate maximum allocation for this pool
            uint256 maxAllowedForPool = (totalAllocatedAfter * s_maxPoolAllocation) / BASIS_POINTS;
            uint256 availableCapacity = maxAllowedForPool > poolInfo.allocation
                ? maxAllowedForPool - poolInfo.allocation
                : 0;

            if (availableCapacity >= s_minAllocation) {
                uint256 allocationAmount =
                    remainingAmount < availableCapacity ? remainingAmount : availableCapacity;

                _allocateToPool(poolAddress, allocationAmount);
                remainingAmount -= allocationAmount;
            }
        }

        // If there's still remaining amount, allocate to best pool regardless of limit
        if (remainingAmount > 0) {
            (address bestPool,) = getBestPool();
            if (bestPool != address(0)) {
                _allocateToPool(bestPool, remainingAmount);
            }
        }
    }

    /**
     * @notice Get pools sorted by APY in descending order
     * @return sortedPools Array of pool addresses sorted by APY
     */
    function _getSortedPoolsByAPY() internal view returns (address[] memory sortedPools) {
        address[] memory activePools = getActivePools();
        uint256 length = activePools.length;

        // Simple bubble sort for small arrays
        for (uint256 i = 0; i < length; i++) {
            for (uint256 j = 0; j < length - i - 1; j++) {
                if (s_poolInfo[activePools[j]].apy < s_poolInfo[activePools[j + 1]].apy) {
                    address temp = activePools[j];
                    activePools[j] = activePools[j + 1];
                    activePools[j + 1] = temp;
                }
            }
        }

        return activePools;
    }

    // ============ View Functions ============
    /**
     * @notice Get total allocated assets
     * @return totalAllocated The total amount allocated across all pools
     */
    function getTotalAllocated() external view returns (uint256 totalAllocated) {
        totalAllocated = s_totalAllocated;
    }

    /**
     * @notice Get rebalance parameters
     * @return params The current rebalance parameters
     */
    function getRebalanceParameters() external view returns (RebalanceParams memory params) {
        params = s_rebalanceParams;
    }

    /**
     * @notice Get allocation limits
     * @return maxPoolAllocation The maximum allocation per pool
     * @return minAllocation The minimum allocation amount
     */
    function getAllocationLimits()
        external
        view
        returns (uint256 maxPoolAllocation, uint256 minAllocation)
    {
        maxPoolAllocation = s_maxPoolAllocation;
        minAllocation = s_minAllocation;
    }

    /**
     * @notice Get last rebalance time
     * @return lastRebalanceTime The timestamp of the last rebalance
     */
    function getLastRebalanceTime() external view returns (uint256 lastRebalanceTime) {
        lastRebalanceTime = s_lastRebalanceTime;
    }

    /**
     * @notice Get rebalance cooldown period
     * @return cooldown The cooldown period in seconds
     */
    function getRebalanceCooldown() external view returns (uint256 cooldown) {
        cooldown = s_rebalanceCooldown;
    }

    /**
     * @notice Check if rebalance is needed
     * @return needed Whether rebalance is needed
     * @return reason The reason for rebalance (0: no rebalance, 1: APY diff, 2: time passed)
     */
    function isRebalanceNeeded() external view returns (bool needed, uint256 reason) {
        // Check cooldown
        if (block.timestamp < s_lastRebalanceTime + s_rebalanceCooldown) {
            return (false, 0);
        }

        // Get best pool
        (address bestPool, uint256 bestAPY) = getBestPool();
        if (bestPool == address(0)) {
            return (false, 0);
        }

        // Check APY differences
        for (uint256 i = 0; i < s_poolAddresses.length; i++) {
            address poolAddress = s_poolAddresses[i];
            PoolInfo memory poolInfo = s_poolInfo[poolAddress];

            if (poolInfo.isActive && poolInfo.allocation > 0) {
                if (bestAPY > poolInfo.apy + s_rebalanceParams.rebalanceThreshold) {
                    return (true, 1);
                }
            }
        }

        return (false, 0);
    }

    /**
     * @notice Get pool count
     * @return totalPools Total number of pools
     * @return activePools Number of active pools
     */
    function getPoolCount() external view returns (uint256 totalPools, uint256 activePools) {
        totalPools = s_poolAddresses.length;

        for (uint256 i = 0; i < s_poolAddresses.length; i++) {
            if (s_poolInfo[s_poolAddresses[i]].isActive) {
                activePools++;
            }
        }
    }

    /**
     * @notice Get pool allocation percentage
     * @param poolAddress The pool address
     * @return percentage The allocation percentage (basis points)
     */
    function getPoolAllocationPercentage(address poolAddress)
        external
        view
        returns (uint256 percentage)
    {
        if (s_totalAllocated == 0) {
            return 0;
        }

        percentage = (s_poolInfo[poolAddress].allocation * BASIS_POINTS) / s_totalAllocated;
    }

    /**
     * @notice Get all pool information
     * @return poolInfos Array of all pool information
     */
    function getAllPoolInfo() external view returns (PoolInfo[] memory poolInfos) {
        poolInfos = new PoolInfo[](s_poolAddresses.length);

        for (uint256 i = 0; i < s_poolAddresses.length; i++) {
            poolInfos[i] = s_poolInfo[s_poolAddresses[i]];
        }
    }

    /**
     * @notice Preview allocation distribution for a given amount
     * @param amount The amount to preview allocation for
     * @return pools Array of pool addresses
     * @return allocations Array of allocation amounts
     */
    function previewAllocation(uint256 amount)
        external
        view
        returns (address[] memory pools, uint256[] memory allocations)
    {
        (address bestPool,) = getBestPool();

        if (bestPool == address(0)) {
            return (new address[](0), new uint256[](0));
        }

        // Simple case: allocate to best pool if within limits
        uint256 maxAllowedAllocation =
            (s_totalAllocated + amount) * s_maxPoolAllocation / BASIS_POINTS;
        uint256 currentAllocation = s_poolInfo[bestPool].allocation;

        if (currentAllocation + amount <= maxAllowedAllocation) {
            pools = new address[](1);
            allocations = new uint256[](1);
            pools[0] = bestPool;
            allocations[0] = amount;
        } else {
            // Complex case: distribute across pools
            address[] memory sortedPools = _getSortedPoolsByAPY();
            uint256 activePoolCount = 0;

            // Count pools that can receive allocation
            for (uint256 i = 0; i < sortedPools.length; i++) {
                if (s_poolInfo[sortedPools[i]].isActive) {
                    activePoolCount++;
                }
            }

            pools = new address[](activePoolCount);
            allocations = new uint256[](activePoolCount);

            uint256 remainingAmount = amount;
            uint256 totalAllocatedAfter = s_totalAllocated + amount;
            uint256 index = 0;

            for (uint256 i = 0; i < sortedPools.length && remainingAmount > 0; i++) {
                address poolAddress = sortedPools[i];
                PoolInfo memory poolInfo = s_poolInfo[poolAddress];

                if (!poolInfo.isActive) continue;

                uint256 maxAllowedForPool =
                    (totalAllocatedAfter * s_maxPoolAllocation) / BASIS_POINTS;
                uint256 availableCapacity = maxAllowedForPool > poolInfo.allocation
                    ? maxAllowedForPool - poolInfo.allocation
                    : 0;

                if (availableCapacity >= s_minAllocation) {
                    uint256 allocationAmount =
                        remainingAmount < availableCapacity ? remainingAmount : availableCapacity;

                    pools[index] = poolAddress;
                    allocations[index] = allocationAmount;
                    remainingAmount -= allocationAmount;
                    index++;
                }
            }

            // Resize arrays to actual size
            assembly {
                mstore(pools, index)
                mstore(allocations, index)
            }
        }
    }

    /**
     * @notice Get estimated yield for a given amount and duration
     * @param amount The amount to calculate yield for
     * @param duration The duration in seconds
     * @return estimatedYield The estimated yield amount
     */
    function getEstimatedYield(
        uint256 amount,
        uint256 duration
    )
        external
        view
        returns (uint256 estimatedYield)
    {
        (address bestPool, uint256 bestAPY) = getBestPool();

        if (bestPool == address(0)) {
            return 0;
        }

        // Calculate annual yield: (amount * APY) / BASIS_POINTS
        uint256 annualYield = (amount * bestAPY) / BASIS_POINTS;

        // Calculate yield for given duration
        estimatedYield = (annualYield * duration) / 365 days;
    }
}
