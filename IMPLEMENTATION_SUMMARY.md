# PULLEY Smart Contracts Implementation Summary

## Overview
The PULLEY contracts have been successfully updated to implement a floating stablecoin insurance system with external trading integration. The key changes align with the requirements for Merkle trade integration and Blocklock automation.

## Key Changes Made

### 1. Insurance Token (PULLEY/PUL) - Converted to Fungible Asset (FA)

**File:** `sources/insurance_token.move`

- **Replaced Coin standard with Fungible Asset (FA) standard**
- **Token Details:**
  - Name: "PULLEY Insurance Token" 
  - Symbol: "PUL"
  - Decimals: 8
  - Floating stablecoin design

- **Dual Minting System:**
  - `mint_external()`: Anyone can mint PULLEY tokens outside trading
  - `mint_insurance()`: Only authorized controllers can mint for trading insurance
  - Separate tracking: `total_external_supply` and `total_insurance_supply`

- **Key Features:**
  - Market utilization tracking for floating price calculation
  - Loss absorption mechanism (burns insurance tokens)
  - Profit distribution (mints additional insurance tokens)
  - Comprehensive event system with mint types

### 2. Controller - Updated for 15%/85% Split and External Trading

**File:** `sources/controller.move`

- **Fund Allocation Changed:**
  - 15% to insurance (mints PULLEY tokens)
  - 85% to trading address (for external Merkle trading)
  - Removed vault system entirely

- **New Architecture:**
  - Added `trading_address` field (admin-controlled)
  - Integrated with PULLEY insurance token minting
  - Profit/Loss distribution: 10% insurance, 90% traders

- **Blocklock Integration Functions:**
  - `has_funds_to_allocate()`: Check if funds available
  - `allocate_available_funds()`: Trigger allocation
  - Automation-friendly event system

### 3. Trading Pool - Enhanced for Automation

**File:** `sources/trading_pool.move`

- **Automation Features:**
  - `transfer_to_controller()`: Manual trigger for fund transfer
  - `is_threshold_met()`: Check if threshold reached
  - Enhanced event system for Blocklock monitoring

- **Unchanged Core Logic:**
  - Deposit/withdrawal mechanisms remain the same
  - Pool token system intact
  - Threshold-based transfers to controller

### 4. Removed Components

- **Deleted:** `sources/yield_vault.move` (no longer needed)
- **Removed:** All vault-related functionality from controller
- **Eliminated:** Yield generation logic from insurance token

## Integration Points

### PULLEY Token Flow
1. **External Minting:** Anyone → `mint_external()` → Increases `total_external_supply`
2. **Trading Insurance:** Controller → `mint_insurance()` → Increases `total_insurance_supply`
3. **Loss Absorption:** Burns insurance tokens from `total_insurance_supply`
4. **Profit Distribution:** Mints additional tokens to `total_insurance_supply`

### Fund Flow Architecture
```
Users Deposit → Trading Pool → (Threshold Met) → Controller
                                                     ↓
                                         ┌─ 15% Insurance (Mint PULLEY)
                                         └─ 85% Trading Address (External)
```

### Profit/Loss Handling
```
External Trading Results → Controller
                            ↓
                  ┌─ Profit: 10% Insurance, 90% Traders
                  └─ Loss: Insurance Absorbs (Burns PULLEY)
```

## Blocklock Automation Ready

### Key Functions for Automation:
1. **Trading Pool:**
   - `is_threshold_met()`: Monitor threshold status
   - `transfer_to_controller()`: Trigger fund transfer

2. **Controller:**
   - `has_funds_to_allocate()`: Check allocation readiness  
   - `allocate_available_funds()`: Trigger allocation
   - `report_profit()` / `report_loss()`: Handle trading results

3. **Insurance Token:**
   - Automatic integration with controller operations
   - Real-time loss absorption and profit distribution

## Testing Suite

### Comprehensive Test Coverage
The implementation includes a full test suite covering all major functionality:

#### Insurance Token Tests (`sources/tests/insurance_token_tests.move`)
- ✅ Module initialization and metadata setup
- ✅ External minting (anyone can mint PULLEY)
- ✅ Insurance minting (controller-only)
- ✅ Loss absorption mechanism (token burning)
- ✅ Profit deposit (token minting)
- ✅ Market utilization updates
- ✅ Authorization controls and access restrictions

#### Controller Tests (`sources/tests/controller_tests.move`)
- ✅ Controller initialization with all addresses
- ✅ Fund allocation (15%/85% split with PULLEY minting)
- ✅ Profit reporting (10% insurance, 90% traders)
- ✅ Loss reporting with insurance integration
- ✅ Trading address management
- ✅ Blocklock automation helper functions

#### Trading Pool Tests (`sources/tests/trading_pool_tests.move`)
- ✅ Pool initialization and configuration
- ✅ User deposits with proportional pool tokens
- ✅ Multi-user proportional token allocation
- ✅ Threshold detection and monitoring
- ✅ Automated fund transfers to controller
- ✅ User withdrawals with proportional share calculation
- ✅ Administrative functions (threshold/controller updates)

### Running Tests
```bash
# Run all tests
aptos move test

# Run specific modules
aptos move test --filter insurance_token_tests
aptos move test --filter controller_tests
aptos move test --filter trading_pool_tests
```

### Test Results
All tests pass successfully, ensuring:
- Proper fund flows and allocations
- Correct PULLEY token minting/burning
- Authorization and access controls
- Mathematical accuracy in proportional calculations
- Integration between all contract components

## Mermaid Diagrams Integration

The documentation includes three comprehensive Mermaid diagrams:

1. **System Flow Diagram**: Shows complete user journey and automation flow
2. **PULLEY Token Economics**: Illustrates dual supply system and price mechanisms  
3. **Automated Operation Sequence**: Details the fully automated trading cycle

These diagrams are embedded in the README and provide visual understanding of:
- User interactions and fund flows
- AI trading bot integration with Merkle
- Nodit API integration for P&L tracking
- Blocklock automation triggers and monitoring
- PULLEY token supply dynamics and floating price mechanism

## Configuration for Deployment

### Required Addresses:
- **Admin Address**: Controls all contracts
- **Trading Pool Address**: Where users deposit
- **Insurance Admin Address**: Manages PULLEY tokens
- **Trading Address**: Receives 85% for external trading (admin-controlled)

### Integration Notes:
- All operations except deposit/withdraw can be automated via Blocklock
- API integration ready for Merkle trade result reporting
- Event system provides comprehensive monitoring capabilities
- Trust-minimized design (trading address controlled by admin but funds flow is automated)

## Next Steps for Integration

1. **Deploy Contracts** with proper address configuration
2. **Set up Blocklock Automation** for:
   - Threshold monitoring and fund transfers
   - Profit/loss reporting based on API results
   - Automatic fund allocation
3. **Develop API Integration** for Merkle trade result fetching
4. **Configure External Trading Bot** to use the trading address

The contracts are now fully prepared for the automated trading system with PULLEY as the floating stablecoin insurance mechanism, complete with comprehensive testing and visual documentation.