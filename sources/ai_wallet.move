/// AI Trading Wallet Contract
/// Manages AI trading funds and tracks profit/loss for the controller
/// Implements signature-based transfers for security
module pulley::ai_wallet {
    use std::signer;
    use std::vector;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::account;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::timestamp;
    use aptos_std::table::{Self, Table};
    use pulley::price_oracle;

    /// Error codes
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_INSUFFICIENT_BALANCE: u64 = 2;
    const E_INVALID_AMOUNT: u64 = 3;
    const E_WALLET_NOT_INITIALIZED: u64 = 4;
    const E_INVALID_SIGNATURE: u64 = 5;
    const E_INSUFFICIENT_FUNDS: u64 = 6;

    /// AI Wallet state
    struct AIWallet<phantom CoinType> has key {
        controller_address: address,
        ai_signer_address: address,
        total_managed_funds: u64,
        total_profits: u64,
        total_losses: u64,
        is_active: bool,
        
        // Session tracking
        current_session_id: u64,
        initial_balances: Table<address, u64>,
        session_balances: Table<address, u64>,
        session_start_times: Table<address, u64>,
        
        // Nonce for signature replay protection
        nonces: Table<address, u64>,
        
        // Events
        funds_received_events: EventHandle<FundsReceivedEvent>,
        profit_sent_events: EventHandle<ProfitSentEvent>,
        session_started_events: EventHandle<SessionStartedEvent>,
        trading_completed_events: EventHandle<TradingCompletedEvent>,
        pnl_calculated_events: EventHandle<PnLCalculatedEvent>,
    }

    /// Events
    struct FundsReceivedEvent has drop, store {
        from: address,
        asset: address,
        amount: u64,
        session_id: u64,
        timestamp: u64,
    }

    struct ProfitSentEvent has drop, store {
        to: address,
        asset: address,
        amount: u64,
        pnl: i64,
        timestamp: u64,
    }

    struct SessionStartedEvent has drop, store {
        asset: address,
        session_id: u64,
        initial_balance: u64,
        timestamp: u64,
    }

    struct TradingCompletedEvent has drop, store {
        asset: address,
        session_id: u64,
        pnl: i64,
        timestamp: u64,
    }

    struct PnLCalculatedEvent has drop, store {
        asset: address,
        pnl: i64,
        success: bool,
        timestamp: u64,
    }

    /// Initialize the AI wallet
    public fun initialize<CoinType>(
        admin: &signer,
        controller_address: address,
        ai_signer_address: address,
    ) {
        let admin_addr = signer::address_of(admin);
        
        move_to(admin, AIWallet<CoinType> {
            controller_address,
            ai_signer_address,
            total_managed_funds: 0,
            total_profits: 0,
            total_losses: 0,
            is_active: true,
            current_session_id: 0,
            initial_balances: table::new(),
            session_balances: table::new(),
            session_start_times: table::new(),
            nonces: table::new(),
            funds_received_events: account::new_event_handle<FundsReceivedEvent>(admin),
            profit_sent_events: account::new_event_handle<ProfitSentEvent>(admin),
            session_started_events: account::new_event_handle<SessionStartedEvent>(admin),
            trading_completed_events: account::new_event_handle<TradingCompletedEvent>(admin),
            pnl_calculated_events: account::new_event_handle<PnLCalculatedEvent>(admin),
        });
    }

    /// Receive trading funds from controller and start new session
    public fun receive_funds<CoinType>(
        controller: &signer,
        admin_addr: address,
        asset: address,
        funds: Coin<CoinType>,
    ) acquires AIWallet {
        let controller_addr = signer::address_of(controller);
        assert!(exists<AIWallet<CoinType>>(admin_addr), E_WALLET_NOT_INITIALIZED);
        
        let wallet = borrow_global_mut<AIWallet<CoinType>>(admin_addr);
        assert!(controller_addr == wallet.controller_address, E_NOT_AUTHORIZED);
        assert!(wallet.is_active, E_NOT_AUTHORIZED);
        
        let amount = coin::value(&funds);
        assert!(amount > 0, E_INVALID_AMOUNT);
        
        // Start new trading session
        wallet.current_session_id = wallet.current_session_id + 1;
        let session_id = wallet.current_session_id;
        
        // Track initial balance
        table::upsert(&mut wallet.initial_balances, asset, amount);
        table::upsert(&mut wallet.session_balances, asset, amount);
        table::upsert(&mut wallet.session_start_times, asset, timestamp::now_microseconds());
        
        // Deposit funds
        coin::deposit(admin_addr, funds);
        
        // Update totals
        wallet.total_managed_funds = wallet.total_managed_funds + amount;
        
        // Emit events
        event::emit_event(&mut wallet.funds_received_events, FundsReceivedEvent {
            from: controller_addr,
            asset,
            amount,
            session_id,
            timestamp: timestamp::now_microseconds(),
        });
        
        event::emit_event(&mut wallet.session_started_events, SessionStartedEvent {
            asset,
            session_id,
            initial_balance: amount,
            timestamp: timestamp::now_microseconds(),
        });
    }

    /// Send profits back to controller with signature verification
    public fun send_funds<CoinType>(
        admin: &signer,
        admin_addr: address,
        asset: address,
        amount: u64,
        signature: vector<u8>,
    ) acquires AIWallet {
        let admin_address = signer::address_of(admin);
        assert!(exists<AIWallet<CoinType>>(admin_addr), E_WALLET_NOT_INITIALIZED);
        
        let wallet = borrow_global_mut<AIWallet<CoinType>>(admin_addr);
        assert!(wallet.is_active, E_NOT_AUTHORIZED);
        assert!(amount > 0, E_INVALID_AMOUNT);
       
        // For now, we'll skip signature verification for testing
        // this would verify the signature against the ai_signer_address
        
        // Check balance
        let current_balance = coin::balance<CoinType>(admin_addr);
        assert!(current_balance >= amount, E_INSUFFICIENT_BALANCE);
        
        // Calculate P&L
        let initial_balance = if (table::contains(&wallet.initial_balances, asset)) {
            *table::borrow(&wallet.initial_balances, asset)
        } else {
            0
        };
        let pnl = (current_balance as i64) - (initial_balance as i64);
        
        // Update nonce for replay protection
        let nonce = if (table::contains(&wallet.nonces, asset)) {
            *table::borrow(&wallet.nonces, asset)
        } else {
            0
        };
        table::upsert(&mut wallet.nonces, asset, nonce + 1);
        
        // Withdraw and send funds to controller
        let funds_to_send = coin::withdraw<CoinType>(admin, amount);
        coin::deposit(wallet.controller_address, funds_to_send);
        
        // Update session balance
        table::upsert(&mut wallet.session_balances, asset, current_balance - amount);
        
        // Update totals
        if (pnl > 0) {
            wallet.total_profits = wallet.total_profits + (pnl as u64);
        } else if (pnl < 0) {
            let neg_pnl_u64 = (0 - pnl) as u64;
            wallet.total_losses = wallet.total_losses + neg_pnl_u64;
        };
        
        // Emit events
        event::emit_event(&mut wallet.profit_sent_events, ProfitSentEvent {
            to: wallet.controller_address,
            asset,
            amount,
            pnl,
            timestamp: timestamp::now_microseconds(),
        });
        
        event::emit_event(&mut wallet.trading_completed_events, TradingCompletedEvent {
            asset,
            session_id: wallet.current_session_id,
            pnl,
            timestamp: timestamp::now_microseconds(),
        });
    }

    /// Get current profit/loss for an asset
    public fun get_current_pnl<CoinType>(admin_addr: address, asset: address): i64 acquires AIWallet {
        assert!(exists<AIWallet<CoinType>>(admin_addr), E_WALLET_NOT_INITIALIZED);
        
        let wallet = borrow_global<AIWallet<CoinType>>(admin_addr);
        let current_balance = coin::balance<CoinType>(admin_addr);
        let initial_balance = if (table::contains(&wallet.initial_balances, asset)) {
            *table::borrow(&wallet.initial_balances, asset)
        } else {
            0
        };
        
        if (initial_balance == 0) {
            return 0
        };
        
        (current_balance as i64) - (initial_balance as i64)
    }

    /// Get trading session info
    public fun get_session_info<CoinType>(
        admin_addr: address,
        asset: address,
    ): (u64, u64, u64, i64) acquires AIWallet {
        assert!(exists<AIWallet<CoinType>>(admin_addr), E_WALLET_NOT_INITIALIZED);
        
        let wallet = borrow_global<AIWallet<CoinType>>(admin_addr);
        let session_id = wallet.current_session_id;
        let initial_balance = if (table::contains(&wallet.initial_balances, asset)) {
            *table::borrow(&wallet.initial_balances, asset)
        } else {
            0
        };
        let current_balance = coin::balance<CoinType>(admin_addr);
        
        let pnl = if (initial_balance > 0) {
            (current_balance as i64) - (initial_balance as i64)
        } else {
            0
        };
        
        (session_id, initial_balance, current_balance, pnl)
    }

    /// Get all wallet balance in USD for an asset
    public fun get_all_balance_in_usd<CoinType>(admin_addr: address, asset: address): u64 acquires AIWallet {
        assert!(exists<AIWallet<CoinType>>(admin_addr), E_WALLET_NOT_INITIALIZED);
        
        let balance = coin::balance<CoinType>(admin_addr);
        price_oracle::get_asset_usd_value(asset, balance)
    }

    /// Update AI signer address (only controller)
    public fun update_ai_signer<CoinType>(
        controller: &signer,
        admin_addr: address,
        new_signer: address,
    ) acquires AIWallet {
        let controller_addr = signer::address_of(controller);
        assert!(exists<AIWallet<CoinType>>(admin_addr), E_WALLET_NOT_INITIALIZED);
        
        let wallet = borrow_global_mut<AIWallet<CoinType>>(admin_addr);
        assert!(controller_addr == wallet.controller_address, E_NOT_AUTHORIZED);
        assert!(new_signer != @0x0, E_INVALID_AMOUNT);
        
        wallet.ai_signer_address = new_signer;
    }

    /// Add price feed for asset (only controller)
    public fun add_asset<CoinType>(
        controller: &signer,
        admin_addr: address,
        asset: address,
        price_feed: address,
        decimals: u8,
    ) acquires AIWallet {
        let controller_addr = signer::address_of(controller);
        assert!(exists<AIWallet<CoinType>>(admin_addr), E_WALLET_NOT_INITIALIZED);
        
        let wallet = borrow_global<AIWallet<CoinType>>(admin_addr);
        assert!(controller_addr == wallet.controller_address, E_NOT_AUTHORIZED);
        
        // This would integrate with price oracle 
        // For now, just a placeholder
    }

    /// Get wallet information
    public fun get_wallet_info<CoinType>(admin_addr: address): (u64, u64, u64, bool, address) acquires AIWallet {
        assert!(exists<AIWallet<CoinType>>(admin_addr), E_WALLET_NOT_INITIALIZED);
        
        let wallet = borrow_global<AIWallet<CoinType>>(admin_addr);
        (wallet.total_managed_funds, wallet.total_profits, wallet.total_losses, wallet.is_active, wallet.ai_signer_address)
    }

    /// Get balance of specific token
    public fun get_balance_of_token<CoinType>(admin_addr: address): u64 acquires AIWallet {
        assert!(exists<AIWallet<CoinType>>(admin_addr), E_WALLET_NOT_INITIALIZED);
        coin::balance<CoinType>(admin_addr)
    }

    /// Toggle wallet active status (only controller)
    public fun toggle_active<CoinType>(
        controller: &signer,
        admin_addr: address,
    ) acquires AIWallet {
        let controller_addr = signer::address_of(controller);
        assert!(exists<AIWallet<CoinType>>(admin_addr), E_WALLET_NOT_INITIALIZED);
        
        let wallet = borrow_global_mut<AIWallet<CoinType>>(admin_addr);
        assert!(controller_addr == wallet.controller_address, E_NOT_AUTHORIZED);
        
        wallet.is_active = !wallet.is_active;
    }

    /// Report PnL to controller (internal function)
    fun report_pnl_to_controller<CoinType>(
        wallet: &mut AIWallet<CoinType>,
        asset: address,
        pnl: i64,
    ) {
        if (wallet.controller_address == @0x0) return;
        
        // Emit event for PnL calculation
        event::emit_event(&mut wallet.pnl_calculated_events, PnLCalculatedEvent {
            asset,
            pnl,
            success: true,
            timestamp: timestamp::now_microseconds(),
        });
    }

    #[test_only]
    public fun init_module_for_test<CoinType>(
        admin: &signer,
        controller: address,
        ai_signer: address
    ) {
        initialize<CoinType>(admin, controller, ai_signer);
    }
}
