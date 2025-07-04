// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IMockOracle
 * @author YieldSync Team
 * @notice Interface for mock oracle providing simulated data for testing
 */
interface IMockOracle {
    /**
     * @notice Get APY for a specific pool
     * @param poolAddress The address of the pool
     * @return apy The current APY for the pool
     */
    function getPoolAPY(address poolAddress) external view returns (uint256 apy);

    /**
     * @notice Get current gas price
     * @return gasPrice The current gas price
     */
    function getGasPrice() external view returns (uint256 gasPrice);

    /**
     * @notice Get network congestion level
     * @return congestionLevel The current network congestion level (0-100)
     */
    function getNetworkCongestion() external view returns (uint256 congestionLevel);

    // ============ Admin Functions ============
    /**
     * @notice Update APY for a specific pool
     * @param poolAddress The address of the pool
     * @param newApy The new APY value
     */
    function updatePoolAPY(address poolAddress, uint256 newApy) external;

    /**
     * @notice Update gas price
     * @param newGasPrice The new gas price
     */
    function updateGasPrice(uint256 newGasPrice) external;

    /**
     * @notice Update network congestion level
     * @param newCongestionLevel The new congestion level
     */
    function updateNetworkCongestion(uint256 newCongestionLevel) external;
}
