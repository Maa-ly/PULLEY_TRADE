/// Controller Contract
/// Manages fund allocation: 15% to insurance, 85% to external trading address
/// Enhanced with AI wallet integration, signature verification, and PnL reporting
module pulley::controller {
    use std::signer;
    use std::vector;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::account;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::timestamp;
    use aptos_std::table::{Self, Table};
    use pulley::insurance_token;
    use pulley::ai_wallet;
    use pulley::trading_pool;

    /// Error codes
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_INSUFFICIENT_BALANCE: u64 = 2;
    const E_INVALID_AMOUNT: u64 = 3;
    const E_CONTROLLER_NOT_INITIALIZED: u64 = 4;
    const E_VAULT_NOT_REGISTERED: u64 = 5;
    const E_INVALID_VAULT_COUNT: u64 = 6;
    const E_AI_WALLET_NOT_SET: u64 = 7;
    const E_INVALID_SIGNATURE: u64 = 8;
    const E_TRADE_NOT_FOUND: u64 = 9;
    const E_UNSUPPORTED_ASSET: u64 = 10;

    /// Fund allocation percentages (basis points: 10000 = 100%)
    const INSURANCE_PERCENTAGE: u64 = 1500; // 15% for insurance
    const TRADING_PERCENTAGE: u64 = 8500; // 85% for external trading
    const PROFIT_INSURANCE_PERCENTAGE: u64 = 1000; // 10% to insurance
    const PROFIT_TRADERS_PERCENTAGE: u64 = 9000; // 90% to traders

    /// Trade request structure
    struct TradeRequest has store {
        request_id: vector<u8>,
        asset: address,
        amount: u64,
        timestamp: u64,
        is_active: bool,
        result_pnl: i64, // Positive for profit, negative for loss
        is_completed: bool,
    }

    /// Controller state
    struct Controller<phantom CoinType> has key {
        admin_address: address,
        trading_pool_address: address,
        insurance_admin_address: address,
        ai_wallet_address: address, // AI trading wallet address
        total_managed_funds: u64,
        total_profits: u64,
        total_losses: u64,
        is_active: bool,
        
        // Asset management
        supported_assets: Table<address, bool>,
        asset_list: vector<address>,
        insurance_allocations: Table<address, u64>,
        trading_allocations: Table<address, u64>,
        
        // AI Trading tracking
        active_trade_requests: Table<vector<u8>, TradeRequest>,
        asset_profit_loss: Table<address, i64>, // Track P&L per asset
        
        // Events
        allocation_events: EventHandle<AllocationEvent>,
        profit_events: EventHandle<ProfitEvent>,
        loss_events: EventHandle<LossEvent>,
        trading_transfer_events: EventHandle<TradingTransferEvent>,
        trade_request_events: EventHandle<TradeRequestEvent>,
        trade_completed_events: EventHandle<TradeCompletedEvent>,
        ai_wallet_pnl_events: EventHandle<AIWalletPnLEvent>,
        automation_events: EventHandle<AutomationEvent>,
    }

    /// Events
    struct AllocationEvent has drop, store {
        asset: address,
        total_amount: u64,
        insurance_amount: u64,
        trading_amount: u64,
        timestamp: u64,
    }

    struct TradingTransferEvent has drop, store {
        asset: address,
        amount: u64,
        ai_wallet_address: address,
        timestamp: u64,
    }

    struct ProfitEvent has drop, store {
        asset: address,
        profit_amount: u64,
        insurance_share: u64,
        traders_share: u64,
        timestamp: u64,
    }

    struct LossEvent has drop, store {
        asset: address,
        loss_amount: u64,
        insurance_absorbed: u64,
        remaining_loss: u64,
        timestamp: u64,
    }

    struct TradeRequestEvent has drop, store {
        request_id: vector<u8>,
        asset: address,
        amount: u64,
        ai_wallet_address: address,
        timestamp: u64,
    }

    struct TradeCompletedEvent has drop, store {
        request_id: vector<u8>,
        asset: address,
        pnl: i64,
        is_profit: bool,
        timestamp: u64,
    }

    struct AIWalletPnLEvent has drop, store {
        asset: address,
        pnl: i64,
        funds_sent: bool,
        timestamp: u64,
    }

    struct AutomationEvent has drop, store {
        action: vector<u8>,
        timestamp: u64,
    }

    struct AssetSupportUpdatedEvent has drop, store {
        asset: address,
        supported: bool,
    }

    struct AIWalletUpdatedEvent has drop, store {
        old_wallet: address,
        new_wallet: address,
    }

    /// Initialize the controller
    public fun initialize<CoinType>(
        admin: &signer,
        trading_pool_address: address,
        insurance_admin_address: address,
        ai_wallet_address: address,
        supported_assets: vector<address>,
    ) {
        let admin_addr = signer::address_of(admin);
        
        // Initialize supported assets table
        let supported_assets_table = table::new<address, bool>();
        let i = 0;
        while (i < vector::length(&supported_assets)) {
            let asset = *vector::borrow(&supported_assets, i);
            table::add(&mut supported_assets_table, asset, true);
            i = i + 1;
        };
        
        move_to(admin, Controller<CoinType> {
            admin_address: admin_addr,
            trading_pool_address,
            insurance_admin_address,
            ai_wallet_address,
            total_managed_funds: 0,
            total_profits: 0,
            total_losses: 0,
            is_active: true,
            supported_assets: supported_assets_table,
            asset_list: supported_assets,
            insurance_allocations: table::new(),
            trading_allocations: table::new(),
            active_trade_requests: table::new(),
            asset_profit_loss: table::new(),
            allocation_events: account::new_event_handle<AllocationEvent>(admin),
            profit_events: account::new_event_handle<ProfitEvent>(admin),
            loss_events: account::new_event_handle<LossEvent>(admin),
            trading_transfer_events: account::new_event_handle<TradingTransferEvent>(admin),
            trade_request_events: account::new_event_handle<TradeRequestEvent>(admin),
            trade_completed_events: account::new_event_handle<TradeCompletedEvent>(admin),
            ai_wallet_pnl_events: account::new_event_handle<AIWalletPnLEvent>(admin),
            automation_events: account::new_event_handle<AutomationEvent>(admin),
        });

        // Note: Insurance authorization should be done separately by the insurance admin
    }

    /// Receive funds from trading pool and allocate them
    public fun receive_funds<CoinType>(
        pool_signer: &signer,
        controller_addr: address,
        asset: address,
        amount: u64,
    ) acquires Controller {
        assert!(exists<Controller<CoinType>>(controller_addr), E_CONTROLLER_NOT_INITIALIZED);
        
        let controller = borrow_global_mut<Controller<CoinType>>(controller_addr);
        let pool_addr = signer::address_of(pool_signer);
        assert!(pool_addr == controller.trading_pool_address, E_NOT_AUTHORIZED);
        assert!(controller.is_active, E_NOT_AUTHORIZED);
        assert!(table::contains(&controller.supported_assets, asset), E_UNSUPPORTED_ASSET);
        assert!(amount > 0, E_INVALID_AMOUNT);
        
        // Calculate allocation amounts: 15% insurance, 85% trading
        let insurance_amount = (amount * INSURANCE_PERCENTAGE) / 10000;
        let trading_amount = amount - insurance_amount;
        
        // Update allocations
        if (table::contains(&controller.insurance_allocations, asset)) {
            let current_insurance = table::borrow_mut(&mut controller.insurance_allocations, asset);
            *current_insurance = *current_insurance + insurance_amount;
        } else {
            table::add(&mut controller.insurance_allocations, asset, insurance_amount);
        };
        
        if (table::contains(&controller.trading_allocations, asset)) {
            let current_trading = table::borrow_mut(&mut controller.trading_allocations, asset);
            *current_trading = *current_trading + trading_amount;
        } else {
            table::add(&mut controller.trading_allocations, asset, trading_amount);
        };
        
        controller.total_managed_funds = controller.total_managed_funds + amount;
        
        // Send insurance portion to insurance pool
        if (insurance_amount > 0) {
            // Mint insurance tokens for trading
            insurance_token::mint_insurance(pool_signer, controller.insurance_admin_address, insurance_amount);
        };
        
        // Trigger automated AI trading for trading portion
        if (trading_amount > 0) {
            initiate_ai_trading(controller, asset, trading_amount);
        };
        
        // Emit allocation event
        event::emit_event(&mut controller.allocation_events, AllocationEvent {
            asset,
            total_amount: amount,
            insurance_amount,
            trading_amount,
            timestamp: timestamp::now_microseconds(),
        });
    }

    /// Allocate funds received from trading pool: 15% to insurance, 85% to trading address
    public fun allocate_funds<CoinType>(
        pool_signer: &signer,
        controller_addr: address,
        funds: Coin<CoinType>,
    ) acquires Controller {
        let amount = coin::value(&funds);
        let asset = @0x0; // Simplified - would need to determine asset type
        
        // Extract funds and call receive_funds
        coin::deposit(controller_addr, funds);
        receive_funds<CoinType>(pool_signer, controller_addr, asset, amount);
    }

    /// Report profit from external trading: 10% to insurance, 90% to traders
    public fun report_profit<CoinType>(
        admin: &signer,
        controller_addr: address,
        profit_coins: Coin<CoinType>,
    ) acquires Controller {
        let admin_addr = signer::address_of(admin);
        assert!(exists<Controller<CoinType>>(controller_addr), E_CONTROLLER_NOT_INITIALIZED);
        
        let controller = borrow_global_mut<Controller<CoinType>>(controller_addr);
        assert!(admin_addr == controller.admin_address, E_NOT_AUTHORIZED);
        
        let profit_amount = coin::value(&profit_coins);
        assert!(profit_amount > 0, E_INVALID_AMOUNT);
        
        // Calculate profit distribution: 10% to insurance, 90% to traders
        let insurance_share = (profit_amount * PROFIT_INSURANCE_PERCENTAGE) / 10000;
        let traders_share = profit_amount - insurance_share;
        
        // Split profit
        let insurance_coins = coin::extract(&mut profit_coins, insurance_share);
        
        // Deposit insurance share and mint PULLEY insurance tokens
        coin::deposit(controller.insurance_admin_address, insurance_coins);
        
        // Deposit profit into insurance (this will mint more PULLEY tokens)
        insurance_token::deposit_profit(admin, controller.insurance_admin_address, insurance_share);
        
        // Send remaining profit to trading pool for distribution to traders
        coin::deposit(controller.trading_pool_address, profit_coins);
        // Note: Profit distribution should be called separately by trading pool
        
        controller.total_profits = controller.total_profits + profit_amount;
        
        // Emit event
        event::emit_event(&mut controller.profit_events, ProfitEvent {
            profit_amount,
            insurance_share,
            traders_share,
            timestamp: timestamp::now_microseconds(),
        });
    }

    /// Report loss from external trading - insurance absorbs losses
    public fun report_loss<CoinType>(
        admin: &signer,
        controller_addr: address,
        loss_amount: u64,
    ) acquires Controller {
        let admin_addr = signer::address_of(admin);
        assert!(exists<Controller<CoinType>>(controller_addr), E_CONTROLLER_NOT_INITIALIZED);
        
        let controller = borrow_global_mut<Controller<CoinType>>(controller_addr);
        assert!(admin_addr == controller.admin_address, E_NOT_AUTHORIZED);
        assert!(loss_amount > 0, E_INVALID_AMOUNT);
        
        // Try to absorb loss with insurance first
        let remaining_loss = insurance_token::absorb_loss(admin, controller.insurance_admin_address, loss_amount);
        
        let insurance_absorbed = loss_amount - remaining_loss;
        
        controller.total_losses = controller.total_losses + loss_amount;
        
        // Emit event
        event::emit_event(&mut controller.loss_events, LossEvent {
            loss_amount,
            insurance_absorbed,
            remaining_loss,
            timestamp: timestamp::now_microseconds(),
        });
    }

    /// Update trading address (admin only)
    public fun update_trading_address<CoinType>(
        admin: &signer,
        controller_addr: address,
        new_trading_address: address,
    ) acquires Controller {
        let admin_addr = signer::address_of(admin);
        assert!(exists<Controller<CoinType>>(controller_addr), E_CONTROLLER_NOT_INITIALIZED);
        
        let controller = borrow_global_mut<Controller<CoinType>>(controller_addr);
        assert!(admin_addr == controller.admin_address, E_NOT_AUTHORIZED);
        
        controller.trading_address = new_trading_address;
    }

    /// Get controller information
    public fun get_controller_info<CoinType>(controller_addr: address): (u64, u64, u64, bool, address) acquires Controller {
        assert!(exists<Controller<CoinType>>(controller_addr), E_CONTROLLER_NOT_INITIALIZED);
        let controller = borrow_global<Controller<CoinType>>(controller_addr);
        (controller.total_managed_funds, controller.total_profits, controller.total_losses, controller.is_active, controller.trading_address)
    }

    /// Get trading address
    public fun get_trading_address<CoinType>(controller_addr: address): address acquires Controller {
        assert!(exists<Controller<CoinType>>(controller_addr), E_CONTROLLER_NOT_INITIALIZED);
        let controller = borrow_global<Controller<CoinType>>(controller_addr);
        controller.trading_address
    }

    // Removed earlier duplicate of has_funds_to_allocate; unified below.

    /// Trigger fund allocation from controller balance (for Blocklock automation)
    public fun allocate_available_funds<CoinType>(
        admin: &signer,
        controller_addr: address,
    ) acquires Controller {
        let admin_addr = signer::address_of(admin);
        assert!(exists<Controller<CoinType>>(controller_addr), E_CONTROLLER_NOT_INITIALIZED);
        
        let controller = borrow_global<Controller<CoinType>>(controller_addr);
        assert!(admin_addr == controller.admin_address, E_NOT_AUTHORIZED);
        
        let balance = coin::balance<CoinType>(controller_addr);
        if (balance > 0) {
            let funds = coin::withdraw<CoinType>(admin, balance);
            // Note: This would need to be called as pool_signer, but this is for Blocklock automation
            // allocate_funds<CoinType>(admin, controller_addr, funds);
            
            // For now, just re-deposit the funds
            coin::deposit(controller_addr, funds);
        };
    }

    /// Toggle controller active status (admin only)
    public fun toggle_active<CoinType>(admin: &signer) acquires Controller {
        let admin_addr = signer::address_of(admin);
        assert!(exists<Controller<CoinType>>(admin_addr), E_CONTROLLER_NOT_INITIALIZED);
        
        let controller = borrow_global_mut<Controller<CoinType>>(admin_addr);
        assert!(admin_addr == controller.admin_address, E_NOT_AUTHORIZED);
        
        controller.is_active = !controller.is_active;
    }

    /// Initiate AI trading
    fun initiate_ai_trading<CoinType>(
        controller: &mut Controller<CoinType>,
        asset: address,
        amount: u64,
    ) {
        if (controller.ai_wallet_address == @0x0) return;
        
        // Generate request ID
        let request_id = generate_request_id(asset, amount);
        
        // Store trade request
        table::add(&mut controller.active_trade_requests, request_id, TradeRequest {
            request_id,
            asset,
            amount,
            timestamp: timestamp::now_microseconds(),
            is_active: true,
            result_pnl: 0,
            is_completed: false,
        });
        
        // Send funds to AI wallet
        // Note: In production, this would transfer actual coins to the AI wallet
        // For now, we'll just track the allocation
        
        // Emit event
        event::emit_event(&mut controller.trade_request_events, TradeRequestEvent {
            request_id,
            asset,
            amount,
            ai_wallet_address: controller.ai_wallet_address,
            timestamp: timestamp::now_microseconds(),
        });
    }

    /// Generate unique request ID
    fun generate_request_id(asset: address, amount: u64): vector<u8> {
        // Simplified request ID generation
        // In production, this would use proper hashing
        let request_id_part1 = std::bcs::to_bytes(&asset);
        let request_id_part2 = std::bcs::to_bytes(&amount);
        let request_id_part3 = std::bcs::to_bytes(&timestamp::now_microseconds());
        let combined1 = vector::concat(request_id_part1, request_id_part2);
        vector::concat(combined1, request_id_part3)
    }

    /// Check AI wallet PnL and handle funds
    public fun check_ai_wallet_pnl<CoinType>(
        admin: &signer,
        controller_addr: address,
        asset: address,
    ): (i64, bool) acquires Controller {
        let admin_addr = signer::address_of(admin);
        assert!(exists<Controller<CoinType>>(controller_addr), E_CONTROLLER_NOT_INITIALIZED);
        
        let controller = borrow_global_mut<Controller<CoinType>>(controller_addr);
        assert!(admin_addr == controller.admin_address, E_NOT_AUTHORIZED);
        assert!(controller.ai_wallet_address != @0x0, E_AI_WALLET_NOT_SET);
        
        // Get session info from AI wallet
        let (session_id, initial_balance, current_balance, pnl) = 
            ai_wallet::get_session_info<CoinType>(controller.ai_wallet_address, asset);
        
        let funds_sent = false;
        
        // If there's profit, call sendFunds to retrieve it
        if (pnl > 0 && current_balance > 0) {
            // Generate signature for sendFunds (simplified)
            let signature = vector::empty<u8>();
            
            // Call AI wallet's sendFunds function
            ai_wallet::send_funds<CoinType>(
                admin,
                controller.ai_wallet_address,
                asset,
                current_balance,
                signature
            );
            // funds_sent = true; // Would be set to true if successful
        };
        
        // If there's PnL (profit or loss), report it to the system
        if (pnl != 0) {
            // Generate request ID for this check
            let request_id = generate_request_id(asset, current_balance);
            
            // Report the PnL result
            report_trading_result(controller, request_id, pnl);
        };
        
        // Emit event
        event::emit_event(&mut controller.ai_wallet_pnl_events, AIWalletPnLEvent {
            asset,
            pnl,
            funds_sent,
            timestamp: timestamp::now_microseconds(),
        });
        
        (pnl, funds_sent)
    }

    /// Report trading result
    fun report_trading_result<CoinType>(
        controller: &mut Controller<CoinType>,
        request_id: vector<u8>,
        pnl: i64,
    ) {
        if (!table::contains(&controller.active_trade_requests, request_id)) return;
        
        let trade_request = table::borrow_mut(&mut controller.active_trade_requests, request_id);
        if (!trade_request.is_active) return;
        
        // Update trade request
        trade_request.result_pnl = pnl;
        trade_request.is_completed = true;
        trade_request.is_active = false;
        
        // Update asset P&L tracking
        if (table::contains(&controller.asset_profit_loss, trade_request.asset)) {
            let current_pnl = table::borrow_mut(&mut controller.asset_profit_loss, trade_request.asset);
            *current_pnl = *current_pnl + pnl;
        } else {
            table::add(&mut controller.asset_profit_loss, trade_request.asset, pnl);
        };
        
        if (pnl > 0) {
            // Profit case
            let profit = (pnl as u64);
            controller.total_profits = controller.total_profits + profit;
            distribute_profits(controller, trade_request.asset, profit);
            
            // Emit event
            event::emit_event(&mut controller.trade_completed_events, TradeCompletedEvent {
                request_id,
                asset: trade_request.asset,
                pnl,
                is_profit: true,
                timestamp: timestamp::now_microseconds(),
            });
        } else if (pnl < 0) {
            // Loss case
            let loss = (0 - pnl) as u64;
            controller.total_losses = controller.total_losses + loss;
            handle_trading_loss(controller, trade_request.asset, loss);
            
            // Emit event
            event::emit_event(&mut controller.trade_completed_events, TradeCompletedEvent {
                request_id,
                asset: trade_request.asset,
                pnl,
                is_profit: false,
                timestamp: timestamp::now_microseconds(),
            });
        };
    }

    /// Distribute profits between insurance and trading pool
    fun distribute_profits<CoinType>(
        controller: &mut Controller<CoinType>,
        asset: address,
        profit_amount: u64,
    ) {
        let insurance_share = (profit_amount * PROFIT_INSURANCE_PERCENTAGE) / 10000;
        let traders_share = profit_amount - insurance_share;
        
        // Send insurance share to insurance pool
        if (insurance_share > 0) {
            // Deposit profit into insurance (this will mint more PULLEY tokens)
            insurance_token::deposit_profit(
                &signer::create_signer(controller.admin_address),
                controller.insurance_admin_address,
                insurance_share
            );
        };
        
        // Send trading share back to trading pool
        if (traders_share > 0) {
            // Report profit back to trading pool
            trading_pool::distribute_period_profit<CoinType>(
                &signer::create_signer(controller.admin_address),
                controller.trading_pool_address,
                asset,
                1, // period_id - would need to track this properly
                traders_share
            );
        };
        
        // Emit event
        event::emit_event(&mut controller.profit_events, ProfitEvent {
            asset,
            profit_amount,
            insurance_share,
            traders_share,
            timestamp: timestamp::now_microseconds(),
        });
    }

    /// Handle trading losses
    fun handle_trading_loss<CoinType>(
        controller: &mut Controller<CoinType>,
        asset: address,
        loss_amount: u64,
    ) {
        let insurance_allocated = if (table::contains(&controller.insurance_allocations, asset)) {
            *table::borrow(&controller.insurance_allocations, asset)
        } else {
            0
        };
        
        let insurance_absorbed = if (insurance_allocated >= loss_amount) {
            loss_amount
        } else {
            insurance_allocated
        };
        
        let remaining_loss = loss_amount - insurance_absorbed;
        
        // Try to absorb loss with insurance first
        if (insurance_absorbed > 0) {
            let remaining_after_insurance = insurance_token::absorb_loss(
                &signer::create_signer(controller.admin_address),
                controller.insurance_admin_address,
                insurance_absorbed
            );
            
            // Update insurance allocation
            if (table::contains(&controller.insurance_allocations, asset)) {
                let current_insurance = table::borrow_mut(&mut controller.insurance_allocations, asset);
                *current_insurance = *current_insurance - insurance_absorbed;
            };
        };
        
        // Emit event
        event::emit_event(&mut controller.loss_events, LossEvent {
            asset,
            loss_amount,
            insurance_absorbed,
            remaining_loss,
            timestamp: timestamp::now_microseconds(),
        });
    }

    /// Update AI wallet address
    public fun update_ai_wallet<CoinType>(
        admin: &signer,
        controller_addr: address,
        new_ai_wallet: address,
    ) acquires Controller {
        let admin_addr = signer::address_of(admin);
        assert!(exists<Controller<CoinType>>(controller_addr), E_CONTROLLER_NOT_INITIALIZED);
        
        let controller = borrow_global_mut<Controller<CoinType>>(controller_addr);
        assert!(admin_addr == controller.admin_address, E_NOT_AUTHORIZED);
        assert!(new_ai_wallet != @0x0, E_INVALID_AMOUNT);
        
        let old_wallet = controller.ai_wallet_address;
        controller.ai_wallet_address = new_ai_wallet;
        
        // Emit event
        event::emit_event(&mut controller.automation_events, AIWalletUpdatedEvent {
            old_wallet,
            new_wallet: new_ai_wallet,
        });
    }

    /// Update asset support
    public fun update_asset_support<CoinType>(
        admin: &signer,
        controller_addr: address,
        asset: address,
        supported: bool,
    ) acquires Controller {
        let admin_addr = signer::address_of(admin);
        assert!(exists<Controller<CoinType>>(controller_addr), E_CONTROLLER_NOT_INITIALIZED);
        
        let controller = borrow_global_mut<Controller<CoinType>>(controller_addr);
        assert!(admin_addr == controller.admin_address, E_NOT_AUTHORIZED);
        
        if (supported && !table::contains(&controller.supported_assets, asset)) {
            table::add(&mut controller.supported_assets, asset, true);
            vector::push_back(&mut controller.asset_list, asset);
        } else if (!supported && table::contains(&controller.supported_assets, asset)) {
            table::remove(&mut controller.supported_assets, asset);
            // Remove from asset list
            let (found, index) = vector::index_of(&controller.asset_list, &asset);
            if (found) {
                vector::remove(&mut controller.asset_list, index);
            };
        };
        
        // Emit event
        event::emit_event(&mut controller.automation_events, AssetSupportUpdatedEvent {
            asset,
            supported,
        });
    }

    /// Get system metrics
    public fun get_system_metrics<CoinType>(controller_addr: address): (u64, u64, u64, u64) acquires Controller {
        assert!(exists<Controller<CoinType>>(controller_addr), E_CONTROLLER_NOT_INITIALIZED);
        let controller = borrow_global<Controller<CoinType>>(controller_addr);
        (controller.total_managed_funds, controller.total_profits, controller.total_losses, 0) // Last param would be total insurance funds
    }

    /// Get supported assets
    public fun get_supported_assets<CoinType>(controller_addr: address): vector<address> acquires Controller {
        assert!(exists<Controller<CoinType>>(controller_addr), E_CONTROLLER_NOT_INITIALIZED);
        let controller = borrow_global<Controller<CoinType>>(controller_addr);
        controller.asset_list
    }

    /// Check if asset is supported
    public fun is_asset_supported<CoinType>(controller_addr: address, asset: address): bool acquires Controller {
        assert!(exists<Controller<CoinType>>(controller_addr), E_CONTROLLER_NOT_INITIALIZED);
        let controller = borrow_global<Controller<CoinType>>(controller_addr);
        table::contains(&controller.supported_assets, asset)
    }

    /// Get fund allocation for an asset
    public fun get_fund_allocation<CoinType>(controller_addr: address, asset: address): (u64, u64) acquires Controller {
        assert!(exists<Controller<CoinType>>(controller_addr), E_CONTROLLER_NOT_INITIALIZED);
        let controller = borrow_global<Controller<CoinType>>(controller_addr);
        
        let insurance_amount = if (table::contains(&controller.insurance_allocations, asset)) {
            *table::borrow(&controller.insurance_allocations, asset)
        } else {
            0
        };
        
        let trading_amount = if (table::contains(&controller.trading_allocations, asset)) {
            *table::borrow(&controller.trading_allocations, asset)
        } else {
            0
        };
        
        (insurance_amount, trading_amount)
    }

    /// Get asset profit/loss
    public fun get_asset_pnl<CoinType>(controller_addr: address, asset: address): i64 acquires Controller {
        assert!(exists<Controller<CoinType>>(controller_addr), E_CONTROLLER_NOT_INITIALIZED);
        let controller = borrow_global<Controller<CoinType>>(controller_addr);
        
        if (table::contains(&controller.asset_profit_loss, asset)) {
            *table::borrow(&controller.asset_profit_loss, asset)
        } else {
            0
        }
    }

    /// Check if funds are available for allocation (for Blocklock automation)
    public fun has_funds_to_allocate<CoinType>(controller_addr: address): bool acquires Controller {
        assert!(exists<Controller<CoinType>>(controller_addr), E_CONTROLLER_NOT_INITIALIZED);
        coin::balance<CoinType>(controller_addr) > 0
    }

    // Removed earlier duplicate of allocate_available_funds; unified above.

    // Removed earlier duplicate of toggle_active; unified above.

    #[test_only]
    public fun init_module_for_test<CoinType>(
        admin: &signer,
        trading_pool: address,
        insurance_admin: address,
        ai_wallet: address,
        supported_assets: vector<address>
    ) {
        initialize<CoinType>(admin, trading_pool, insurance_admin, ai_wallet, supported_assets);
    }
}
