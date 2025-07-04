// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IFeeOptimizer } from "./interfaces/IFeeOptimizer.sol";
import { IMockOracle } from "./interfaces/IMockOracle.sol";

/**
 * @title FeeOptimizer
 * @author Zoll - YieldSync Team
 * @notice Dynamic fee optimizer that adjusts fees based on BlockDAG network conditions
 * @dev Implements dynamic fee adjustment based on gas prices and network congestion
 *
 * This contract optimizes fees by:
 * - Monitoring real-time gas prices from oracle
 * - Tracking network congestion levels
 * - Adjusting fees between min/max bounds
 * - Providing smooth fee transitions to prevent sudden spikes
 * - Supporting different fee models for different operations
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
contract FeeOptimizer is IFeeOptimizer, AccessControl, Pausable {
    // ============ Errors ============
    error FeeOptimizer__InvalidFeeRange();
    error FeeOptimizer__OracleError();
    error FeeOptimizer__Unauthorized();
    error FeeOptimizer__InvalidAddress();
    error FeeOptimizer__InvalidParameters();
    error FeeOptimizer__FeeUpdateTooFrequent();
    error FeeOptimizer__InvalidCongestionLevel();

    // ============ Type declarations ============
    struct FeeParameters {
        uint256 minFee; // Minimum fee in basis points (0.1% = 10)
        uint256 maxFee; // Maximum fee in basis points (1% = 100)
        uint256 baseFee; // Base fee in basis points (0.5% = 50)
        uint256 targetGasPrice; // Target gas price for optimal fees
        uint256 congestionMultiplier; // Multiplier for congestion-based adjustment
    }

    struct FeeAdjustmentConfig {
        uint256 gasThresholdLow; // Gas price below which fees decrease
        uint256 gasThresholdHigh; // Gas price above which fees increase
        uint256 congestionThresholdLow; // Congestion level below which fees decrease
        uint256 congestionThresholdHigh; // Congestion level above which fees increase
        uint256 adjustmentFactor; // Factor for fee adjustment calculations
        uint256 maxAdjustmentPct; // Maximum adjustment percentage per update
    }

    struct FeeHistory {
        uint256 fee; // Fee amount
        uint256 gasPrice; // Gas price at time of fee
        uint256 congestionLevel; // Congestion level at time of fee
        uint256 timestamp; // Timestamp of fee update
    }

    // ============ State variables ============
    /// @notice The mock oracle contract
    IMockOracle public immutable oracle;

    /// @notice Role identifier for managers
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice Basis points for percentage calculations
    uint256 public constant BASIS_POINTS = 10_000;

    /// @notice Maximum fee update frequency (1 minute)
    uint256 public constant MIN_UPDATE_INTERVAL = 1 minutes;

    /// @notice Fee history length
    uint256 public constant FEE_HISTORY_LENGTH = 100;

    /// @notice Current fee parameters
    FeeParameters private s_feeParameters;

    /// @notice Fee adjustment configuration
    FeeAdjustmentConfig private s_adjustmentConfig;

    /// @notice Current fee in basis points
    uint256 private s_currentFee;

    /// @notice Last fee update timestamp
    uint256 private s_lastUpdateTime;

    /// @notice Fee history for analysis
    FeeHistory[] private s_feeHistory;

    /// @notice Fee smoothing factor (0-1000, where 1000 = no smoothing)
    uint256 private s_smoothingFactor;

    /// @notice Emergency fee override
    uint256 private s_emergencyFee;

    /// @notice Emergency mode flag
    bool private s_emergencyMode;

    /// @notice Different fee types for different operations
    mapping(bytes32 => uint256) private s_operationFees;

    /// @notice Fee multipliers for different user tiers
    mapping(address => uint256) private s_userFeeMultipliers;

    /// @notice Total fees collected
    uint256 private s_totalFeesCollected;

    // ============ Events ============
    event FeeUpdated(uint256 newFee, uint256 gasPrice, uint256 networkCongestion);
    event FeeParametersUpdated(uint256 minFee, uint256 maxFee, uint256 targetGasPrice);
    event FeeAdjustmentConfigUpdated(
        uint256 gasThresholdLow,
        uint256 gasThresholdHigh,
        uint256 congestionThresholdLow,
        uint256 congestionThresholdHigh
    );
    event EmergencyModeToggled(bool enabled, uint256 emergencyFee);
    event OperationFeeSet(bytes32 indexed operation, uint256 fee);
    event UserFeeMultiplierSet(address indexed user, uint256 multiplier);
    event SmoothingFactorUpdated(uint256 newFactor);

    // ============ Modifiers ============
    modifier onlyManager() {
        if (!hasRole(MANAGER_ROLE, msg.sender)) {
            revert FeeOptimizer__Unauthorized();
        }
        _;
    }

    modifier validAddress(address addr) {
        if (addr == address(0)) {
            revert FeeOptimizer__InvalidAddress();
        }
        _;
    }

    modifier notTooFrequent() {
        if (block.timestamp < s_lastUpdateTime + MIN_UPDATE_INTERVAL) {
            revert FeeOptimizer__FeeUpdateTooFrequent();
        }
        _;
    }

    // ============ Constructor ============
    /**
     * @notice Initialize the FeeOptimizer contract
     * @param _oracle The mock oracle contract address
     */
    constructor(address _oracle) validAddress(_oracle) {
        oracle = IMockOracle(_oracle);

        // Initialize default fee parameters
        s_feeParameters = FeeParameters({
            minFee: 10, // 0.1%
            maxFee: 100, // 1%
            baseFee: 50, // 0.5%
            targetGasPrice: 20 gwei,
            congestionMultiplier: 150 // 1.5x multiplier
         });

        // Initialize adjustment configuration
        s_adjustmentConfig = FeeAdjustmentConfig({
            gasThresholdLow: 10 gwei,
            gasThresholdHigh: 50 gwei,
            congestionThresholdLow: 30, // 30% congestion
            congestionThresholdHigh: 70, // 70% congestion
            adjustmentFactor: 100, // 1% adjustment factor
            maxAdjustmentPct: 500 // 5% max adjustment
         });

        // Set initial values
        s_currentFee = s_feeParameters.baseFee;
        s_lastUpdateTime = block.timestamp;
        s_smoothingFactor = 800; // 80% smoothing

        // Grant roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, msg.sender);
    }

    // ============ External Functions ============
    /**
     * @notice Get the current optimal fee based on network conditions
     * @return fee The current fee in basis points
     */
    function getCurrentFee() external view override returns (uint256 fee) {
        if (s_emergencyMode) {
            return s_emergencyFee;
        }

        return s_currentFee;
    }

    /**
     * @notice Update fee based on current network conditions
     */
    function updateFee() external override whenNotPaused notTooFrequent {
        if (s_emergencyMode) {
            return; // Skip updates in emergency mode
        }

        // Get current network conditions
        uint256 gasPrice;
        uint256 congestionLevel;

        try oracle.getGasPrice() returns (uint256 currentGasPrice) {
            gasPrice = currentGasPrice;
        } catch {
            revert FeeOptimizer__OracleError();
        }

        try oracle.getNetworkCongestion() returns (uint256 currentCongestion) {
            congestionLevel = currentCongestion;
        } catch {
            revert FeeOptimizer__OracleError();
        }

        // Calculate new fee
        uint256 newFee = _calculateOptimalFee(gasPrice, congestionLevel);

        // Apply smoothing
        newFee = _applySmoothingFactor(s_currentFee, newFee);

        // Update current fee
        s_currentFee = newFee;
        s_lastUpdateTime = block.timestamp;

        // Record in history
        _recordFeeHistory(newFee, gasPrice, congestionLevel);

        emit FeeUpdated(newFee, gasPrice, congestionLevel);
    }

    /**
     * @notice Calculate fee for a specific transaction amount
     * @param amount The transaction amount
     * @return feeAmount The fee amount to be charged
     */
    function calculateFee(uint256 amount) external view override returns (uint256 feeAmount) {
        uint256 currentFee = s_emergencyMode ? s_emergencyFee : s_currentFee;
        feeAmount = (amount * currentFee) / BASIS_POINTS;
    }

    /**
     * @notice Calculate fee for a specific operation and user
     * @param amount The transaction amount
     * @param operation The operation identifier
     * @param user The user address
     * @return feeAmount The fee amount to be charged
     */
    function calculateFeeForOperation(
        uint256 amount,
        bytes32 operation,
        address user
    )
        external
        view
        returns (uint256 feeAmount)
    {
        uint256 baseFee = s_emergencyMode ? s_emergencyFee : s_currentFee;

        // Apply operation-specific fee if set
        uint256 operationFee = s_operationFees[operation];
        if (operationFee > 0) {
            baseFee = operationFee;
        }

        // Apply user multiplier if set
        uint256 userMultiplier = s_userFeeMultipliers[user];
        if (userMultiplier > 0) {
            baseFee = (baseFee * userMultiplier) / BASIS_POINTS;
        }

        feeAmount = (amount * baseFee) / BASIS_POINTS;
    }

    /**
     * @notice Set fee parameters
     * @param minFee Minimum fee in basis points
     * @param maxFee Maximum fee in basis points
     * @param baseFee Base fee in basis points
     * @param targetGasPrice Target gas price for optimal fees
     * @param congestionMultiplier Multiplier for congestion-based adjustment
     */
    function setFeeParameters(
        uint256 minFee,
        uint256 maxFee,
        uint256 baseFee,
        uint256 targetGasPrice,
        uint256 congestionMultiplier
    )
        external
        onlyManager
    {
        if (minFee >= maxFee || maxFee > 1000) {
            // Max 10% fee
            revert FeeOptimizer__InvalidFeeRange();
        }

        if (baseFee < minFee || baseFee > maxFee) {
            revert FeeOptimizer__InvalidParameters();
        }

        s_feeParameters = FeeParameters({
            minFee: minFee,
            maxFee: maxFee,
            baseFee: baseFee,
            targetGasPrice: targetGasPrice,
            congestionMultiplier: congestionMultiplier
        });

        emit FeeParametersUpdated(minFee, maxFee, targetGasPrice);
    }

    /**
     * @notice Set fee adjustment configuration
     * @param gasThresholdLow Gas price threshold for fee decrease
     * @param gasThresholdHigh Gas price threshold for fee increase
     * @param congestionThresholdLow Congestion threshold for fee decrease
     * @param congestionThresholdHigh Congestion threshold for fee increase
     * @param adjustmentFactor Factor for fee adjustment calculations
     * @param maxAdjustmentPct Maximum adjustment percentage per update
     */
    function setFeeAdjustmentConfig(
        uint256 gasThresholdLow,
        uint256 gasThresholdHigh,
        uint256 congestionThresholdLow,
        uint256 congestionThresholdHigh,
        uint256 adjustmentFactor,
        uint256 maxAdjustmentPct
    )
        external
        onlyManager
    {
        if (gasThresholdLow >= gasThresholdHigh) {
            revert FeeOptimizer__InvalidParameters();
        }

        if (congestionThresholdLow >= congestionThresholdHigh || congestionThresholdHigh > 100) {
            revert FeeOptimizer__InvalidCongestionLevel();
        }

        s_adjustmentConfig = FeeAdjustmentConfig({
            gasThresholdLow: gasThresholdLow,
            gasThresholdHigh: gasThresholdHigh,
            congestionThresholdLow: congestionThresholdLow,
            congestionThresholdHigh: congestionThresholdHigh,
            adjustmentFactor: adjustmentFactor,
            maxAdjustmentPct: maxAdjustmentPct
        });

        emit FeeAdjustmentConfigUpdated(
            gasThresholdLow, gasThresholdHigh, congestionThresholdLow, congestionThresholdHigh
        );
    }

    /**
     * @notice Set operation-specific fee
     * @param operation The operation identifier
     * @param fee The fee in basis points
     */
    function setOperationFee(bytes32 operation, uint256 fee) external onlyManager {
        if (fee > s_feeParameters.maxFee) {
            revert FeeOptimizer__InvalidFeeRange();
        }

        s_operationFees[operation] = fee;
        emit OperationFeeSet(operation, fee);
    }

    /**
     * @notice Set user fee multiplier
     * @param user The user address
     * @param multiplier The multiplier in basis points (10000 = 1x)
     */
    function setUserFeeMultiplier(
        address user,
        uint256 multiplier
    )
        external
        onlyManager
        validAddress(user)
    {
        if (multiplier > 20_000) {
            // Max 2x multiplier
            revert FeeOptimizer__InvalidParameters();
        }

        s_userFeeMultipliers[user] = multiplier;
        emit UserFeeMultiplierSet(user, multiplier);
    }

    /**
     * @notice Set smoothing factor
     * @param factor The smoothing factor (0-1000, where 1000 = no smoothing)
     */
    function setSmoothingFactor(uint256 factor) external onlyManager {
        if (factor > 1000) {
            revert FeeOptimizer__InvalidParameters();
        }

        s_smoothingFactor = factor;
        emit SmoothingFactorUpdated(factor);
    }

    /**
     * @notice Toggle emergency mode
     * @param enabled Whether to enable emergency mode
     * @param emergencyFee The emergency fee to use
     */
    function toggleEmergencyMode(bool enabled, uint256 emergencyFee) external onlyManager {
        if (enabled && emergencyFee > s_feeParameters.maxFee) {
            revert FeeOptimizer__InvalidFeeRange();
        }

        s_emergencyMode = enabled;
        s_emergencyFee = emergencyFee;

        emit EmergencyModeToggled(enabled, emergencyFee);
    }

    /**
     * @notice Force fee update (bypasses frequency limit)
     */
    function forceFeeUpdate() external onlyManager {
        if (s_emergencyMode) {
            return;
        }

        // Get current network conditions
        uint256 gasPrice = oracle.getGasPrice();
        uint256 congestionLevel = oracle.getNetworkCongestion();

        // Calculate new fee
        uint256 newFee = _calculateOptimalFee(gasPrice, congestionLevel);

        // Update without smoothing for immediate effect
        s_currentFee = newFee;
        s_lastUpdateTime = block.timestamp;

        // Record in history
        _recordFeeHistory(newFee, gasPrice, congestionLevel);

        emit FeeUpdated(newFee, gasPrice, congestionLevel);
    }

    /**
     * @notice Pause the fee optimizer
     */
    function pause() external onlyManager {
        _pause();
    }

    /**
     * @notice Unpause the fee optimizer
     */
    function unpause() external onlyManager {
        _unpause();
    }

    // ============ Internal Functions ============
    /**
     * @notice Calculate optimal fee based on gas price and congestion
     * @param gasPrice Current gas price
     * @param congestionLevel Current congestion level
     * @return optimalFee The calculated optimal fee
     */
    function _calculateOptimalFee(
        uint256 gasPrice,
        uint256 congestionLevel
    )
        internal
        view
        returns (uint256 optimalFee)
    {
        FeeParameters memory params = s_feeParameters;
        FeeAdjustmentConfig memory config = s_adjustmentConfig;

        // Start with base fee
        optimalFee = params.baseFee;

        // Adjust based on gas price
        if (gasPrice < config.gasThresholdLow) {
            // Low gas price - decrease fee
            uint256 gasAdjustment = ((config.gasThresholdLow - gasPrice) * config.adjustmentFactor)
                / config.gasThresholdLow;
            optimalFee = optimalFee > gasAdjustment ? optimalFee - gasAdjustment : params.minFee;
        } else if (gasPrice > config.gasThresholdHigh) {
            // High gas price - increase fee
            uint256 gasAdjustment = ((gasPrice - config.gasThresholdHigh) * config.adjustmentFactor)
                / config.gasThresholdHigh;
            optimalFee += gasAdjustment;
        }

        // Adjust based on congestion
        if (congestionLevel < config.congestionThresholdLow) {
            // Low congestion - decrease fee
            uint256 congestionAdjustment =
                ((config.congestionThresholdLow - congestionLevel) * config.adjustmentFactor) / 100;
            optimalFee = optimalFee > congestionAdjustment
                ? optimalFee - congestionAdjustment
                : params.minFee;
        } else if (congestionLevel > config.congestionThresholdHigh) {
            // High congestion - increase fee
            uint256 congestionAdjustment =
                ((congestionLevel - config.congestionThresholdHigh) * config.adjustmentFactor) / 100;
            optimalFee += congestionAdjustment;
        }

        // Apply congestion multiplier for extreme congestion
        if (congestionLevel > 90) {
            optimalFee = (optimalFee * params.congestionMultiplier) / 100;
        }

        // Ensure fee is within bounds
        if (optimalFee < params.minFee) {
            optimalFee = params.minFee;
        } else if (optimalFee > params.maxFee) {
            optimalFee = params.maxFee;
        }

        // Apply maximum adjustment limit
        uint256 maxChange = (params.baseFee * config.maxAdjustmentPct) / BASIS_POINTS;
        if (optimalFee > params.baseFee + maxChange) {
            optimalFee = params.baseFee + maxChange;
        } else if (optimalFee < params.baseFee - maxChange) {
            optimalFee = params.baseFee - maxChange;
        }
    }

    /**
     * @notice Apply smoothing factor to fee changes
     * @param currentFee The current fee
     * @param newFee The newly calculated fee
     * @return smoothedFee The smoothed fee
     */
    function _applySmoothingFactor(
        uint256 currentFee,
        uint256 newFee
    )
        internal
        view
        returns (uint256 smoothedFee)
    {
        if (s_smoothingFactor == 1000) {
            return newFee; // No smoothing
        }

        // Apply exponential smoothing: smoothedFee = (1 - alpha) * currentFee + alpha * newFee
        // where alpha = (1000 - s_smoothingFactor) / 1000
        uint256 alpha = 1000 - s_smoothingFactor;
        smoothedFee = ((s_smoothingFactor * currentFee) + (alpha * newFee)) / 1000;
    }

    /**
     * @notice Record fee history for analysis
     * @param fee The fee amount
     * @param gasPrice The gas price
     * @param congestionLevel The congestion level
     */
    function _recordFeeHistory(uint256 fee, uint256 gasPrice, uint256 congestionLevel) internal {
        FeeHistory memory entry = FeeHistory({
            fee: fee,
            gasPrice: gasPrice,
            congestionLevel: congestionLevel,
            timestamp: block.timestamp
        });

        s_feeHistory.push(entry);

        // Keep only recent history
        if (s_feeHistory.length > FEE_HISTORY_LENGTH) {
            // Remove oldest entry
            for (uint256 i = 0; i < s_feeHistory.length - 1; i++) {
                s_feeHistory[i] = s_feeHistory[i + 1];
            }
            s_feeHistory.pop();
        }
    }

    // ============ View Functions ============
    /**
     * @notice Get current fee parameters
     * @return params The current fee parameters
     */
    function getFeeParameters() external view returns (FeeParameters memory params) {
        params = s_feeParameters;
    }

    /**
     * @notice Get fee adjustment configuration
     * @return config The current adjustment configuration
     */
    function getFeeAdjustmentConfig() external view returns (FeeAdjustmentConfig memory config) {
        config = s_adjustmentConfig;
    }

    /**
     * @notice Get operation-specific fee
     * @param operation The operation identifier
     * @return fee The operation fee in basis points
     */
    function getOperationFee(bytes32 operation) external view returns (uint256 fee) {
        fee = s_operationFees[operation];
    }

    /**
     * @notice Get user fee multiplier
     * @param user The user address
     * @return multiplier The user's fee multiplier
     */
    function getUserFeeMultiplier(address user) external view returns (uint256 multiplier) {
        multiplier = s_userFeeMultipliers[user];
    }

    /**
     * @notice Get smoothing factor
     * @return factor The current smoothing factor
     */
    function getSmoothingFactor() external view returns (uint256 factor) {
        factor = s_smoothingFactor;
    }

    /**
     * @notice Get emergency mode status
     * @return enabled Whether emergency mode is enabled
     * @return emergencyFee The emergency fee
     */
    function getEmergencyMode() external view returns (bool enabled, uint256 emergencyFee) {
        enabled = s_emergencyMode;
        emergencyFee = s_emergencyFee;
    }

    /**
     * @notice Get last update time
     * @return timestamp The last fee update timestamp
     */
    function getLastUpdateTime() external view returns (uint256 timestamp) {
        timestamp = s_lastUpdateTime;
    }

    /**
     * @notice Get fee history
     * @return history Array of fee history entries
     */
    function getFeeHistory() external view returns (FeeHistory[] memory history) {
        history = s_feeHistory;
    }

    /**
     * @notice Get recent fee history
     * @param count Number of recent entries to return
     * @return history Array of recent fee history entries
     */
    function getRecentFeeHistory(uint256 count)
        external
        view
        returns (FeeHistory[] memory history)
    {
        uint256 length = s_feeHistory.length;
        if (count > length) {
            count = length;
        }

        history = new FeeHistory[](count);
        for (uint256 i = 0; i < count; i++) {
            history[i] = s_feeHistory[length - count + i];
        }
    }

    /**
     * @notice Get fee statistics
     * @return avgFee Average fee over history
     * @return minFee Minimum fee in history
     * @return maxFee Maximum fee in history
     * @return volatility Fee volatility (standard deviation)
     */
    function getFeeStatistics()
        external
        view
        returns (uint256 avgFee, uint256 minFee, uint256 maxFee, uint256 volatility)
    {
        uint256 length = s_feeHistory.length;
        if (length == 0) {
            return (s_currentFee, s_currentFee, s_currentFee, 0);
        }

        uint256 sum = 0;
        minFee = type(uint256).max;
        maxFee = 0;

        // Calculate average, min, max
        for (uint256 i = 0; i < length; i++) {
            uint256 fee = s_feeHistory[i].fee;
            sum += fee;
            if (fee < minFee) minFee = fee;
            if (fee > maxFee) maxFee = fee;
        }

        avgFee = sum / length;

        // Calculate volatility (simplified standard deviation)
        uint256 variance = 0;
        for (uint256 i = 0; i < length; i++) {
            uint256 fee = s_feeHistory[i].fee;
            uint256 diff = fee > avgFee ? fee - avgFee : avgFee - fee;
            variance += diff * diff;
        }

        volatility = _sqrt(variance / length);
    }

    /**
     * @notice Predict fee for given network conditions
     * @param gasPrice The gas price to simulate
     * @param congestionLevel The congestion level to simulate
     * @return predictedFee The predicted fee
     */
    function predictFee(
        uint256 gasPrice,
        uint256 congestionLevel
    )
        external
        view
        returns (uint256 predictedFee)
    {
        predictedFee = _calculateOptimalFee(gasPrice, congestionLevel);
        predictedFee = _applySmoothingFactor(s_currentFee, predictedFee);
    }

    /**
     * @notice Get optimal fee parameters for current conditions
     * @return optimalMin Optimal minimum fee
     * @return optimalMax Optimal maximum fee
     * @return optimalBase Optimal base fee
     */
    function getOptimalFeeParameters()
        external
        view
        returns (uint256 optimalMin, uint256 optimalMax, uint256 optimalBase)
    {
        // Get current network conditions
        uint256 gasPrice = oracle.getGasPrice();
        uint256 congestionLevel = oracle.getNetworkCongestion();

        // Calculate optimal base fee
        optimalBase = _calculateOptimalFee(gasPrice, congestionLevel);

        // Calculate optimal range around base fee
        uint256 range = optimalBase / 5; // 20% range
        optimalMin = optimalBase > range ? optimalBase - range : s_feeParameters.minFee;
        optimalMax = optimalBase + range;

        // Ensure bounds
        if (optimalMin < s_feeParameters.minFee) optimalMin = s_feeParameters.minFee;
        if (optimalMax > s_feeParameters.maxFee) optimalMax = s_feeParameters.maxFee;
    }

    /**
     * @notice Check if fee update is needed
     * @return needed Whether fee update is needed
     * @return urgency Urgency level (0-100)
     */
    function isFeeUpdateNeeded() external view returns (bool needed, uint256 urgency) {
        if (s_emergencyMode) {
            return (false, 0);
        }

        // Check time since last update
        uint256 timeSinceUpdate = block.timestamp - s_lastUpdateTime;
        if (timeSinceUpdate < MIN_UPDATE_INTERVAL) {
            return (false, 0);
        }

        // Get current network conditions
        uint256 gasPrice = oracle.getGasPrice();
        uint256 congestionLevel = oracle.getNetworkCongestion();

        // Calculate what the fee should be
        uint256 optimalFee = _calculateOptimalFee(gasPrice, congestionLevel);

        // Check difference from current fee
        uint256 diff =
            optimalFee > s_currentFee ? optimalFee - s_currentFee : s_currentFee - optimalFee;
        uint256 changePercent = (diff * 100) / s_currentFee;

        if (changePercent > 2) {
            // 2% threshold
            needed = true;
            urgency = changePercent > 10 ? 100 : (changePercent * 10);
        }
    }

    /**
     * @notice Get total fees collected
     * @return totalFees The total fees collected
     */
    function getTotalFeesCollected() external view returns (uint256 totalFees) {
        totalFees = s_totalFeesCollected;
    }

    /**
     * @notice Calculate sqrt using Babylonian method
     * @param x The number to calculate sqrt for
     * @return y The square root
     */
    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    /**
     * @notice Get fee trend analysis
     * @return trend The fee trend (-1: decreasing, 0: stable, 1: increasing)
     * @return strength The strength of the trend (0-100)
     */
    function getFeeTrend() external view returns (int256 trend, uint256 strength) {
        uint256 length = s_feeHistory.length;
        if (length < 5) {
            return (0, 0);
        }

        // Compare recent fees with older fees
        uint256 recentAvg = 0;
        uint256 olderAvg = 0;
        uint256 recentCount = length / 3;
        uint256 olderCount = recentCount;

        // Calculate recent average
        for (uint256 i = length - recentCount; i < length; i++) {
            recentAvg += s_feeHistory[i].fee;
        }
        recentAvg /= recentCount;

        // Calculate older average
        for (uint256 i = 0; i < olderCount; i++) {
            olderAvg += s_feeHistory[i].fee;
        }
        olderAvg /= olderCount;

        // Determine trend
        if (recentAvg > olderAvg) {
            trend = 1;
            strength = ((recentAvg - olderAvg) * 100) / olderAvg;
        } else if (recentAvg < olderAvg) {
            trend = -1;
            strength = ((olderAvg - recentAvg) * 100) / olderAvg;
        } else {
            trend = 0;
            strength = 0;
        }

        // Cap strength at 100
        if (strength > 100) strength = 100;
    }
}
