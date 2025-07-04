// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IMockOracle } from "./interfaces/IMockOracle.sol";

/**
 * @title MockOracle
 * @author YieldSync Team
 * @notice Mock oracle contract for simulating real-time data feeds during testing
 * @dev Provides simulated APY, gas price, and network congestion data for hackathon testing
 *
 * This contract simulates a real oracle by:
 * - Providing mock APY data for different pools
 * - Simulating gas price fluctuations
 * - Tracking network congestion levels
 * - Supporting automatic data updates with randomization
 * - Allowing manual data updates for testing scenarios
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
contract MockOracle is IMockOracle, AccessControl, Pausable {
    // ============ Errors ============
    error MockOracle__InvalidData();
    error MockOracle__Unauthorized();
    error MockOracle__InvalidAddress();
    error MockOracle__PoolNotFound();
    error MockOracle__InvalidAPY();
    error MockOracle__InvalidGasPrice();
    error MockOracle__InvalidCongestionLevel();
    error MockOracle__UpdateTooFrequent();

    // ============ Type Declarations ============
    struct PoolData {
        uint256 apy; // Current APY in basis points
        uint256 baseAPY; // Base APY without fluctuations
        uint256 lastUpdated; // Last update timestamp
        uint256 volatility; // APY volatility factor
        bool isActive; // Whether pool is active
        uint256 minAPY; // Minimum APY
        uint256 maxAPY; // Maximum APY
    }

    struct NetworkData {
        uint256 gasPrice; // Current gas price
        uint256 congestionLevel; // Network congestion (0-100)
        uint256 lastGasUpdate; // Last gas price update
        uint256 lastCongestionUpdate; // Last congestion update
    }

    struct OracleConfig {
        uint256 gasUpdateInterval; // Gas price update interval
        uint256 congestionUpdateInterval; // Congestion update interval
        uint256 apyUpdateInterval; // APY update interval
        uint256 gasVolatility; // Gas price volatility
        uint256 congestionVolatility; // Congestion volatility
        bool autoUpdate; // Whether to auto-update data
    }

    // ============ State Variables ============
    /// @notice Role identifier for oracle managers
    bytes32 public constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");

    /// @notice Role identifier for data updaters
    bytes32 public constant DATA_UPDATER_ROLE = keccak256("DATA_UPDATER_ROLE");

    /// @notice Basis points for percentage calculations
    uint256 public constant BASIS_POINTS = 10_000;

    /// @notice Maximum APY (500% = 50000 basis points)
    uint256 public constant MAX_APY = 50_000;

    /// @notice Maximum gas price (1000 gwei)
    uint256 public constant MAX_GAS_PRICE = 1000 gwei;

    /// @notice Default update interval (5 minutes)
    uint256 public constant DEFAULT_UPDATE_INTERVAL = 5 minutes;

    /// @notice Pool data mapping
    mapping(address => PoolData) private s_poolData;

    /// @notice Array of all pool addresses
    address[] private s_poolAddresses;

    /// @notice Network data
    NetworkData private s_networkData;

    /// @notice Oracle configuration
    OracleConfig private s_oracleConfig;

    /// @notice Random seed for data generation
    uint256 private s_randomSeed;

    /// @notice Historical data storage
    mapping(address => uint256[]) private s_apyHistory;
    mapping(uint256 => uint256) private s_gasPriceHistory;
    mapping(uint256 => uint256) private s_congestionHistory;

    /// @notice Data request counter for randomization
    uint256 private s_requestCounter;

    /// @notice Emergency override values
    bool private s_emergencyMode;
    uint256 private s_emergencyGasPrice;
    uint256 private s_emergencyCongestion;

    // ============ Events ============
    event APYUpdated(address indexed poolAddress, uint256 newApy);
    event GasPriceUpdated(uint256 newGasPrice);
    event NetworkCongestionUpdated(uint256 newCongestionLevel);
    event PoolAdded(address indexed poolAddress, uint256 baseAPY);
    event PoolRemoved(address indexed poolAddress);
    event OracleConfigUpdated(
        uint256 gasUpdateInterval, uint256 congestionUpdateInterval, uint256 apyUpdateInterval
    );
    event EmergencyModeToggled(bool enabled);
    event DataBatchUpdated(uint256 poolCount, uint256 timestamp);

    // ============ Modifiers ============
    modifier onlyOracleManager() {
        if (!hasRole(ORACLE_MANAGER_ROLE, msg.sender)) {
            revert MockOracle__Unauthorized();
        }
        _;
    }

    modifier onlyDataUpdater() {
        if (!hasRole(DATA_UPDATER_ROLE, msg.sender)) {
            revert MockOracle__Unauthorized();
        }
        _;
    }

    modifier validPool(address poolAddress) {
        if (!s_poolData[poolAddress].isActive) {
            revert MockOracle__PoolNotFound();
        }
        _;
    }

    modifier validAddress(address addr) {
        if (addr == address(0)) {
            revert MockOracle__InvalidAddress();
        }
        _;
    }

    // ============ Constructor ============
    /**
     * @notice Initialize the MockOracle contract
     */
    constructor() {
        // Initialize network data with realistic values
        s_networkData = NetworkData({
            gasPrice: 20 gwei, // 20 gwei base
            congestionLevel: 50, // 50% congestion
            lastGasUpdate: block.timestamp,
            lastCongestionUpdate: block.timestamp
        });

        // Initialize oracle configuration
        s_oracleConfig = OracleConfig({
            gasUpdateInterval: DEFAULT_UPDATE_INTERVAL,
            congestionUpdateInterval: DEFAULT_UPDATE_INTERVAL,
            apyUpdateInterval: DEFAULT_UPDATE_INTERVAL,
            gasVolatility: 200, // 2% volatility
            congestionVolatility: 100, // 1% volatility
            autoUpdate: true
        });

        // Initialize random seed
        s_randomSeed =
            uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender)));

        // Grant roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ORACLE_MANAGER_ROLE, msg.sender);
        _grantRole(DATA_UPDATER_ROLE, msg.sender);
    }

    // ============ External Functions ============
    /**
     * @notice Get APY for a specific pool
     * @param poolAddress The address of the pool
     * @return apy The current APY for the pool
     */
    function getPoolAPY(address poolAddress)
        external
        view
        override
        validPool(poolAddress)
        returns (uint256 apy)
    {
        PoolData memory poolData = s_poolData[poolAddress];

        // Auto-update if enabled and time passed
        if (
            s_oracleConfig.autoUpdate
                && block.timestamp >= poolData.lastUpdated + s_oracleConfig.apyUpdateInterval
        ) {
            // Simulate APY fluctuation (view-only, does not update state)
            uint256 randomness = uint256(
                keccak256(
                    abi.encodePacked(
                        block.timestamp,
                        block.prevrandao,
                        s_randomSeed,
                        s_requestCounter,
                        msg.sender
                    )
                )
            );
            uint256 maxChange = (poolData.baseAPY * poolData.volatility) / BASIS_POINTS;
            uint256 change = randomness % (maxChange * 2);

            if (change < maxChange) {
                // Decrease APY
                apy = poolData.apy > maxChange - change
                    ? poolData.apy - (maxChange - change)
                    : poolData.minAPY;
            } else {
                // Increase APY
                apy = poolData.apy + (change - maxChange);
            }
            // Ensure within bounds
            if (apy < poolData.minAPY) apy = poolData.minAPY;
            if (apy > poolData.maxAPY) apy = poolData.maxAPY;
        } else {
            apy = poolData.apy;
        }
    }

    /**
     * @notice Get gas price
     * @return gasPrice The current gas price
     */
    function getGasPrice() external view override returns (uint256 gasPrice) {
        if (s_emergencyMode) {
            return s_emergencyGasPrice;
        }

        NetworkData memory networkData = s_networkData;

        // Auto-update if enabled and time passed
        if (
            s_oracleConfig.autoUpdate
                && block.timestamp >= networkData.lastGasUpdate + s_oracleConfig.gasUpdateInterval
        ) {
            // Simulate gas price fluctuation (view-only)
            uint256 randomness = uint256(
                keccak256(
                    abi.encodePacked(
                        block.timestamp,
                        block.prevrandao,
                        s_randomSeed,
                        s_requestCounter,
                        msg.sender
                    )
                )
            );
            uint256 maxChange = (networkData.gasPrice * s_oracleConfig.gasVolatility) / BASIS_POINTS;
            uint256 change = randomness % (maxChange * 2);
            if (change < maxChange) {
                gasPrice = networkData.gasPrice > maxChange - change
                    ? networkData.gasPrice - (maxChange - change)
                    : 1 gwei;
            } else {
                gasPrice = networkData.gasPrice + (change - maxChange);
            }
            if (gasPrice > MAX_GAS_PRICE) gasPrice = MAX_GAS_PRICE;
            if (gasPrice < 1 gwei) gasPrice = 1 gwei;
        } else {
            gasPrice = networkData.gasPrice;
        }
    }
    /**
     * @notice Get network congestion level
     * @return congestionLevel The current network congestion level (0-100)
     */

    function getNetworkCongestion() external view override returns (uint256 congestionLevel) {
        if (s_emergencyMode) {
            return s_emergencyCongestion;
        }

        NetworkData memory networkData = s_networkData;

        // Auto-update if enabled and time passed
        if (
            s_oracleConfig.autoUpdate
                && block.timestamp
                    >= networkData.lastCongestionUpdate + s_oracleConfig.congestionUpdateInterval
        ) {
            // Simulate congestion fluctuation (view-only, does not update state)
            uint256 randomness = uint256(
                keccak256(
                    abi.encodePacked(
                        block.timestamp,
                        block.prevrandao,
                        s_randomSeed,
                        s_requestCounter,
                        msg.sender
                    )
                )
            );
            uint256 maxChange = s_oracleConfig.congestionVolatility;
            uint256 change = randomness % (maxChange * 2);
            if (change < maxChange) {
                // Decrease congestion
                congestionLevel = networkData.congestionLevel > maxChange - change
                    ? networkData.congestionLevel - (maxChange - change)
                    : 0;
            } else {
                // Increase congestion
                congestionLevel = networkData.congestionLevel + (change - maxChange);
            }
            // Ensure within bounds
            if (congestionLevel > 100) congestionLevel = 100;
        } else {
            congestionLevel = networkData.congestionLevel;
        }
    }
    /**
     * @notice Update APY for a specific pool
     * @param poolAddress The address of the pool
     * @param newApy The new APY value
     */

    function updatePoolAPY(
        address poolAddress,
        uint256 newApy
    )
        external
        override
        onlyDataUpdater
        validPool(poolAddress)
    {
        if (newApy > MAX_APY) {
            revert MockOracle__InvalidAPY();
        }

        PoolData storage poolData = s_poolData[poolAddress];
        poolData.apy = newApy;
        poolData.lastUpdated = block.timestamp;

        // Store in history
        s_apyHistory[poolAddress].push(newApy);

        emit APYUpdated(poolAddress, newApy);
    }

    /**
     * @notice Update gas price
     * @param newGasPrice The new gas price
     */
    function updateGasPrice(uint256 newGasPrice) external override onlyDataUpdater {
        if (newGasPrice > MAX_GAS_PRICE) {
            revert MockOracle__InvalidGasPrice();
        }

        s_networkData.gasPrice = newGasPrice;
        s_networkData.lastGasUpdate = block.timestamp;

        // Store in history
        s_gasPriceHistory[block.timestamp] = newGasPrice;

        emit GasPriceUpdated(newGasPrice);
    }

    /**
     * @notice Update network congestion level
     * @param newCongestionLevel The new congestion level
     */
    function updateNetworkCongestion(uint256 newCongestionLevel)
        external
        override
        onlyDataUpdater
    {
        if (newCongestionLevel > 100) {
            revert MockOracle__InvalidCongestionLevel();
        }

        s_networkData.congestionLevel = newCongestionLevel;
        s_networkData.lastCongestionUpdate = block.timestamp;

        // Store in history
        s_congestionHistory[block.timestamp] = newCongestionLevel;

        emit NetworkCongestionUpdated(newCongestionLevel);
    }

    /**
     * @notice Add a new pool to the oracle
     * @param poolAddress The address of the pool
     * @param baseAPY The base APY for the pool
     * @param volatility The volatility factor for APY fluctuations
     */
    function addPool(
        address poolAddress,
        uint256 baseAPY,
        uint256 volatility
    )
        external
        onlyOracleManager
        validAddress(poolAddress)
    {
        if (s_poolData[poolAddress].isActive) {
            revert MockOracle__InvalidData();
        }

        if (baseAPY > MAX_APY) {
            revert MockOracle__InvalidAPY();
        }

        // Calculate min and max APY based on volatility
        uint256 minAPY = baseAPY > volatility ? baseAPY - volatility : 0;
        uint256 maxAPY = baseAPY + volatility;
        if (maxAPY > MAX_APY) maxAPY = MAX_APY;

        s_poolData[poolAddress] = PoolData({
            apy: baseAPY,
            baseAPY: baseAPY,
            lastUpdated: block.timestamp,
            volatility: volatility,
            isActive: true,
            minAPY: minAPY,
            maxAPY: maxAPY
        });

        s_poolAddresses.push(poolAddress);

        emit PoolAdded(poolAddress, baseAPY);
    }

    /**
     * @notice Remove a pool from the oracle
     * @param poolAddress The address of the pool to remove
     */
    function removePool(address poolAddress) external onlyOracleManager validPool(poolAddress) {
        s_poolData[poolAddress].isActive = false;

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
     * @notice Update oracle configuration
     * @param gasUpdateInterval Gas price update interval
     * @param congestionUpdateInterval Congestion update interval
     * @param apyUpdateInterval APY update interval
     * @param gasVolatility Gas price volatility
     * @param congestionVolatility Congestion volatility
     * @param autoUpdate Whether to enable auto-updates
     */
    function updateOracleConfig(
        uint256 gasUpdateInterval,
        uint256 congestionUpdateInterval,
        uint256 apyUpdateInterval,
        uint256 gasVolatility,
        uint256 congestionVolatility,
        bool autoUpdate
    )
        external
        onlyOracleManager
    {
        s_oracleConfig = OracleConfig({
            gasUpdateInterval: gasUpdateInterval,
            congestionUpdateInterval: congestionUpdateInterval,
            apyUpdateInterval: apyUpdateInterval,
            gasVolatility: gasVolatility,
            congestionVolatility: congestionVolatility,
            autoUpdate: autoUpdate
        });

        emit OracleConfigUpdated(gasUpdateInterval, congestionUpdateInterval, apyUpdateInterval);
    }

    /**
     * @notice Batch update all data
     */
    function batchUpdateData() external onlyDataUpdater {
        uint256 poolCount = 0;

        // Update all pool APYs
        for (uint256 i = 0; i < s_poolAddresses.length; i++) {
            address poolAddress = s_poolAddresses[i];
            PoolData storage poolData = s_poolData[poolAddress];

            if (poolData.isActive) {
                uint256 newAPY = _simulateAPYUpdate(poolAddress, poolData);
                poolData.apy = newAPY;
                poolData.lastUpdated = block.timestamp;

                s_apyHistory[poolAddress].push(newAPY);
                emit APYUpdated(poolAddress, newAPY);
                poolCount++;
            }
        }

        // Update gas price
        uint256 newGasPrice = _simulateGasPriceUpdate(s_networkData);
        s_networkData.gasPrice = newGasPrice;
        s_networkData.lastGasUpdate = block.timestamp;
        s_gasPriceHistory[block.timestamp] = newGasPrice;
        emit GasPriceUpdated(newGasPrice);

        // Update congestion
        uint256 newCongestion = _simulateCongestionUpdate(s_networkData);
        s_networkData.congestionLevel = newCongestion;
        s_networkData.lastCongestionUpdate = block.timestamp;
        s_congestionHistory[block.timestamp] = newCongestion;
        emit NetworkCongestionUpdated(newCongestion);

        emit DataBatchUpdated(poolCount, block.timestamp);
    }

    /**
     * @notice Toggle emergency mode
     * @param enabled Whether to enable emergency mode
     * @param emergencyGasPrice Emergency gas price
     * @param emergencyCongestion Emergency congestion level
     */
    function toggleEmergencyMode(
        bool enabled,
        uint256 emergencyGasPrice,
        uint256 emergencyCongestion
    )
        external
        onlyOracleManager
    {
        if (enabled) {
            if (emergencyGasPrice > MAX_GAS_PRICE) {
                revert MockOracle__InvalidGasPrice();
            }
            if (emergencyCongestion > 100) {
                revert MockOracle__InvalidCongestionLevel();
            }
        }

        s_emergencyMode = enabled;
        s_emergencyGasPrice = emergencyGasPrice;
        s_emergencyCongestion = emergencyCongestion;

        emit EmergencyModeToggled(enabled);
    }

    /**
     * @notice Simulate market conditions
     * @param scenario The market scenario (0: normal, 1: bull, 2: bear, 3: volatile)
     */
    function simulateMarketConditions(uint256 scenario) external onlyOracleManager {
        for (uint256 i = 0; i < s_poolAddresses.length; i++) {
            address poolAddress = s_poolAddresses[i];
            PoolData storage poolData = s_poolData[poolAddress];

            if (poolData.isActive) {
                uint256 newAPY;

                if (scenario == 1) {
                    // Bull market - increase APYs
                    newAPY = (poolData.baseAPY * 120) / 100; // 20% increase
                } else if (scenario == 2) {
                    // Bear market - decrease APYs
                    newAPY = (poolData.baseAPY * 80) / 100; // 20% decrease
                } else if (scenario == 3) {
                    // Volatile market - random fluctuation
                    uint256 change = _generateRandomness() % 40; // 0-40% change
                    newAPY = (poolData.baseAPY * (80 + change)) / 100;
                } else {
                    // Normal market - return to base
                    newAPY = poolData.baseAPY;
                }

                // Ensure within bounds
                if (newAPY < poolData.minAPY) newAPY = poolData.minAPY;
                if (newAPY > poolData.maxAPY) newAPY = poolData.maxAPY;

                poolData.apy = newAPY;
                poolData.lastUpdated = block.timestamp;

                emit APYUpdated(poolAddress, newAPY);
            }
        }

        // Update network conditions based on scenario
        if (scenario == 1) {
            // Bull market - higher congestion, higher gas
            s_networkData.gasPrice = (s_networkData.gasPrice * 130) / 100;
            s_networkData.congestionLevel = 80;
        } else if (scenario == 2) {
            // Bear market - lower congestion, lower gas
            s_networkData.gasPrice = (s_networkData.gasPrice * 70) / 100;
            s_networkData.congestionLevel = 20;
        } else if (scenario == 3) {
            // Volatile market - fluctuating conditions
            s_networkData.gasPrice =
                (s_networkData.gasPrice * (80 + _generateRandomness() % 40)) / 100;
            s_networkData.congestionLevel = 30 + _generateRandomness() % 40;
        }

        // Ensure bounds
        if (s_networkData.gasPrice > MAX_GAS_PRICE) {
            s_networkData.gasPrice = MAX_GAS_PRICE;
        }
        if (s_networkData.congestionLevel > 100) {
            s_networkData.congestionLevel = 100;
        }
    }

    /**
     * @notice Pause the oracle
     */
    function pause() external onlyOracleManager {
        _pause();
    }

    /**
     * @notice Unpause the oracle
     */
    function unpause() external onlyOracleManager {
        _unpause();
    }

    // ============ Internal Functions ============
    /**
     * @notice Simulate APY update with fluctuations
     * @param poolData The pool data
     * @return newAPY The new APY value
     */
    function _simulateAPYUpdate(
        address /* poolAddress */,
        PoolData memory poolData
    )
        internal
        returns (uint256 newAPY)
    {
        // Generate pseudo-random fluctuation
        uint256 randomness = _generateRandomness();

        // Calculate fluctuation based on volatility
        uint256 maxChange = (poolData.baseAPY * poolData.volatility) / BASIS_POINTS;
        uint256 change = randomness % (maxChange * 2);

        if (change < maxChange) {
            // Decrease APY
            newAPY = poolData.apy > maxChange - change
                ? poolData.apy - (maxChange - change)
                : poolData.minAPY;
        } else {
            // Increase APY
            newAPY = poolData.apy + (change - maxChange);
        }

        // Ensure within bounds
        if (newAPY < poolData.minAPY) newAPY = poolData.minAPY;
        if (newAPY > poolData.maxAPY) newAPY = poolData.maxAPY;
    }

    /**
     * @notice Simulate gas price update
     * @param networkData The network data
     * @return newGasPrice The new gas price
     */
    function _simulateGasPriceUpdate(NetworkData memory networkData)
        internal
        returns (uint256 newGasPrice)
    {
        uint256 randomness = _generateRandomness();

        // Calculate fluctuation based on volatility
        uint256 maxChange = (networkData.gasPrice * s_oracleConfig.gasVolatility) / BASIS_POINTS;
        uint256 change = randomness % (maxChange * 2);

        if (change < maxChange) {
            // Decrease gas price
            newGasPrice = networkData.gasPrice > maxChange - change
                ? networkData.gasPrice - (maxChange - change)
                : 1 gwei;
        } else {
            // Increase gas price
            newGasPrice = networkData.gasPrice + (change - maxChange);
        }

        // Ensure within bounds
        if (newGasPrice > MAX_GAS_PRICE) newGasPrice = MAX_GAS_PRICE;
        if (newGasPrice < 1 gwei) newGasPrice = 1 gwei;
    }
    /**
     * @notice Simulate congestion update
     * @param networkData The network data
     * @return newCongestion The new congestion level
     */

    function _simulateCongestionUpdate(NetworkData memory networkData)
        internal
        returns (uint256 newCongestion)
    {
        uint256 randomness = _generateRandomness();

        // Calculate fluctuation based on volatility
        uint256 maxChange = s_oracleConfig.congestionVolatility;
        uint256 change = randomness % (maxChange * 2);

        if (change < maxChange) {
            // Decrease congestion
            newCongestion = networkData.congestionLevel > maxChange - change
                ? networkData.congestionLevel - (maxChange - change)
                : 0;
        } else {
            // Increase congestion
            newCongestion = networkData.congestionLevel + (change - maxChange);
        }

        // Ensure within bounds
        if (newCongestion > 100) newCongestion = 100;
    }
    /**
     * @notice Generate pseudo-random number
     * @return randomness A pseudo-random number
     */

    function _generateRandomness() internal returns (uint256 randomness) {
        s_requestCounter++;
        randomness = uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp, block.prevrandao, s_randomSeed, s_requestCounter, msg.sender
                )
            )
        );
    }

    // ============ View Functions ============
    /**
     * @notice Get pool data
     * @param poolAddress The pool address
     * @return poolData The pool data struct
     */
    function getPoolData(address poolAddress) external view returns (PoolData memory poolData) {
        poolData = s_poolData[poolAddress];
    }

    /**
     * @notice Get all active pools
     * @return pools Array of active pool addresses
     */
    function getActivePools() external view returns (address[] memory pools) {
        uint256 activeCount = 0;

        // Count active pools
        for (uint256 i = 0; i < s_poolAddresses.length; i++) {
            if (s_poolData[s_poolAddresses[i]].isActive) {
                activeCount++;
            }
        }

        // Create array of active pools
        pools = new address[](activeCount);
        uint256 index = 0;

        for (uint256 i = 0; i < s_poolAddresses.length; i++) {
            if (s_poolData[s_poolAddresses[i]].isActive) {
                pools[index] = s_poolAddresses[i];
                index++;
            }
        }
    }

    /**
     * @notice Get network data
     * @return networkData The network data struct
     */
    function getNetworkData() external view returns (NetworkData memory networkData) {
        networkData = s_networkData;
    }

    /**
     * @notice Get oracle configuration
     * @return config The oracle configuration struct
     */
    function getOracleConfig() external view returns (OracleConfig memory config) {
        config = s_oracleConfig;
    }

    /**
     * @notice Get APY history for a pool
     * @param poolAddress The pool address
     * @return history Array of historical APY values
     */
    function getAPYHistory(address poolAddress) external view returns (uint256[] memory history) {
        history = s_apyHistory[poolAddress];
    }

    /**
     * @notice Get recent APY history for a pool
     * @param poolAddress The pool address
     * @param count Number of recent entries to return
     * @return history Array of recent APY values
     */
    function getRecentAPYHistory(
        address poolAddress,
        uint256 count
    )
        external
        view
        returns (uint256[] memory history)
    {
        uint256[] storage fullHistory = s_apyHistory[poolAddress];
        uint256 length = fullHistory.length;

        if (count > length) count = length;

        history = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            history[i] = fullHistory[length - count + i];
        }
    }

    /**
     * @notice Get pool statistics
     * @param poolAddress The pool address
     * @return avgAPY Average APY
     * @return minAPY Minimum APY in history
     * @return maxAPY Maximum APY in history
     * @return volatility APY volatility
     */
    function getPoolStatistics(address poolAddress)
        external
        view
        returns (uint256 avgAPY, uint256 minAPY, uint256 maxAPY, uint256 volatility)
    {
        uint256[] storage history = s_apyHistory[poolAddress];
        uint256 length = history.length;

        if (length == 0) {
            PoolData memory poolData = s_poolData[poolAddress];
            return (poolData.apy, poolData.apy, poolData.apy, poolData.volatility);
        }

        uint256 sum = 0;
        minAPY = type(uint256).max;
        maxAPY = 0;

        // Calculate average, min, max
        for (uint256 i = 0; i < length; i++) {
            uint256 apy = history[i];
            sum += apy;
            if (apy < minAPY) minAPY = apy;
            if (apy > maxAPY) maxAPY = apy;
        }

        avgAPY = sum / length;

        // Calculate volatility (standard deviation)
        uint256 variance = 0;
        for (uint256 i = 0; i < length; i++) {
            uint256 apy = history[i];
            uint256 diff = apy > avgAPY ? apy - avgAPY : avgAPY - apy;
            variance += diff * diff;
        }

        volatility = _sqrt(variance / length);
    }

    /**
     * @notice Check if data needs update
     * @return needsUpdate Whether any data needs updating
     * @return updateTypes Bitmask of update types needed (1: APY, 2: Gas, 4: Congestion)
     */
    function needsDataUpdate() external view returns (bool needsUpdate, uint256 updateTypes) {
        updateTypes = 0;

        // Check APY updates
        for (uint256 i = 0; i < s_poolAddresses.length; i++) {
            address poolAddress = s_poolAddresses[i];
            PoolData memory poolData = s_poolData[poolAddress];

            if (
                poolData.isActive
                    && block.timestamp >= poolData.lastUpdated + s_oracleConfig.apyUpdateInterval
            ) {
                updateTypes |= 1;
                break;
            }
        }

        // Check gas price update
        if (block.timestamp >= s_networkData.lastGasUpdate + s_oracleConfig.gasUpdateInterval) {
            updateTypes |= 2;
        }

        // Check congestion update
        if (
            block.timestamp
                >= s_networkData.lastCongestionUpdate + s_oracleConfig.congestionUpdateInterval
        ) {
            updateTypes |= 4;
        }

        needsUpdate = updateTypes > 0;
    }

    /**
     * @notice Get emergency mode status
     * @return enabled Whether emergency mode is enabled
     * @return emergencyGasPrice Emergency gas price
     * @return emergencyCongestion Emergency congestion level
     */
    function getEmergencyMode()
        external
        view
        returns (bool enabled, uint256 emergencyGasPrice, uint256 emergencyCongestion)
    {
        enabled = s_emergencyMode;
        emergencyGasPrice = s_emergencyGasPrice;
        emergencyCongestion = s_emergencyCongestion;
    }

    /**
     * @notice Get pool count
     * @return totalPools Total number of pools
     * @return activePools Number of active pools
     */
    function getPoolCount() external view returns (uint256 totalPools, uint256 activePools) {
        totalPools = s_poolAddresses.length;

        for (uint256 i = 0; i < s_poolAddresses.length; i++) {
            if (s_poolData[s_poolAddresses[i]].isActive) {
                activePools++;
            }
        }
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
     * @notice Get best performing pool
     * @return poolAddress Address of best performing pool
     * @return apy APY of best performing pool
     */
    function getBestPerformingPool() external view returns (address poolAddress, uint256 apy) {
        uint256 bestAPY = 0;
        address bestPool = address(0);

        for (uint256 i = 0; i < s_poolAddresses.length; i++) {
            address currentPool = s_poolAddresses[i];
            PoolData memory poolData = s_poolData[currentPool];

            if (poolData.isActive && poolData.apy > bestAPY) {
                bestAPY = poolData.apy;
                bestPool = currentPool;
            }
        }

        return (bestPool, bestAPY);
    }

    /**
     * @notice Get worst performing pool
     * @return poolAddress Address of worst performing pool
     * @return apy APY of worst performing pool
     */
    function getWorstPerformingPool() external view returns (address poolAddress, uint256 apy) {
        uint256 worstAPY = type(uint256).max;
        address worstPool = address(0);

        for (uint256 i = 0; i < s_poolAddresses.length; i++) {
            address currentPool = s_poolAddresses[i];
            PoolData memory poolData = s_poolData[currentPool];

            if (poolData.isActive && poolData.apy < worstAPY) {
                worstAPY = poolData.apy;
                worstPool = currentPool;
            }
        }

        return (worstPool, worstAPY);
    }

    /**
     * @notice Get market trend analysis
     * @return trend Market trend (-1: bear, 0: neutral, 1: bull)
     * @return strength Trend strength (0-100)
     */
    function getMarketTrend() external view returns (int256 trend, uint256 strength) {
        if (s_poolAddresses.length == 0) {
            return (0, 0);
        }

        uint256 totalCurrent = 0;
        uint256 totalBase = 0;
        uint256 activeCount = 0;

        // Calculate weighted trend based on all pools
        for (uint256 i = 0; i < s_poolAddresses.length; i++) {
            PoolData memory poolData = s_poolData[s_poolAddresses[i]];

            if (poolData.isActive) {
                totalCurrent += poolData.apy;
                totalBase += poolData.baseAPY;
                activeCount++;
            }
        }

        if (activeCount == 0) {
            return (0, 0);
        }

        uint256 avgCurrent = totalCurrent / activeCount;
        uint256 avgBase = totalBase / activeCount;

        if (avgCurrent > avgBase) {
            trend = 1; // Bull market
            strength = ((avgCurrent - avgBase) * 100) / avgBase;
        } else if (avgCurrent < avgBase) {
            trend = -1; // Bear market
            strength = ((avgBase - avgCurrent) * 100) / avgBase;
        } else {
            trend = 0; // Neutral
            strength = 0;
        }

        // Cap strength at 100
        if (strength > 100) strength = 100;
    }
}
