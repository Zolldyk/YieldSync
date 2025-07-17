// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { YieldVault } from "../../src/YieldVault.sol";
import { YieldAggregator } from "../../src/YieldAggregator.sol";
import { FeeOptimizer } from "../../src/FeeOptimizer.sol";
import { MockOracle } from "../../src/MockOracle.sol";
import { GovernanceToken } from "../../src/GovernanceToken.sol";
import { MockPool } from "../../src/MockPool.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockToken
 * @notice Mock ERC20 token for testing
 */
contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1_000_000_000 * 10 ** decimals());
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title BaseTest
 * @notice Base test contract with common setup and utilities
 */
contract BaseTest is Test {
    // Contract instances
    MockToken public mockToken;
    MockOracle public mockOracle;
    FeeOptimizer public feeOptimizer;
    YieldAggregator public yieldAggregator;
    YieldVault public yieldVault;
    GovernanceToken public governanceToken;
    MockPool public pool1;
    MockPool public pool2;
    MockPool public pool3;

    // Test accounts
    address public constant ADMIN = address(0x1);
    address public constant FEE_COLLECTOR = address(0x2);
    address public constant USER1 = address(0x3);
    address public constant USER2 = address(0x4);
    address public constant USER3 = address(0x5);

    // Test constants
    uint256 public constant INITIAL_BALANCE = 100_000 * 1e18;
    uint256 public constant DEPOSIT_AMOUNT = 1000 * 1e18;
    uint256 public constant POOL_APY_1 = 800; // 8%
    uint256 public constant POOL_APY_2 = 1200; // 12%
    uint256 public constant POOL_APY_3 = 1500; // 15%

    // Events for testing
    event Deposited(address indexed user, uint256 amount, uint256 shares);
    event Withdrawn(address indexed user, uint256 amount, uint256 shares);
    event YieldHarvested(uint256 totalYield, uint256 timestamp);

    /**
     * @notice Setup function called before each test
     */
    function setUp() public virtual {
        vm.startPrank(ADMIN);

        // Deploy mock token
        mockToken = new MockToken();

        // Deploy mock oracle
        mockOracle = new MockOracle();

        // Deploy mock pools
        pool1 = new MockPool(address(mockToken), POOL_APY_1, "Pool 1", "AMM");
        pool2 = new MockPool(address(mockToken), POOL_APY_2, "Pool 2", "Lending");
        pool3 = new MockPool(address(mockToken), POOL_APY_3, "Pool 3", "Staking");

        // Add pools to oracle
        mockOracle.addPool(address(pool1), POOL_APY_1, 100);
        mockOracle.addPool(address(pool2), POOL_APY_2, 150);
        mockOracle.addPool(address(pool3), POOL_APY_3, 200);

        // Deploy fee optimizer
        feeOptimizer = new FeeOptimizer(address(mockOracle));

        // Deploy yield aggregator first (with temporary vault address)
        yieldAggregator = new YieldAggregator(address(mockToken), address(mockOracle), address(1));

        // Deploy yield vault with aggregator address
        yieldVault = new YieldVault(
            address(mockToken),
            address(yieldAggregator),
            address(feeOptimizer),
            FEE_COLLECTOR,
            "YieldSync Vault",
            "YSV"
        );

        // Set the correct vault address in the aggregator
        yieldAggregator.setVault(address(yieldVault));

        // Deploy governance token
        governanceToken = new GovernanceToken(address(yieldVault), "YieldSync Governance", "YSG");

        // Configure contracts
        bytes32 vaultRole = yieldAggregator.VAULT_ROLE();
        yieldAggregator.grantRole(vaultRole, address(yieldVault));

        bytes32 aggregatorRole = yieldVault.AGGREGATOR_ROLE();
        yieldVault.grantRole(aggregatorRole, address(yieldAggregator));

        // Add pools to aggregator
        yieldAggregator.addPool(address(pool1), POOL_APY_1);
        yieldAggregator.addPool(address(pool2), POOL_APY_2);
        yieldAggregator.addPool(address(pool3), POOL_APY_3);

        vm.stopPrank();

        // Setup user balances
        _setupUserBalances();
    }

    /**
     * @notice Setup initial token balances for test users
     */
    function _setupUserBalances() internal {
        mockToken.mint(USER1, INITIAL_BALANCE);
        mockToken.mint(USER2, INITIAL_BALANCE);
        mockToken.mint(USER3, INITIAL_BALANCE);

        // Add some liquidity to pools for testing
        vm.startPrank(ADMIN);
        mockToken.mint(ADMIN, INITIAL_BALANCE);

        mockToken.approve(address(pool1), INITIAL_BALANCE / 3);
        pool1.deposit(INITIAL_BALANCE / 3);

        mockToken.approve(address(pool2), INITIAL_BALANCE / 3);
        pool2.deposit(INITIAL_BALANCE / 3);

        mockToken.approve(address(pool3), INITIAL_BALANCE / 3);
        pool3.deposit(INITIAL_BALANCE / 3);

        vm.stopPrank();
    }

    /**
     * @notice Setup governance tokens for testing
     */
    function _setupGovernanceTokens(address user, uint256 amount) internal {
        vm.startPrank(ADMIN);

        // First user needs vault shares to share yield
        mockToken.mint(user, amount);

        vm.stopPrank();
        vm.startPrank(user);

        // Deposit to get vault shares
        mockToken.approve(address(yieldVault), amount / 10);
        uint256 vaultShares = yieldVault.deposit(amount / 10);

        // Share yield to get governance tokens
        yieldVault.approve(address(governanceToken), vaultShares);
        governanceToken.shareYield(vaultShares);

        // Delegate voting power to self (required for ERC20Votes)
        governanceToken.delegate(user);

        vm.stopPrank();
    }
}