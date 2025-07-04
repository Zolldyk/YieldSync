// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IMockPool
 * @author YieldSync Team
 * @notice Interface for mock liquidity pools used for testing
 */
interface IMockPool {
    /**
     * @notice Deposit assets into the mock pool
     * @param amount The amount to deposit
     */
    function deposit(uint256 amount) external;

    /**
     * @notice Withdraw assets from the mock pool
     * @param amount The amount to withdraw
     */
    function withdraw(uint256 amount) external;

    /**
     * @notice Get the current APY of the pool
     * @return apy The current APY
     */
    function getAPY() external view returns (uint256 apy);

    /**
     * @notice Get total assets in the pool
     * @return totalAssets The total amount of assets
     */
    function totalAssets() external view returns (uint256 totalAssets);

    /**
     * @notice Get user's balance in the pool
     * @param user The user address
     * @return balance The user's balance
     */
    function balanceOf(address user) external view returns (uint256 balance);
}
