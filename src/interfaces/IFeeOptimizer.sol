// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IFeeOptimizer
 * @author YieldSync Team
 * @notice Interface for dynamic fee optimization based on network conditions
 */
interface IFeeOptimizer {
    /**
     * @notice Get the current optimal fee based on network conditions
     * @return fee The current fee in basis points (1 basis point = 0.01%)
     */
    function getCurrentFee() external view returns (uint256 fee);

    /**
     * @notice Update fee based on current network conditions
     */
    function updateFee() external;

    /**
     * @notice Calculate fee for a specific transaction amount
     * @param amount The transaction amount
     * @return feeAmount The fee amount to be charged
     */
    function calculateFee(uint256 amount) external view returns (uint256 feeAmount);
}
