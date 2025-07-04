// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { YieldAggregator } from "../YieldAggregator.sol";

/**
 * @title IYieldAggregator
 * @author YieldSync Team
 * @notice Interface for the yield aggregator that manages pool allocation
 */
interface IYieldAggregator {
    struct PoolInfo {
        address poolAddress; // Address of the liquidity pool
        uint256 apy; // Current APY of the pool (in basis points)
        uint256 allocation; // Current allocation amount in the pool
        uint256 lastUpdated; // Last time pool data was updated
        bool isActive; // Whether the pool is active for allocation
    }

    /**
     * @notice Allocate funds to the best performing pools
     * @param amount The total amount to allocate
     */
    function allocateFunds(uint256 amount) external;

    /**
     * @notice Rebalance funds across pools based on current APYs
     */
    function rebalancePools() external;

    /**
     * @notice Get the best pool for allocation
     * @return poolAddress The address of the best performing pool
     * @return apy The APY of the best performing pool
     */
    function getBestPool() external view returns (address poolAddress, uint256 apy);

    /**
     * @notice Get information about a specific pool
     * @param poolAddress The address of the pool
     * @return poolInfo The pool information struct
     */
    function getPoolInfo(address poolAddress) external view returns (PoolInfo memory poolInfo);

    /**
     * @notice Get all active pools
     * @return pools Array of active pool addresses
     */
    function getActivePools() external view returns (address[] memory pools);
}
