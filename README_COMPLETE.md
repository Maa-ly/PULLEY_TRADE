# Pulley Protocol - Complete Aptos Implementation

## Overview

This is a complete implementation of the Pulley Protocol on Aptos, ported from the original EVM version. The Pulley Protocol is a DeFi trading system that combines AI-driven strategies with insurance via a floating stablecoin, providing a comprehensive solution for automated trading with risk management.

## Architecture

### Core Components

1. **Trading Pool** (`trading_pool.move`)
   - Manages user deposits and withdrawals
   - Implements continuous trading periods
   - Handles profit distribution and insurance refunds
   - Integrates with price oracles for asset valuation

2. **Controller** (`controller.move`)
   - Central orchestrator for the protocol
   - Manages fund allocation (15% insurance, 85% trading)
   - Handles AI wallet integration and PnL reporting
   - Distributes profits and manages losses

3. **Insurance Token** (`insurance_token.move`)
   - Implements floating price mechanism
   - Manages growth algorithm and utilization rates
   - Provides dual minting logic (external and insurance)
   - Handles loss absorption via burning

4. **AI Wallet** (`ai_wallet.move`)
   - Manages AI trading sessions
   - Handles signature-based transfers
   - Provides session tracking and balance management
   - Integrates with controller for PnL reporting

5. **Clone Factory** (`clone_factory.move`)
   - Enables strategy creation and customization
   - Manages strategy configurations and parameters
   - Provides quick clone creation functionality
   - Tracks strategy instances and creators

6. **Permission Manager** (`permission_manager.move`)
   - Implements role-based access control
   - Manages user permissions and roles
   - Provides security for protocol operations
   - Supports custom role creation

7. **Price Oracle** (`price_oracle.move`)
   - Integrates with external price feeds
   - Provides asset valuation services
   - Manages price updates and validation
   - Supports batch operations and emergency updates

## Key Features

### 1. Continuous Trading Periods
- Trading pools manage multiple concurrent periods
- Threshold-based fund transfers to controller
- User contribution tracking per period
- Profit distribution and insurance refunds

### 2. Floating Stablecoin (PUL)
- Dynamic pricing based on utilization and performance
- Growth algorithm with configurable parameters
- Dual minting logic for external and insurance use
- Loss absorption mechanism via burning

### 3. AI Trading Integration
- External AI system interaction via AI Wallet
- Session-based trading management
- Signature-based fund transfers
- PnL reporting and tracking

### 4. Fund Allocation
- 15% allocated to insurance pool
- 85% allocated to AI trading
- Automatic rebalancing based on performance
- Profit distribution (10% insurance, 90% traders)

### 5. Clone Factory
- Create custom trading strategies
- Configurable parameters and assets
- Quick clone creation for common use cases
- Strategy management and tracking

### 6. Permission System
- Role-based access control
- Granular permission management
- Custom role creation
- Security for protocol operations

## Smart Contract Details

### Trading Pool Contract

**Key Functions:**
- `initialize(threshold, controller_address)` - Initialize trading pool
- `deposit(asset, amount)` - Deposit assets to pool
- `withdraw(asset, amount)` - Withdraw assets from pool
- `add_asset(asset, decimals, threshold, price_feed)` - Add supported asset
- `distribute_period_profit(asset, period_id)` - Distribute profits
- `claim_period_profit(asset, period_id)` - Claim user profits

**Data Structures:**
- `TradingPool` - Main pool state
- `TradingPeriod` - Individual trading period
- `UserContribution` - User contribution tracking

### Controller Contract

**Key Functions:**
- `initialize(trading_pool, insurance_admin, ai_wallet, supported_assets)` - Initialize controller
- `receive_funds(asset, amount)` - Receive funds from trading pool
- `initiate_ai_trading(asset, amount)` - Start AI trading
- `check_ai_wallet_pnl(asset, pnl)` - Check AI wallet PnL
- `distribute_profits(asset, profit)` - Distribute trading profits
- `handle_trading_loss(asset, loss)` - Handle trading losses

**Data Structures:**
- `Controller` - Main controller state
- `TradeRequest` - Trading request tracking
- `AssetAllocation` - Asset allocation tracking

### Insurance Token Contract

**Key Functions:**
- `mint_insurance(recipient, amount)` - Mint insurance tokens
- `burn(amount)` - Burn tokens for loss absorption
- `get_current_price()` - Get current token price
- `update_growth()` - Update growth algorithm
- `update_utilization(rate)` - Update utilization rate

**Data Structures:**
- `InsurancePool` - Insurance pool state
- `AssetBacking` - Asset backing tracking
- `GrowthMetrics` - Growth algorithm metrics

### AI Wallet Contract

**Key Functions:**
- `initialize(controller, ai_signer)` - Initialize AI wallet
- `receive_funds(asset, amount)` - Receive trading funds
- `send_funds(asset, amount, signature)` - Send funds with signature
- `get_session_info()` - Get current session info
- `update_session(session_id, balance)` - Update session

**Data Structures:**
- `AIWallet` - AI wallet state
- `SessionInfo` - Trading session information
- `TransferRequest` - Fund transfer request

### Clone Factory Contract

**Key Functions:**
- `create_strategy(name, symbol, threshold, assets, thresholds, decimals, price_feeds)` - Create strategy
- `quick_create_clone(native_asset, custom_asset, decimals, threshold)` - Quick clone
- `update_strategy_config(strategy, new_threshold)` - Update strategy
- `deactivate_strategy(strategy)` - Deactivate strategy
- `get_strategy_info(strategy)` - Get strategy information

**Data Structures:**
- `CloneFactory` - Factory state
- `StrategyConfig` - Strategy configuration
- `CloneConfig` - Clone configuration

### Permission Manager Contract

**Key Functions:**
- `assign_role(user, role_id)` - Assign role to user
- `revoke_role(user, role_id)` - Revoke role from user
- `create_role(role_id, name, permissions)` - Create custom role
- `has_permission(user, permission_id)` - Check user permission
- `has_role(user, role_id)` - Check user role

**Data Structures:**
- `PermissionManager` - Permission system state
- `Role` - Role definition
- `UserRole` - User role assignment

### Price Oracle Contract

**Key Functions:**
- `add_price_feed(asset, price_feed, decimals, confidence, max_deviation)` - Add price feed
- `update_price(asset, price)` - Update asset price
- `get_asset_usd_value(asset, amount)` - Get USD value
- `batch_update_prices(assets, prices)` - Batch update prices
- `emergency_update_price(asset, price)` - Emergency price update

**Data Structures:**
- `PriceOracle` - Oracle state
- `PriceFeed` - Price feed information
- `PriceUpdate` - Price update event

## Development

### Prerequisites

- Aptos CLI
- Move compiler
- Node.js (for testing)

### Setup

1. Clone the repository
2. Install dependencies
3. Initialize Aptos environment
4. Deploy contracts

### Testing

Run the comprehensive test suite:

```bash
aptos move test
```

The test suite includes:
- Unit tests for each contract
- Integration tests for system components
- End-to-end trading flow tests
- Error handling tests
- Permission system tests

### Deployment

1. Deploy core contracts in order:
   - Price Oracle
   - Permission Manager
   - Insurance Token
   - Trading Pool
   - Controller
   - AI Wallet
   - Clone Factory

2. Initialize contracts with proper addresses
3. Configure permissions and roles
4. Set up price feeds
5. Deploy and test

## Integration Points

### External Systems

1. **Price Feeds**
   - Pyth Network integration
   - Chainlink compatibility
   - Custom price feed support

2. **AI Trading Systems**
   - External AI wallet integration
   - Signature-based authentication
   - PnL reporting interface

3. **Automation**
   - Blocklock integration
   - Threshold monitoring
   - Automated operations

4. **Frontend**
   - Web3 wallet integration
   - User interface components
   - Real-time data display

### API Endpoints

- Trading pool operations
- Controller management
- Insurance token functions
- AI wallet interactions
- Clone factory operations
- Permission management
- Price oracle queries

## Economic Model

### Token Economics

- **PUL Token**: Floating stablecoin with dynamic pricing
- **Growth Algorithm**: Based on utilization and performance
- **Minting Logic**: Dual minting for external and insurance use
- **Burning Mechanism**: Loss absorption and price stability

### Fund Allocation

- **Insurance Pool**: 15% of total funds
- **Trading Pool**: 85% of total funds
- **Profit Distribution**: 10% insurance, 90% traders
- **Loss Handling**: Insurance pool covers losses

### Fee Structure

- **Trading Fees**: Configurable per strategy
- **Insurance Fees**: Based on risk assessment
- **Oracle Fees**: Price feed maintenance
- **Gas Fees**: Aptos network fees

## Security Considerations

### Access Control

- Role-based permissions
- Multi-signature requirements
- Time-locked operations
- Emergency pause functionality

### Risk Management

- Insurance pool coverage
- Loss absorption mechanisms
- Price oracle validation
- Automated risk monitoring

### Audit Requirements

- Smart contract audits
- Security reviews
- Penetration testing
- Continuous monitoring

## Roadmap

### Phase 1: Core Implementation ✅
- Basic contract deployment
- Core functionality implementation
- Testing and validation

### Phase 2: Integration
- External system integration
- Frontend development
- API implementation

### Phase 3: Optimization
- Performance optimization
- Gas efficiency improvements
- Advanced features

### Phase 4: Scaling
- Multi-chain deployment
- Advanced strategies
- Enterprise features

## Contributing

1. Fork the repository
2. Create feature branch
3. Implement changes
4. Add tests
5. Submit pull request

## License

MIT License - see LICENSE file for details

## Support

- Documentation: [Link to docs]
- Discord: [Link to Discord]
- GitHub Issues: [Link to issues]
- Email: [Contact email]

## Changelog

### v1.0.0 - Complete Aptos Implementation
- Full port from EVM to Aptos
- All core contracts implemented
- Comprehensive test suite
- Complete documentation
- Security audit ready

---

*This implementation provides a complete, production-ready version of the Pulley Protocol on Aptos, maintaining all the functionality and features of the original EVM version while leveraging Aptos-specific capabilities.*
