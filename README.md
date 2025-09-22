# Pulley DeFi Trading Pool System

A comprehensive DeFi system built on Aptos that enables users to participate in yield-bearing trading pools with built-in insurance mechanisms.

## System Overview

The Pulley system consists of four main components:

1. **Trading Pool** - Users deposit funds and receive pool tokens representing their share
2. **Controller** - Manages fund allocation across different yield strategies
3. **Yield Vaults** - Execute different yield-bearing strategies (lending, liquidity mining, staking)
4. **Insurance Token** - Provides loss protection through a floating stablecoin mechanism

## Architecture

```
User Deposits → Trading Pool → Controller → Yield Vaults
                     ↓              ↓
                Insurance ← 10% + 5% of profits
```

### Fund Allocation Flow

1. Users deposit funds into the trading pool and receive pool tokens
2. When the pool balance reaches a threshold, funds are automatically transferred to the controller
3. The controller splits funds as follows:
   - **10%** → Insurance token minting
   - **30%** → Yield Vault 1 (Lending Strategy)
   - **30%** → Yield Vault 2 (Liquidity Mining Strategy)  
   - **30%** → Yield Vault 3 (Staking Strategy)

### Profit/Loss Mechanism

**Profits:**
- **5%** of profits go to insurance token minting
- **95%** of profits are distributed to pool token holders

**Losses:**
- Insurance tokens are burned first to absorb losses
- Only after insurance is depleted do losses affect the trading pool
- Users outside the trading pool can mint insurance tokens for additional protection

## Smart Contracts

### 1. Insurance Token (`insurance_token.move`)

- **Purpose**: Floating stablecoin that provides loss insurance
- **Key Features**:
  - Anyone can mint insurance tokens
  - Automatically absorbs trading losses
  - Receives 5% of all trading profits
  - Authorized controllers can burn tokens to cover losses

**Main Functions:**
- `initialize(admin)` - Setup the insurance system
- `mint_insurance(recipient, admin_addr, amount)` - Mint insurance tokens
- `absorb_loss(controller, admin_addr, loss_amount)` - Absorb trading losses
- `deposit_profit(controller, admin_addr, profit_amount)` - Deposit profits

### 2. Trading Pool (`trading_pool.move`)

- **Purpose**: Main entry point for user deposits and withdrawals
- **Key Features**:
  - Issues pool tokens proportional to deposits
  - Automatic threshold-based fund transfer to controller
  - Profit distribution to token holders
  - Withdrawal based on pool token ownership

**Main Functions:**
- `initialize<CoinType>(admin, threshold_amount, controller_address)` - Setup pool
- `deposit<CoinType>(user, admin_addr, deposit_coins)` - Deposit funds
- `withdraw<CoinType>(user, admin_addr, pool_tokens_to_burn)` - Withdraw funds
- `distribute_profit<CoinType>(controller, admin_addr, profit_coins, insurance_share)` - Distribute profits

### 3. Controller (`controller.move`)

- **Purpose**: Central fund management and allocation
- **Key Features**:
  - Splits incoming funds according to predefined percentages
  - Manages interactions with yield vaults
  - Handles profit/loss reporting
  - Coordinates with insurance system

**Main Functions:**
- `initialize<CoinType>(admin, trading_pool_address, insurance_admin_address, vault_addresses)` - Setup controller
- `allocate_funds<CoinType>(pool_signer, controller_addr, funds)` - Allocate funds to vaults
- `report_profit<CoinType>(vault, controller_addr, profit_coins)` - Handle vault profits
- `report_loss<CoinType>(vault, controller_addr, loss_amount)` - Handle vault losses

### 4. Yield Vault (`yield_vault.move`)

- **Purpose**: Execute yield-bearing strategies
- **Key Features**:
  - Multiple strategy types (lending, liquidity mining, staking)
  - Automated yield harvesting
  - Performance fee collection
  - Loss reporting to controller

**Strategy Types:**
- **Type 1**: Lending Strategy (5% APY target)
- **Type 2**: Liquidity Mining Strategy (8% APY target)
- **Type 3**: Staking Strategy (6% APY target)

**Main Functions:**
- `initialize<CoinType>(admin, controller_address, strategy_type, strategy_name, performance_fee)` - Setup vault
- `deposit<CoinType>(controller, vault_addr, deposit_coins)` - Receive funds from controller
- `harvest<CoinType>(harvester, vault_addr)` - Harvest yield and distribute
- `report_loss<CoinType>(vault_admin, vault_addr, loss_amount)` - Report losses

## Usage Examples

### 1. Deploy the System

```move
// Initialize insurance token
insurance_token::initialize(admin);

// Initialize trading pool with 1000 APT threshold
trading_pool::initialize<AptosCoin>(admin, 1000 * 100000000, controller_address);

// Initialize controller
let vault_addresses = vector[vault1_addr, vault2_addr, vault3_addr];
controller::initialize<AptosCoin>(admin, trading_pool_addr, insurance_admin_addr, vault_addresses);

// Initialize yield vaults
yield_vault::initialize<AptosCoin>(vault1_admin, controller_addr, 1, b"Lending Strategy", 200);
yield_vault::initialize<AptosCoin>(vault2_admin, controller_addr, 2, b"Liquidity Mining", 300);
yield_vault::initialize<AptosCoin>(vault3_admin, controller_addr, 3, b"Staking Strategy", 250);
```

### 2. User Operations

```move
// User deposits into trading pool
let deposit_coins = coin::withdraw<AptosCoin>(user, 500 * 100000000); // 500 APT
trading_pool::deposit<AptosCoin>(user, pool_admin_addr, deposit_coins);

// User mints insurance tokens
insurance_token::mint_insurance(user, insurance_admin_addr, 100 * 100000000); // 100 tokens

// User withdraws from pool
let pool_tokens_to_burn = 250 * 100000000; // Half of pool tokens
let withdrawn_coins = trading_pool::withdraw<AptosCoin>(user, pool_admin_addr, pool_tokens_to_burn);
```

### 3. Vault Operations

```move
// Harvest yield from vault
yield_vault::harvest<AptosCoin>(harvester, vault_addr);

// Report loss from vault
yield_vault::report_loss<AptosCoin>(vault_admin, vault_addr, 50 * 100000000); // 50 APT loss
```

## Testing

The system includes comprehensive tests covering:

- Full system integration flow
- Insurance token operations
- Vault strategy implementations
- Controller fund allocation
- Profit/loss distribution mechanisms

Run tests with:
```bash
aptos move test
```



### Key Parameters

- **Insurance Allocation**: 10% of all deposits
- **Vault Allocation**: 30% each to three vaults
- **Profit Insurance Share**: 5% of all profits
- **Maximum Performance Fee**: 20% (2000 basis points)

### Threshold Settings

- **Pool Threshold**: Configurable amount that triggers fund transfer to controller
- **Performance Fees**: Configurable per vault (0-20%)


## Future Enhancements

Potential improvements could include:
- Additional yield strategies
- Dynamic allocation percentages
- Governance mechanisms
- Cross-chain bridge support
- Advanced risk management
- Automated rebalancing

## License
