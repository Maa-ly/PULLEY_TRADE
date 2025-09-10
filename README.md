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

## System Flow

1. **User Deposit**: Users deposit assets into the trading pool
2. **Fund Allocation**: 15% goes to insurance, 85% to AI trading
3. **AI Trading**: AI system trades with allocated funds
4. **PnL Reporting**: AI reports profit/loss to controller
5. **Profit Distribution**: 10% to insurance, 90% to traders
6. **Loss Handling**: Insurance pool covers losses
7. **Token Growth**: PUL token price adjusts based on performance

## Token Economics

- **PUL Token**: Floating stablecoin with dynamic pricing
- **Growth Algorithm**: Based on utilization and performance
- **Minting Logic**: Dual minting for external and insurance use
- **Burning Mechanism**: Loss absorption and price stability

## Development

### Prerequisites
- Aptos CLI
- Move compiler
- Node.js

### Setup
1. Clone repository
2. Install dependencies
3. Initialize Aptos environment
4. Deploy contracts

### Testing
```bash
aptos move test
```

The test suite includes comprehensive coverage of all functionality.

## Deployment

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

## Integration

- **Price Feeds**: Pyth Network integration
- **AI Systems**: External AI wallet integration
- **Automation**: Blocklock integration
- **Frontend**: Web3 wallet integration

## Security

- Role-based access control
- Multi-signature requirements
- Time-locked operations
- Emergency pause functionality

## License

MIT License

## Contributing

1. Fork repository
2. Create feature branch
3. Implement changes
4. Add tests
5. Submit pull request

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