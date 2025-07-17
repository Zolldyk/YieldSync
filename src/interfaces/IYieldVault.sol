// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;


/**
 * @title IYieldVault
 * @author YieldSync Team
 * @notice Interface for the main vault contract that handles user deposits and withdrawals
 */
interface IYieldVault {
    /**
     * @notice Deposit assets into the vault
     * @param amount The amount of assets to deposit
     * @return shares The number of shares minted to the user
     */
    function deposit(uint256 amount) external returns (uint256 shares);

    /**
     * @notice Withdraw assets from the vault
     * @param shares The number of shares to burn
     * @return amount The amount of assets withdrawn
     */
    function withdraw(uint256 shares) external returns (uint256 amount);

    /**
     * @notice Get the current exchange rate between assets and shares
     * @return rate The current exchange rate (assets per share)
     */
    function getExchangeRate() external view returns (uint256 rate);

    /**
     * @notice Get the total assets managed by the vault
     * @return totalAssets The total amount of assets under management
     */
    function totalAssets() external view returns (uint256 totalAssets);

    /**
     * @notice Get user's share balance
     * @param user The user address
     * @return shares The user's share balance
     */
    function balanceOf(address user) external view returns (uint256 shares);
}
