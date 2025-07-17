# YieldSync BlockDAG

> **Decentralized Yield Aggregator Protocol on BlockDAG Network**

[![Solidity](https://img.shields.io/badge/Solidity-^0.8.24-blue.svg)](https://soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg)](https://getfoundry.sh/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Live Demo](https://img.shields.io/badge/Live%20Demo-Vercel-black.svg)](https://yieldsync-blockdag.vercel.app)

YieldSync is a sophisticated DeFi yield optimization protocol designed specifically for the BlockDAG ecosystem. It automatically maximizes returns for users by intelligently allocating funds across multiple liquidity pools while implementing dynamic fee optimization and community governance features.

## 🌟 Project Overview

### Purpose

YieldSync addresses the complexity of manual yield farming by providing an automated, intelligent yield aggregator that:

- **Maximizes Returns**: Automatically allocates user funds to the highest-yielding liquidity pools
- **Optimizes Fees**: Dynamically adjusts protocol fees based on BlockDAG network conditions
- **Enables Governance**: Allows community participation through yield-sharing and voting mechanisms
- **Manages Risk**: Implements comprehensive safety mechanisms and diversification strategies

### Key Features

- 🚀 **Automated Yield Optimization**: Set-and-forget yield farming across multiple pools
- 📊 **Dynamic Fee Management**: Smart fee adjustment based on network congestion
- 🏛️ **Community Governance**: Decentralized decision-making through governance tokens
- 🛡️ **Risk Management**: Deposit caps, allocation limits, and emergency mechanisms
- ⚡ **BlockDAG Native**: Optimized for BlockDAG's fast transaction processing
- 🎯 **User-Friendly Interface**: Intuitive web application for seamless interaction

## 🏗️ System Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   YieldVault    │◄──►│  YieldAggregator │◄──►│  Liquidity      │
│   (Main Hub)    │    │  (Allocation)    │    │  Pools (1-N)    │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │
         ▼                       ▼
┌─────────────────┐    ┌──────────────────┐
│  FeeOptimizer   │    │   Oracle System  │
│ (Fee Dynamics)  │    │ (Price/APY Data) │
└─────────────────┘    └──────────────────┘
         │
         ▼
┌─────────────────┐
│ GovernanceToken │
│   (Community)   │
└─────────────────┘
```

### Core Contracts

| Contract | Purpose | Key Features |
|----------|---------|--------------|
| **YieldVault** | Main user interface | Deposits, withdrawals, share management |
| **YieldAggregator** | Pool allocation engine | Multi-pool management, rebalancing |
| **GovernanceToken** | Community governance | Voting, proposals, yield sharing |
| **FeeOptimizer** | Dynamic fee management | Network-based fee adjustment |
| **MockOracle** | Price & APY data | Real-time pool performance tracking |

## 🛠️ Installation

### Prerequisites

- [Node.js](https://nodejs.org/) (v16 or higher)
- [Foundry](https://getfoundry.sh/) for smart contract development
- [Git](https://git-scm.com/) for version control

### Quick Setup

1. **Clone the repository**
   ```bash
   git clone https://github.com/Zolldyk/YieldSync.git
   cd yieldsync-blockdag
   ```

2. **Install Foundry dependencies**
   ```bash
   foundry install
   ```

3. **Set up environment variables**
   ```bash
   cp .env.example .env
   # Edit .env with your configuration
   ```

4. **Build the contracts**
   ```bash
   forge build
   ```

5. **Run the test suite**
   ```bash
   forge test
   ```

### Environment Configuration

Create a `.env` file with the following variables:

```bash
# Network Configuration
CHAIN_ID=1043
NETWORK=blockdag

# RPC Configuration
BLOCKDAG_RPC_URL=https://test-rpc.primordial.bdagscan.com
BLOCKDAG_EXPLORER_URL=https://primordial.bdagscan.com

# Deployment Configuration (Add your private key for deployments)
PRIVATE_KEY=your_private_key_here

# Token Configuration
VAULT_NAME="YieldSync Vault"
VAULT_SYMBOL="YSV"
GOV_TOKEN_NAME="YieldSync Governance"
GOV_TOKEN_SYMBOL="YSG"
```

## 📋 Usage Instructions

### For Users

#### 1. Access the Web Interface
Visit the live application: [https://yieldsync-blockdag.vercel.app](https://yieldsync-blockdag.vercel.app)

#### 2. Connect Your Wallet
- Click "Connect Wallet" and select MetaMask
- Switch to BlockDAG Primordial Testnet (Chain ID: 1043)
- Ensure you have BDAG tokens for transactions

#### 3. Deposit Assets
- Navigate to the "Deposit" tab
- Enter the amount of BDAG tokens to deposit
- Click "Deposit Assets" and confirm the transaction
- Receive YSV (YieldSync Vault) shares representing your stake

#### 4. Monitor Performance
- View your vault shares and current value
- Track real-time APY and pool allocations
- Monitor vault health indicators

#### 5. Participate in Governance
- Share yield to earn YSG (YieldSync Governance) tokens
- Vote on governance proposals
- Create new proposals (requires minimum token threshold)

#### 6. Withdraw Assets
- Go to the "Withdraw" tab
- Enter the amount of shares to withdraw
- Confirm the transaction to receive your assets plus earned yield

### For Developers

#### Smart Contract Deployment

##### Option 1: BlockDAG IDE (Recommended)

The easiest way to deploy YieldSync contracts is using BlockDAG's official web-based IDE:

1. **Access BlockDAG IDE**
   - Visit [https://ide.primordial.bdagscan.com/](https://ide.primordial.bdagscan.com/)
   - No installation required - runs entirely in your browser

2. **Create Contract Files**
   - Navigate to "Workspace" in the left panel
   - Click "Create New File" icon
   - Create files under the "contracts" folder:
     - `YieldVault.sol`
     - `YieldAggregator.sol` 
     - `GovernanceToken.sol`
     - `FeeOptimizer.sol`
     - `MockOracle.sol`

3. **Import Contract Code**
   - Copy the contract code from your local `src/` directory
   - Paste into the respective files in the IDE
   - Include all necessary import statements

4. **Compile Contracts**
   - Configure Solidity compiler settings (select version ^0.8.24)
   - Select each contract file and click "Compile"
   - Verify successful compilation (green checkmarks)

5. **Deploy Contracts**
   - Navigate to "Deploy & Run Transactions" in the left sidebar
   - Connect your wallet:
     - **BlockDAG Provider**: Connect MetaMask to BlockDAG network
   - Select the contract from the dropdown
   - Click "Deploy" and confirm the transaction in MetaMask
   - Repeat for each contract in deployment order:
     1. MockOracle
     2. FeeOptimizer  
     3. YieldAggregator
     4. YieldVault
     5. GovernanceToken

6. **Configure Contract Interactions**
   - Use the IDE's interaction panel to:
     - Grant necessary roles between contracts
     - Set up pool configurations
     - Initialize contract parameters

**Benefits of BlockDAG IDE:**
- No local setup required
- Integrated with BlockDAG network
- Real-time compilation and deployment
- Built-in wallet integration
- Contract interaction interface
- Deployment history and logs

##### Option 2: Foundry CLI (Advanced)

For developers preferring command-line deployment:

1. **Deploy to BlockDAG Testnet**
   ```bash
   forge script script/Deploy.s.sol --rpc-url blockdag --broadcast --verify
   ```

2. **Deploy Individual Contracts**
   ```bash
   # Deploy only GovernanceToken
   forge script script/DeployGovernanceToken.s.sol --rpc-url blockdag --broadcast
   ```

3. **Configure Deployed Contracts**
   ```bash
   forge script script/ConfigureDeployment.s.sol --rpc-url blockdag --broadcast
   ```

#### Testing

```bash
# Run all tests
forge test

# Run tests with gas reporting
forge test --gas-report

# Run specific test contract
forge test --match-contract YieldVaultUnitTest

# Run fuzz tests
forge test --match-contract YieldVaultFuzzTest

# Run integration tests
forge test --match-contract YieldVaultIntegrationTest
```

#### Local Development

1. **Start local blockchain**
   ```bash
   anvil
   ```

2. **Deploy to local network**
   ```bash
   forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast
   ```

3. **Interact with contracts**
   ```bash
   cast call <contract_address> "balanceOf(address)" <user_address> --rpc-url http://localhost:8545
   ```

### Frontend Development

The web interface is built with vanilla HTML, CSS, and JavaScript for simplicity and performance.

1. **Serve locally**
   ```bash
   cd frontend/src
   python -m http.server 8000
   # Access at http://localhost:8000
   ```

2. **Deploy to Vercel**
   ```bash
   vercel --prod
   ```

## 🧪 Testing

The project includes comprehensive testing across multiple dimensions:

- **Unit Tests**: Individual contract functionality
- **Integration Tests**: Cross-contract interactions
- **Fuzz Tests**: Property-based testing with random inputs
- **Gas Optimization**: Performance and cost analysis

### Test Coverage

| Component | Unit Tests | Integration | Fuzz Tests |
|-----------|------------|-------------|------------|
| YieldVault | ✅ 24 tests | ✅ 12 tests | ✅ 15 tests |
| YieldAggregator | ✅ 20 tests | Included | Planned |
| GovernanceToken | ✅ 3 tests | ✅ Included | Planned |
| FeeOptimizer | ✅ 12 tests | ✅ Included | Planned |

## 🔧 Contract Verification

Verify deployed contracts on BlockDAG Explorer:

```bash
forge verify-contract <contract_address> src/YieldVault.sol:YieldVault \
  --constructor-args <encoded_args> \
  --rpc-url https://test-rpc.primordial.bdagscan.com \
  --chain-id 1043
```

## 🌐 Live Deployment

### Mainnet Addresses (BlockDAG Primordial Testnet)

| Contract | Address |
|----------|---------|
| YieldVault | `0xE63cE0E709eB6E7f345133C681Ba177df603e804` |
| YieldAggregator | `0xCB30C36cfaAa32b059138E302281dB4B8e50eD8c` |
| GovernanceToken | `0x7412634B3189546549898000929A72600EF52b82` |
| FeeOptimizer | `0x90aF6FD2d47144a72B1e1D482C4208006Dba4f29` |
| MockOracle | `0x4f910ef3996d7c4763efa2fef15265e8b918cd0b` |

### Network Information

- **Network**: BlockDAG Primordial Testnet
- **Chain ID**: 1043 (0x413)
- **RPC URL**: `https://test-rpc.primordial.bdagscan.com`
- **Explorer**: `https://primordial.bdagscan.com`

## 🛡️ Security

### Implemented Security Measures

- **Access Controls**: Role-based permissions for all administrative functions
- **Reentrancy Protection**: Guards against reentrancy attacks
- **Input Validation**: Comprehensive validation of all user inputs
- **Emergency Mechanisms**: Emergency withdrawal and pause functionality
- **Deposit Caps**: Maximum deposit limits to prevent excessive concentration
- **Allocation Limits**: Maximum 50% allocation per pool for risk diversification

### Audit Status

⚠️ **This protocol has not been audited.** Use at your own risk. This is experimental software designed for educational and testing purposes.

### Development Workflow

```bash
# Create feature branch
git checkout -b feature/awesome-feature

# Make changes and test
forge test

# Commit changes
git commit -m "Add awesome feature"

# Push and create PR
git push origin feature/awesome-feature
```

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

```
MIT License

Copyright (c) 2025 YieldSync Team

---

## 📚 Additional Resources

- [BlockDAG Documentation](https://docs.blockdag.network/)
- [Foundry Book](https://book.getfoundry.sh/)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/)
- [ERC-4626 Vault Standard](https://eips.ethereum.org/EIPS/eip-4626)

## Interact

- **Live Demo**: [https://yieldsync-blockdag.vercel.app](https://yieldsync-blockdag.vercel.app)

---

**⚠️ Disclaimer**: This is experimental DeFi software. Use at your own risk. 