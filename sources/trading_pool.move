/// Trading Pool Contract
/// Users can deposit funds and receive pool tokens representing their share
/// Enhanced with oracle pricing, continuous periods, and comprehensive user tracking
module pulley::trading_pool {
    use std::signer;
    use std::string;
    use aptos_framework::coin::{Self, Coin, MintCapability, BurnCapability, FreezeCapability};
    use aptos_framework::account;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::timestamp;
    use aptos_std::table::{Self, Table};
    use pulley::price_oracle;

    /// Error codes
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_INSUFFICIENT_BALANCE: u64 = 2;
    const E_INVALID_AMOUNT: u64 = 3;
    const E_POOL_NOT_INITIALIZED: u64 = 4;
    const E_THRESHOLD_NOT_MET: u64 = 5;
    const E_CONTROLLER_NOT_SET: u64 = 6;
    const E_UNSUPPORTED_ASSET: u64 = 7;
    const E_INSUFFICIENT_POOL_TOKENS: u64 = 8;
    const E_NO_ACTIVE_TRADING_PERIOD: u64 = 9;
    const E_PERIOD_NOT_COMPLETED: u64 = 10;
    const E_PROFIT_ALREADY_CLAIMED: u64 = 11;
    const E_NO_CONTRIBUTION_IN_PERIOD: u64 = 12;

    /// Pool token struct
    struct PoolToken has key {}

    /// Pool token capabilities
    struct PoolCapabilities has key {
        mint_cap: MintCapability<PoolToken>,
        burn_cap: BurnCapability<PoolToken>,
        freeze_cap: FreezeCapability<PoolToken>,
    }

    /// Trading period structure
    struct TradingPeriod has store {
        start_time: u64,
        end_time: u64,
        total_usd_value_at_start: u64,
        is_active: bool,
        profits_distributed: bool,
        period_pnl: i64, // Positive for profit, negative for loss
        profit_per_dollar: u64, // Profit per dollar contributed (18 decimals)
        insurance_refund_per_dollar: u64, // Insurance refund per dollar (18 decimals)
        insurance_refund_amount: u64,
        user_usd_contribution_at_start: Table<address, u64>,
        user_tokens_at_start: Table<address, u64>,
        user_profit_claimed: Table<address, bool>,
    }

    /// Trading pool state
    struct TradingPool<phantom CoinType> has key {
        total_deposited: u64,
        total_pool_tokens: u64,
        total_pool_value: u64, // Total USD value in pool
        threshold_amount: u64,
        controller_address: address,
        admin_address: address,
        is_active: bool,
        last_controller_transfer: u64,
        
        // Asset management
        asset_balances: Table<address, u64>,
        supported_assets: Table<address, bool>,
        asset_thresholds: Table<address, u64>,
        asset_decimals: Table<address, u8>,
        asset_list: vector<address>,
        
        // User tracking
        user_deposits: Table<address, u64>,
        user_pool_tokens: Table<address, u64>,
        user_asset_deposits: Table<address, Table<address, u64>>,
        
        // Trading periods - continuous periods support
        asset_periods: Table<address, Table<u64, TradingPeriod>>,
        asset_current_period_id: Table<address, u64>,
        asset_active_periods: Table<address, vector<u64>>,
        asset_available_for_trading: Table<address, u64>,
        period_asset_allocation: Table<address, Table<u64, u64>>,
        
        // Pool metrics
        total_profits: u64,
        total_losses: u64,
        insurance_funds: u64,
        total_losses_covered: u64,
        total_insurance_refunds: u64,
        
        // Events
        deposit_events: EventHandle<DepositEvent>,
        withdrawal_events: EventHandle<WithdrawalEvent>,
        controller_transfer_events: EventHandle<ControllerTransferEvent>,
        profit_distribution_events: EventHandle<ProfitDistributionEvent>,
        trading_period_events: EventHandle<TradingPeriodEvent>,
        user_joined_period_events: EventHandle<UserJoinedPeriodEvent>,
        profit_claimed_events: EventHandle<ProfitClaimedEvent>,
        insurance_refund_events: EventHandle<InsuranceRefundEvent>,
    }

    /// Events
    struct DepositEvent has drop, store {
        user: address,
        asset: address,
        amount: u64,
        pool_tokens_minted: u64,
        usd_value: u64,
        timestamp: u64,
    }

    struct WithdrawalEvent has drop, store {
        user: address,
        asset: address,
        amount: u64,
        pool_tokens_burned: u64,
        timestamp: u64,
    }

    struct ControllerTransferEvent has drop, store {
        asset: address,
        amount_transferred: u64,
        period_id: u64,
        timestamp: u64,
    }

    struct ProfitDistributionEvent has drop, store {
        asset: address,
        profit_amount: u64,
        period_id: u64,
        timestamp: u64,
    }

    struct TradingPeriodEvent has drop, store {
        asset: address,
        period_id: u64,
        start_time: u64,
        end_time: u64,
        total_value: u64,
        pnl: i64,
        is_active: bool,
    }

    struct UserJoinedPeriodEvent has drop, store {
        user: address,
        asset: address,
        period_id: u64,
        usd_contribution: u64,
        timestamp: u64,
    }

    struct ProfitClaimedEvent has drop, store {
        user: address,
        asset: address,
        period_id: u64,
        profit_amount: u64,
        reinvested: bool,
        timestamp: u64,
    }

    struct InsuranceRefundEvent has drop, store {
        asset: address,
        refund_amount: u64,
        period_id: u64,
        timestamp: u64,
    }

    struct AssetAddedEvent has drop, store {
        asset: address,
        decimals: u8,
        threshold: u64,
        price_feed: address,
    }

    struct AssetRemovedEvent has drop, store {
        asset: address,
    }

    struct ThresholdUpdatedEvent has drop, store {
        new_threshold: u64,
    }

    struct PriceFeedUpdatedEvent has drop, store {
        asset: address,
        price_feed: address,
    }

    /// Initialize the trading pool
    public fun initialize<CoinType>(
        admin: &signer,
        threshold_amount: u64,
        controller_address: address,
    ) {
        let admin_addr = signer::address_of(admin);
        
        // Initialize pool token
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<PoolToken>(
            admin,
            string::utf8(b"Pulley Pool Token"),
            string::utf8(b"PPT"),
            8, // decimals
            true, // monitor_supply
        );

        // Store pool token capabilities
        move_to(admin, PoolCapabilities {
            mint_cap,
            burn_cap,
            freeze_cap,
        });

        // Initialize trading pool state
        move_to(admin, TradingPool<CoinType> {
            total_deposited: 0,
            total_pool_tokens: 0,
            total_pool_value: 0,
            threshold_amount,
            controller_address,
            admin_address: admin_addr,
            is_active: true,
            last_controller_transfer: 0,
            
            // Asset management
            asset_balances: table::new(),
            supported_assets: table::new(),
            asset_thresholds: table::new(),
            asset_decimals: table::new(),
            asset_list: vector::empty(),
            
            // User tracking
            user_deposits: table::new(),
            user_pool_tokens: table::new(),
            user_asset_deposits: table::new(),
            
            // Trading periods
            asset_periods: table::new(),
            asset_current_period_id: table::new(),
            asset_active_periods: table::new(),
            asset_available_for_trading: table::new(),
            period_asset_allocation: table::new(),
            
            // Pool metrics
            total_profits: 0,
            total_losses: 0,
            insurance_funds: 0,
            total_losses_covered: 0,
            total_insurance_refunds: 0,
            
            // Events
            deposit_events: account::new_event_handle<DepositEvent>(admin),
            withdrawal_events: account::new_event_handle<WithdrawalEvent>(admin),
            controller_transfer_events: account::new_event_handle<ControllerTransferEvent>(admin),
            profit_distribution_events: account::new_event_handle<ProfitDistributionEvent>(admin),
            trading_period_events: account::new_event_handle<TradingPeriodEvent>(admin),
            user_joined_period_events: account::new_event_handle<UserJoinedPeriodEvent>(admin),
            profit_claimed_events: account::new_event_handle<ProfitClaimedEvent>(admin),
            insurance_refund_events: account::new_event_handle<InsuranceRefundEvent>(admin),
        });
    }

    /// Deposit funds into the trading pool with oracle pricing
    public fun deposit<CoinType>(
        user: &signer,
        admin_addr: address,
        asset: address,
        deposit_coins: Coin<CoinType>,
    ) acquires TradingPool, PoolCapabilities {
        let user_addr = signer::address_of(user);
        assert!(exists<TradingPool<CoinType>>(admin_addr), E_POOL_NOT_INITIALIZED);
        
        let pool = borrow_global_mut<TradingPool<CoinType>>(admin_addr);
        assert!(pool.is_active, E_NOT_AUTHORIZED);
        assert!(table::contains(&pool.supported_assets, asset), E_UNSUPPORTED_ASSET);
        
        let deposit_amount = coin::value(&deposit_coins);
        assert!(deposit_amount > 0, E_INVALID_AMOUNT);
        
        // Get USD value using oracle
        let usd_value = price_oracle::get_asset_usd_value(asset, deposit_amount);
        assert!(usd_value > 0, E_INVALID_AMOUNT);
        
        // Calculate pool tokens based on current pool state
        let pool_tokens_to_mint = if (pool.total_pool_tokens == 0) {
            // First deposit, minus min share to prevent share manipulation
            usd_value - 100000000 // 1e8 = 1 USD in 8 decimals
        } else {
            // Subsequent deposits: proportional to pool value
            (usd_value * pool.total_pool_tokens) / pool.total_pool_value
        };
        
        // Deposit the coins
        coin::deposit(admin_addr, deposit_coins);
        
        // Mint pool tokens to user
        let caps = borrow_global<PoolCapabilities>(admin_addr);
        let pool_tokens = coin::mint<PoolToken>(pool_tokens_to_mint, &caps.mint_cap);
        coin::deposit(user_addr, pool_tokens);
        
        // Update balances
        if (table::contains(&pool.asset_balances, asset)) {
            let current_balance = table::borrow_mut(&mut pool.asset_balances, asset);
            *current_balance = *current_balance + deposit_amount;
        } else {
            table::add(&mut pool.asset_balances, asset, deposit_amount);
        };
        
        // Update user tracking
        if (table::contains(&pool.user_deposits, user_addr)) {
            let current_deposit = table::borrow_mut(&mut pool.user_deposits, user_addr);
            *current_deposit = *current_deposit + deposit_amount;
        } else {
            table::add(&mut pool.user_deposits, user_addr, deposit_amount);
        };
        
        if (table::contains(&pool.user_pool_tokens, user_addr)) {
            let current_tokens = table::borrow_mut(&mut pool.user_pool_tokens, user_addr);
            *current_tokens = *current_tokens + pool_tokens_to_mint;
        } else {
            table::add(&mut pool.user_pool_tokens, user_addr, pool_tokens_to_mint);
        };
        
        // Update user asset deposits
        if (!table::contains(&pool.user_asset_deposits, user_addr)) {
            table::add(&mut pool.user_asset_deposits, user_addr, table::new());
        };
        let user_asset_deposits = table::borrow_mut(&mut pool.user_asset_deposits, user_addr);
        if (table::contains(user_asset_deposits, asset)) {
            let current_asset_deposit = table::borrow_mut(user_asset_deposits, asset);
            *current_asset_deposit = *current_asset_deposit + deposit_amount;
        } else {
            table::add(user_asset_deposits, asset, deposit_amount);
        };
        
        // Update pool state
        pool.total_deposited = pool.total_deposited + usd_value;
        pool.total_pool_tokens = pool.total_pool_tokens + pool_tokens_to_mint;
        pool.total_pool_value = pool.total_pool_value + usd_value;
        
        // Update available funds for trading (continuous periods)
        if (table::contains(&pool.asset_available_for_trading, asset)) {
            let available = table::borrow_mut(&mut pool.asset_available_for_trading, asset);
            *available = *available + usd_value;
        } else {
            table::add(&mut pool.asset_available_for_trading, asset, usd_value);
        };
        
        // Record user contribution for current trading period
        record_user_contribution_for_period(pool, user_addr, asset, usd_value);
        
        // Emit event
        event::emit_event(&mut pool.deposit_events, DepositEvent {
            user: user_addr,
            asset,
            amount: deposit_amount,
            pool_tokens_minted: pool_tokens_to_mint,
            usd_value,
            timestamp: timestamp::now_microseconds(),
        });
        
        // Check if we can start a new trading period
        check_and_start_new_trading_period(pool, asset);
    }

    /// Record user contribution for current trading period
    fun record_user_contribution_for_period(
        pool: &mut TradingPool<CoinType>,
        user_addr: address,
        asset: address,
        usd_contribution: u64,
    ) {
        // Get or create current period ID
        if (!table::contains(&pool.asset_current_period_id, asset)) {
            table::add(&mut pool.asset_current_period_id, asset, 0);
        };
        
        let current_period_id = table::borrow(&pool.asset_current_period_id, asset);
        if (*current_period_id == 0) {
            // Start first trading period for this asset
            let new_period_id = *current_period_id + 1;
            table::upsert(&mut pool.asset_current_period_id, asset, new_period_id);
            
            // Create new trading period
            if (!table::contains(&pool.asset_periods, asset)) {
                table::add(&mut pool.asset_periods, asset, table::new());
            };
            let asset_periods = table::borrow_mut(&mut pool.asset_periods, asset);
            table::add(asset_periods, new_period_id, TradingPeriod {
                start_time: timestamp::now_microseconds(),
                end_time: 0,
                total_usd_value_at_start: 0,
                is_active: true,
                profits_distributed: false,
                period_pnl: 0,
                profit_per_dollar: 0,
                insurance_refund_per_dollar: 0,
                insurance_refund_amount: 0,
                user_usd_contribution_at_start: table::new(),
                user_tokens_at_start: table::new(),
                user_profit_claimed: table::new(),
            });
            
            // Add to active periods
            if (!table::contains(&pool.asset_active_periods, asset)) {
                table::add(&mut pool.asset_active_periods, asset, vector::empty());
            };
            let active_periods = table::borrow_mut(&mut pool.asset_active_periods, asset);
            vector::push_back(active_periods, new_period_id);
            
            // Emit event
            event::emit_event(&mut pool.trading_period_events, TradingPeriodEvent {
                asset,
                period_id: new_period_id,
                start_time: timestamp::now_microseconds(),
                end_time: 0,
                total_value: 0,
                pnl: 0,
                is_active: true,
            });
        };
        
        // Get current period
        let current_period_id = *table::borrow(&pool.asset_current_period_id, asset);
        let asset_periods = table::borrow_mut(&mut pool.asset_periods, asset);
        let period = table::borrow_mut(asset_periods, current_period_id);
        
        // Record user's contribution for this period
        if (!table::contains(&period.user_usd_contribution_at_start, user_addr)) {
            table::add(&mut period.user_usd_contribution_at_start, user_addr, 0);
            table::add(&mut period.user_tokens_at_start, user_addr, 0);
        };
        
        let user_contribution = table::borrow_mut(&mut period.user_usd_contribution_at_start, user_addr);
        *user_contribution = *user_contribution + usd_contribution;
        
        // Update period total
        period.total_usd_value_at_start = period.total_usd_value_at_start + usd_contribution;
        
        // Emit event
        event::emit_event(&mut pool.user_joined_period_events, UserJoinedPeriodEvent {
            user: user_addr,
            asset,
            period_id: current_period_id,
            usd_contribution,
            timestamp: timestamp::now_microseconds(),
        });
    }

    /// Check if we can start a new trading period
    fun check_and_start_new_trading_period(
        pool: &mut TradingPool<CoinType>,
        asset: address,
    ) {
        if (!table::contains(&pool.asset_available_for_trading, asset)) {
            return
        };
        
        let available_funds = *table::borrow(&pool.asset_available_for_trading, asset);
        let asset_threshold = *table::borrow(&pool.asset_thresholds, asset);
        
        if (available_funds >= asset_threshold) {
            // Start new trading period with threshold amount
            start_new_trading_period(pool, asset, asset_threshold);
        };
    }

    /// Start a new trading period for an asset
    fun start_new_trading_period(
        pool: &mut TradingPool<CoinType>,
        asset: address,
        amount: u64,
    ) {
        // Increment period ID
        let current_period_id = if (table::contains(&pool.asset_current_period_id, asset)) {
            *table::borrow(&pool.asset_current_period_id, asset)
        } else {
            0
        };
        let new_period_id = current_period_id + 1;
        table::upsert(&mut pool.asset_current_period_id, asset, new_period_id);
        
        // Create new trading period
        if (!table::contains(&pool.asset_periods, asset)) {
            table::add(&mut pool.asset_periods, asset, table::new());
        };
        let asset_periods = table::borrow_mut(&mut pool.asset_periods, asset);
        table::add(asset_periods, new_period_id, TradingPeriod {
            start_time: timestamp::now_microseconds(),
            end_time: 0,
            total_usd_value_at_start: amount,
            is_active: true,
            profits_distributed: false,
            period_pnl: 0,
            profit_per_dollar: 0,
            insurance_refund_per_dollar: 0,
            insurance_refund_amount: 0,
            user_usd_contribution_at_start: table::new(),
            user_tokens_at_start: table::new(),
            user_profit_claimed: table::new(),
        });
        
        // Track this period as active
        if (!table::contains(&pool.asset_active_periods, asset)) {
            table::add(&mut pool.asset_active_periods, asset, vector::empty());
        };
        let active_periods = table::borrow_mut(&mut pool.asset_active_periods, asset);
        vector::push_back(active_periods, new_period_id);
        
        // Track allocation
        if (!table::contains(&pool.period_asset_allocation, asset)) {
            table::add(&mut pool.period_asset_allocation, asset, table::new());
        };
        let period_allocations = table::borrow_mut(&mut pool.period_asset_allocation, asset);
        table::add(period_allocations, new_period_id, amount);
        
        // Reduce available funds
        let available = table::borrow_mut(&mut pool.asset_available_for_trading, asset);
        *available = *available - amount;
        
        // Emit event
        event::emit_event(&mut pool.trading_period_events, TradingPeriodEvent {
            asset,
            period_id: new_period_id,
            start_time: timestamp::now_microseconds(),
            end_time: 0,
            total_value: amount,
            pnl: 0,
            is_active: true,
        });
        
        // Send funds to controller for this period
        send_funds_to_controller_for_period(pool, asset, amount, new_period_id);
    }

    /// Send funds to controller for a specific trading period
    fun send_funds_to_controller_for_period(
        pool: &mut TradingPool<CoinType>,
        asset: address,
        amount: u64,
        period_id: u64,
    ) {
        if (pool.controller_address == @0x0) return;
        
        // Update balances (don't reset to 0, just reduce by amount)
        let asset_balance = table::borrow_mut(&mut pool.asset_balances, asset);
        *asset_balance = *asset_balance - amount;
        pool.total_pool_value = pool.total_pool_value - amount;
        
        // Emit event
        event::emit_event(&mut pool.controller_transfer_events, ControllerTransferEvent {
            asset,
            amount_transferred: amount,
            period_id,
            timestamp: timestamp::now_microseconds(),
        });
    }

    /// Check threshold and transfer funds to controller (internal function)
    fun check_and_transfer_to_controller<CoinType>(admin_addr: address) acquires TradingPool {
        let pool = borrow_global_mut<TradingPool<CoinType>>(admin_addr);
        
        if (pool.total_deposited >= pool.threshold_amount) {
            let current_balance = coin::balance<CoinType>(admin_addr);
            if (current_balance > 0) {
                // Note: Fund transfer to controller should be done by admin via transfer_to_controller function
                
                pool.last_controller_transfer = timestamp::now_microseconds();
                
                // Emit event to signal that transfer is ready
                event::emit_event(&mut pool.controller_transfer_events, ControllerTransferEvent {
                    amount_transferred: current_balance,
                    new_pool_balance: 0,
                    timestamp: timestamp::now_microseconds(),
                });
            };
        };
    }

    /// Transfer funds to controller (for Blocklock automation)
    public fun transfer_to_controller<CoinType>(
        admin: &signer,
        admin_addr: address,
    ) acquires TradingPool {
        let admin_address = signer::address_of(admin);
        assert!(exists<TradingPool<CoinType>>(admin_addr), E_POOL_NOT_INITIALIZED);
        
        let pool = borrow_global<TradingPool<CoinType>>(admin_addr);
        assert!(admin_address == pool.admin_address, E_NOT_AUTHORIZED);
        assert!(pool.total_deposited >= pool.threshold_amount, E_THRESHOLD_NOT_MET);
        
        let current_balance = coin::balance<CoinType>(admin_addr);
        if (current_balance > 0) {
            let transfer_coins = coin::withdraw<CoinType>(admin, current_balance);
            coin::deposit(pool.controller_address, transfer_coins);
        };
    }

    /// Check if threshold is met (for Blocklock automation)
    public fun is_threshold_met<CoinType>(admin_addr: address): bool acquires TradingPool {
        assert!(exists<TradingPool<CoinType>>(admin_addr), E_POOL_NOT_INITIALIZED);
        let pool = borrow_global<TradingPool<CoinType>>(admin_addr);
        pool.total_deposited >= pool.threshold_amount
    }

    /// Withdraw funds from the trading pool
    public fun withdraw<CoinType>(
        user: &signer,
        admin_addr: address,
        pool_tokens_to_burn: u64,
    ): Coin<CoinType> acquires TradingPool, PoolCapabilities {
        let user_addr = signer::address_of(user);
        assert!(exists<TradingPool<CoinType>>(admin_addr), E_POOL_NOT_INITIALIZED);
        
        let pool = borrow_global_mut<TradingPool<CoinType>>(admin_addr);
        assert!(pool_tokens_to_burn > 0, E_INVALID_AMOUNT);
        
        // Calculate withdrawal amount: (pool_tokens_to_burn * total_deposited) / total_pool_tokens
        let withdrawal_amount = (pool_tokens_to_burn * pool.total_deposited) / pool.total_pool_tokens;
        
        // Burn pool tokens
        let caps = borrow_global<PoolCapabilities>(admin_addr);
        let pool_tokens = coin::withdraw<PoolToken>(user, pool_tokens_to_burn);
        coin::burn(pool_tokens, &caps.burn_cap);
        
        // Note: Withdrawal should be done by admin signer
        // For now, return empty coin as placeholder
        let withdrawal_coins = coin::zero<CoinType>();
        
        // Update pool state
        pool.total_deposited = pool.total_deposited - withdrawal_amount;
        pool.total_pool_tokens = pool.total_pool_tokens - pool_tokens_to_burn;
        
        // Update user deposit tracking
        if (table::contains(&pool.user_deposits, user_addr)) {
            let current_deposit = table::borrow_mut(&mut pool.user_deposits, user_addr);
            *current_deposit = if (*current_deposit > withdrawal_amount) {
                *current_deposit - withdrawal_amount
            } else {
                0
            };
        };
        
        // Emit event
        event::emit_event(&mut pool.withdrawal_events, WithdrawalEvent {
            user: user_addr,
            amount: withdrawal_amount,
            pool_tokens_burned: pool_tokens_to_burn,
            timestamp: timestamp::now_microseconds(),
        });
        
        withdrawal_coins
    }

    /// Distribute profit to the pool (called by controller)
    public fun distribute_profit<CoinType>(
        controller: &signer,
        admin_addr: address,
        profit_coins: Coin<CoinType>,
        insurance_share: u64,
    ) acquires TradingPool {
        let controller_addr = signer::address_of(controller);
        assert!(exists<TradingPool<CoinType>>(admin_addr), E_POOL_NOT_INITIALIZED);
        
        let pool = borrow_global_mut<TradingPool<CoinType>>(admin_addr);
        assert!(controller_addr == pool.controller_address, E_NOT_AUTHORIZED);
        
        let total_profit = coin::value(&profit_coins);
        let pool_share = total_profit - insurance_share;
        
        // Deposit profit to pool
        coin::deposit(admin_addr, profit_coins);
        pool.total_deposited = pool.total_deposited + pool_share;
        
        // Emit event
        event::emit_event(&mut pool.profit_distribution_events, ProfitDistributionEvent {
            profit_amount: total_profit,
            insurance_share,
            pool_share,
            timestamp: timestamp::now_microseconds(),
        });
    }

    /// Update threshold amount (admin only)
    public fun update_threshold<CoinType>(
        admin: &signer,
        new_threshold: u64,
    ) acquires TradingPool {
        let admin_addr = signer::address_of(admin);
        assert!(exists<TradingPool<CoinType>>(admin_addr), E_POOL_NOT_INITIALIZED);
        
        let pool = borrow_global_mut<TradingPool<CoinType>>(admin_addr);
        assert!(admin_addr == pool.admin_address, E_NOT_AUTHORIZED);
        
        pool.threshold_amount = new_threshold;
    }

    /// Update controller address (admin only)
    public fun update_controller<CoinType>(
        admin: &signer,
        new_controller: address,
    ) acquires TradingPool {
        let admin_addr = signer::address_of(admin);
        assert!(exists<TradingPool<CoinType>>(admin_addr), E_POOL_NOT_INITIALIZED);
        
        let pool = borrow_global_mut<TradingPool<CoinType>>(admin_addr);
        assert!(admin_addr == pool.admin_address, E_NOT_AUTHORIZED);
        
        pool.controller_address = new_controller;
    }

    /// Get pool information
    public fun get_pool_info<CoinType>(admin_addr: address): (u64, u64, u64, bool) acquires TradingPool {
        assert!(exists<TradingPool<CoinType>>(admin_addr), E_POOL_NOT_INITIALIZED);
        let pool = borrow_global<TradingPool<CoinType>>(admin_addr);
        (pool.total_deposited, pool.total_pool_tokens, pool.threshold_amount, pool.is_active)
    }

    /// Get user's pool token balance and deposit amount
    public fun get_user_info<CoinType>(admin_addr: address, user_addr: address): (u64, u64) acquires TradingPool {
        assert!(exists<TradingPool<CoinType>>(admin_addr), E_POOL_NOT_INITIALIZED);
        let pool = borrow_global<TradingPool<CoinType>>(admin_addr);
        
        let user_deposit = if (table::contains(&pool.user_deposits, user_addr)) {
            *table::borrow(&pool.user_deposits, user_addr)
        } else {
            0
        };
        
        let pool_token_balance = coin::balance<PoolToken>(user_addr);
        (user_deposit, pool_token_balance)
    }

    /// Add supported asset with decimals and threshold
    public fun add_asset<CoinType>(
        admin: &signer,
        admin_addr: address,
        asset: address,
        decimals: u8,
        asset_threshold: u64,
        price_feed: address,
    ) acquires TradingPool {
        let admin_address = signer::address_of(admin);
        assert!(exists<TradingPool<CoinType>>(admin_addr), E_POOL_NOT_INITIALIZED);
        
        let pool = borrow_global_mut<TradingPool<CoinType>>(admin_addr);
        assert!(admin_address == pool.admin_address, E_NOT_AUTHORIZED);
        assert!(asset != @0x0, E_INVALID_AMOUNT);
        assert!(asset_threshold > 0, E_INVALID_AMOUNT);
        
        if (!table::contains(&pool.supported_assets, asset)) {
            table::add(&mut pool.supported_assets, asset, true);
            table::add(&mut pool.asset_decimals, asset, decimals);
            table::add(&mut pool.asset_thresholds, asset, asset_threshold);
            vector::push_back(&mut pool.asset_list, asset);
            
            // Emit event
            event::emit_event(&mut pool.deposit_events, AssetAddedEvent {
                asset,
                decimals,
                threshold: asset_threshold,
                price_feed,
            });
        };
    }

    /// Remove supported asset
    public fun remove_asset<CoinType>(
        admin: &signer,
        admin_addr: address,
        asset: address,
    ) acquires TradingPool {
        let admin_address = signer::address_of(admin);
        assert!(exists<TradingPool<CoinType>>(admin_addr), E_POOL_NOT_INITIALIZED);
        
        let pool = borrow_global_mut<TradingPool<CoinType>>(admin_addr);
        assert!(admin_address == pool.admin_address, E_NOT_AUTHORIZED);
        
        if (table::contains(&pool.supported_assets, asset)) {
            table::remove(&mut pool.supported_assets, asset);
            table::remove(&mut pool.asset_decimals, asset);
            table::remove(&mut pool.asset_thresholds, asset);
            
            // Remove from array
            let (found, index) = vector::index_of(&pool.asset_list, &asset);
            if (found) {
                vector::remove(&mut pool.asset_list, index);
            };
            
            // Emit event
            event::emit_event(&mut pool.deposit_events, AssetRemovedEvent {
                asset,
            });
        };
    }

    /// Update threshold amount
    public fun update_threshold<CoinType>(
        admin: &signer,
        admin_addr: address,
        new_threshold: u64,
    ) acquires TradingPool {
        let admin_address = signer::address_of(admin);
        assert!(exists<TradingPool<CoinType>>(admin_addr), E_POOL_NOT_INITIALIZED);
        
        let pool = borrow_global_mut<TradingPool<CoinType>>(admin_addr);
        assert!(admin_address == pool.admin_address, E_NOT_AUTHORIZED);
        
        pool.threshold_amount = new_threshold;
        
        // Emit event
        event::emit_event(&mut pool.deposit_events, ThresholdUpdatedEvent {
            new_threshold,
        });
    }

    /// Update controller address
    public fun update_controller<CoinType>(
        admin: &signer,
        admin_addr: address,
        new_controller: address,
    ) acquires TradingPool {
        let admin_address = signer::address_of(admin);
        assert!(exists<TradingPool<CoinType>>(admin_addr), E_POOL_NOT_INITIALIZED);
        
        let pool = borrow_global_mut<TradingPool<CoinType>>(admin_addr);
        assert!(admin_address == pool.admin_address, E_NOT_AUTHORIZED);
        assert!(new_controller != @0x0, E_INVALID_AMOUNT);
        
        pool.controller_address = new_controller;
    }

    /// Set price feed for an asset
    public fun set_price_feed<CoinType>(
        admin: &signer,
        admin_addr: address,
        asset: address,
        price_feed: address,
    ) acquires TradingPool {
        let admin_address = signer::address_of(admin);
        assert!(exists<TradingPool<CoinType>>(admin_addr), E_POOL_NOT_INITIALIZED);
        
        let pool = borrow_global_mut<TradingPool<CoinType>>(admin_addr);
        assert!(admin_address == pool.admin_address, E_NOT_AUTHORIZED);
        
        // Emit event
        event::emit_event(&mut pool.deposit_events, PriceFeedUpdatedEvent {
            asset,
            price_feed,
        });
    }

    /// Distribute profit for a specific asset period
    public fun distribute_period_profit<CoinType>(
        controller: &signer,
        admin_addr: address,
        asset: address,
        period_id: u64,
        profit_amount: u64,
    ) acquires TradingPool {
        let controller_addr = signer::address_of(controller);
        assert!(exists<TradingPool<CoinType>>(admin_addr), E_POOL_NOT_INITIALIZED);
        
        let pool = borrow_global_mut<TradingPool<CoinType>>(admin_addr);
        assert!(controller_addr == pool.controller_address, E_NOT_AUTHORIZED);
        assert!(profit_amount > 0, E_INVALID_AMOUNT);
        
        // Get period
        let asset_periods = table::borrow_mut(&mut pool.asset_periods, asset);
        let period = table::borrow_mut(asset_periods, period_id);
        assert!(period.is_active, E_NO_ACTIVE_TRADING_PERIOD);
        
        // Calculate profit per dollar contributed
        if (period.total_usd_value_at_start > 0) {
            period.profit_per_dollar = (profit_amount * 100000000) / period.total_usd_value_at_start; // 1e8 = 1 USD
            period.period_pnl = (profit_amount as i64);
        };
        
        // End the period
        period.end_time = timestamp::now_microseconds();
        period.is_active = false;
        period.profits_distributed = true;
        
        // Remove from active periods list
        remove_active_period(pool, asset, period_id);
        
        // Update totals
        pool.total_profits = pool.total_profits + profit_amount;
        pool.total_pool_value = pool.total_pool_value + profit_amount;
        
        // Emit events
        event::emit_event(&mut pool.profit_distribution_events, ProfitDistributionEvent {
            asset,
            profit_amount,
            period_id,
            timestamp: timestamp::now_microseconds(),
        });
        
        event::emit_event(&mut pool.trading_period_events, TradingPeriodEvent {
            asset,
            period_id,
            start_time: period.start_time,
            end_time: period.end_time,
            total_value: period.total_usd_value_at_start,
            pnl: period.period_pnl,
            is_active: false,
        });
    }

    /// Distribute insurance refund to participants when losses occur
    public fun distribute_insurance_refund<CoinType>(
        controller: &signer,
        admin_addr: address,
        asset: address,
        refund_amount: u64,
    ) acquires TradingPool {
        let controller_addr = signer::address_of(controller);
        assert!(exists<TradingPool<CoinType>>(admin_addr), E_POOL_NOT_INITIALIZED);
        
        let pool = borrow_global_mut<TradingPool<CoinType>>(admin_addr);
        assert!(controller_addr == pool.controller_address, E_NOT_AUTHORIZED);
        assert!(refund_amount > 0, E_INVALID_AMOUNT);
        
        // Get the most recent active period for this asset
        let active_periods = table::borrow(&pool.asset_active_periods, asset);
        if (vector::length(active_periods) == 0) {
            abort E_NO_ACTIVE_TRADING_PERIOD
        };
        
        // Get the latest period (most recent)
        let latest_period_id = *vector::borrow(active_periods, vector::length(active_periods) - 1);
        let asset_periods = table::borrow_mut(&mut pool.asset_periods, asset);
        let period = table::borrow_mut(asset_periods, latest_period_id);
        
        assert!(period.is_active, E_NO_ACTIVE_TRADING_PERIOD);
        
        // Calculate refund per dollar contributed (15% of their contribution)
        let refund_per_dollar = if (period.total_usd_value_at_start > 0) {
            (refund_amount * 100000000) / period.total_usd_value_at_start // 1e8 = 1 USD
        } else {
            0
        };
        
        // Update period with refund information
        period.insurance_refund_per_dollar = refund_per_dollar;
        period.insurance_refund_amount = refund_amount;
        
        // Update pool totals
        pool.total_insurance_refunds = pool.total_insurance_refunds + refund_amount;
        
        // Emit event
        event::emit_event(&mut pool.insurance_refund_events, InsuranceRefundEvent {
            asset,
            refund_amount,
            period_id: latest_period_id,
            timestamp: timestamp::now_microseconds(),
        });
    }

    /// Remove a period from the active periods list
    fun remove_active_period(
        pool: &mut TradingPool<CoinType>,
        asset: address,
        period_id: u64,
    ) {
        let active_periods = table::borrow_mut(&mut pool.asset_active_periods, asset);
        let (found, index) = vector::index_of(active_periods, &period_id);
        if (found) {
            vector::remove(active_periods, index);
        };
    }

    /// Calculate user's profit/loss for a specific period
    public fun calculate_user_pnl<CoinType>(
        admin_addr: address,
        user: address,
        asset: address,
        period_id: u64,
    ): (u64, u64) acquires TradingPool {
        assert!(exists<TradingPool<CoinType>>(admin_addr), E_POOL_NOT_INITIALIZED);
        
        let pool = borrow_global<TradingPool<CoinType>>(admin_addr);
        let asset_periods = table::borrow(&pool.asset_periods, asset);
        let period = table::borrow(asset_periods, period_id);
        
        let user_contribution = if (table::contains(&period.user_usd_contribution_at_start, user)) {
            *table::borrow(&period.user_usd_contribution_at_start, user)
        } else {
            0
        };
        
        if (user_contribution == 0) {
            return (0, 0)
        };
        
        if (period.period_pnl > 0) {
            // Profit scenario
            let profit = (user_contribution * period.profit_per_dollar) / 100000000; // 1e8 = 1 USD
            (profit, 0)
        } else if (period.period_pnl < 0) {
            // Loss scenario
            let total_loss = (-period.period_pnl) as u64;
            let loss = if (period.total_usd_value_at_start > 0) {
                (user_contribution * total_loss) / period.total_usd_value_at_start
            } else {
                0
            };
            (0, loss)
        } else {
            (0, 0)
        }
    }

    /// Claim profit from a completed period
    public fun claim_period_profit<CoinType>(
        user: &signer,
        admin_addr: address,
        asset: address,
        period_id: u64,
        reinvest: bool,
    ) acquires TradingPool, PoolCapabilities {
        let user_addr = signer::address_of(user);
        assert!(exists<TradingPool<CoinType>>(admin_addr), E_POOL_NOT_INITIALIZED);
        
        let pool = borrow_global_mut<TradingPool<CoinType>>(admin_addr);
        let asset_periods = table::borrow_mut(&mut pool.asset_periods, asset);
        let period = table::borrow_mut(asset_periods, period_id);
        
        assert!(period.profits_distributed, E_PERIOD_NOT_COMPLETED);
        assert!(!table::contains(&period.user_profit_claimed, user_addr) || 
                !*table::borrow(&period.user_profit_claimed, user_addr), E_PROFIT_ALREADY_CLAIMED);
        assert!(table::contains(&period.user_usd_contribution_at_start, user_addr), E_NO_CONTRIBUTION_IN_PERIOD);
        
        let (profit, _) = calculate_user_pnl<CoinType>(admin_addr, user_addr, asset, period_id);
        if (profit == 0) return;
        
        // Mark as claimed
        if (!table::contains(&period.user_profit_claimed, user_addr)) {
            table::add(&mut period.user_profit_claimed, user_addr, true);
        } else {
            let claimed = table::borrow_mut(&mut period.user_profit_claimed, user_addr);
            *claimed = true;
        };
        
        if (reinvest) {
            // Mint additional pool tokens
            let current_price = if (pool.total_pool_value > 0) {
                (pool.total_pool_value * 100000000) / pool.total_pool_tokens // 1e8 = 1 USD
            } else {
                100000000 // 1 USD
            };
            let new_tokens = (profit * 100000000) / current_price;
            
            // Mint tokens
            let caps = borrow_global<PoolCapabilities>(admin_addr);
            let pool_tokens = coin::mint<PoolToken>(new_tokens, &caps.mint_cap);
            coin::deposit(user_addr, pool_tokens);
            
            // Update user tracking
            if (table::contains(&pool.user_pool_tokens, user_addr)) {
                let user_tokens = table::borrow_mut(&mut pool.user_pool_tokens, user_addr);
                *user_tokens = *user_tokens + new_tokens;
            } else {
                table::add(&mut pool.user_pool_tokens, user_addr, new_tokens);
            };
            
            pool.total_pool_tokens = pool.total_pool_tokens + new_tokens;
            
            // Emit event
            event::emit_event(&mut pool.profit_claimed_events, ProfitClaimedEvent {
                user: user_addr,
                asset,
                period_id,
                profit_amount: profit,
                reinvested: true,
                timestamp: timestamp::now_microseconds(),
            });
        } else {
            // Withdraw profit in the asset (simplified - would need asset conversion)
            // For now, just emit event
            event::emit_event(&mut pool.profit_claimed_events, ProfitClaimedEvent {
                user: user_addr,
                asset,
                period_id,
                profit_amount: profit,
                reinvested: false,
                timestamp: timestamp::now_microseconds(),
            });
        };
    }

    /// Get pool information
    public fun get_pool_info<CoinType>(admin_addr: address): (u64, u64, u64, u64, u64, bool) acquires TradingPool {
        assert!(exists<TradingPool<CoinType>>(admin_addr), E_POOL_NOT_INITIALIZED);
        let pool = borrow_global<TradingPool<CoinType>>(admin_addr);
        (pool.total_deposited, pool.total_pool_tokens, pool.total_pool_value, pool.threshold_amount, pool.total_profits, pool.is_active)
    }

    /// Get user's pool token balance and deposit amount
    public fun get_user_info<CoinType>(admin_addr: address, user_addr: address): (u64, u64) acquires TradingPool {
        assert!(exists<TradingPool<CoinType>>(admin_addr), E_POOL_NOT_INITIALIZED);
        let pool = borrow_global<TradingPool<CoinType>>(admin_addr);
        
        let user_deposit = if (table::contains(&pool.user_deposits, user_addr)) {
            *table::borrow(&pool.user_deposits, user_addr)
        } else {
            0
        };
        
        let pool_token_balance = if (table::contains(&pool.user_pool_tokens, user_addr)) {
            *table::borrow(&pool.user_pool_tokens, user_addr)
        } else {
            0
        };
        
        (user_deposit, pool_token_balance)
    }

    /// Get supported assets
    public fun get_supported_assets<CoinType>(admin_addr: address): vector<address> acquires TradingPool {
        assert!(exists<TradingPool<CoinType>>(admin_addr), E_POOL_NOT_INITIALIZED);
        let pool = borrow_global<TradingPool<CoinType>>(admin_addr);
        pool.asset_list
    }

    /// Get asset balance and USD value
    public fun get_asset_info<CoinType>(admin_addr: address, asset: address): (u64, u64, u8) acquires TradingPool {
        assert!(exists<TradingPool<CoinType>>(admin_addr), E_POOL_NOT_INITIALIZED);
        let pool = borrow_global<TradingPool<CoinType>>(admin_addr);
        
        let balance = if (table::contains(&pool.asset_balances, asset)) {
            *table::borrow(&pool.asset_balances, asset)
        } else {
            0
        };
        
        let usd_value = price_oracle::get_asset_usd_value(asset, balance);
        let decimals = if (table::contains(&pool.asset_decimals, asset)) {
            *table::borrow(&pool.asset_decimals, asset)
        } else {
            8
        };
        
        (balance, usd_value, decimals)
    }

    /// Get user's asset deposits
    public fun get_user_asset_deposit<CoinType>(admin_addr: address, user: address, asset: address): u64 acquires TradingPool {
        assert!(exists<TradingPool<CoinType>>(admin_addr), E_POOL_NOT_INITIALIZED);
        let pool = borrow_global<TradingPool<CoinType>>(admin_addr);
        
        if (table::contains(&pool.user_asset_deposits, user)) {
            let user_asset_deposits = table::borrow(&pool.user_asset_deposits, user);
            if (table::contains(user_asset_deposits, asset)) {
                *table::borrow(user_asset_deposits, asset)
            } else {
                0
            }
        } else {
            0
        }
    }

    /// Get all active trading periods for an asset
    public fun get_active_periods<CoinType>(admin_addr: address, asset: address): vector<u64> acquires TradingPool {
        assert!(exists<TradingPool<CoinType>>(admin_addr), E_POOL_NOT_INITIALIZED);
        let pool = borrow_global<TradingPool<CoinType>>(admin_addr);
        
        if (table::contains(&pool.asset_active_periods, asset)) {
            *table::borrow(&pool.asset_active_periods, asset)
        } else {
            vector::empty()
        }
    }

    /// Get available funds for new trading periods
    public fun get_available_funds_for_trading<CoinType>(admin_addr: address, asset: address): u64 acquires TradingPool {
        assert!(exists<TradingPool<CoinType>>(admin_addr), E_POOL_NOT_INITIALIZED);
        let pool = borrow_global<TradingPool<CoinType>>(admin_addr);
        
        if (table::contains(&pool.asset_available_for_trading, asset)) {
            *table::borrow(&pool.asset_available_for_trading, asset)
        } else {
            0
        }
    }

    /// Check if an asset can start a new trading period
    public fun can_start_new_period<CoinType>(admin_addr: address, asset: address): (bool, u64, u64) acquires TradingPool {
        assert!(exists<TradingPool<CoinType>>(admin_addr), E_POOL_NOT_INITIALIZED);
        let pool = borrow_global<TradingPool<CoinType>>(admin_addr);
        
        let available_funds = if (table::contains(&pool.asset_available_for_trading, asset)) {
            *table::borrow(&pool.asset_available_for_trading, asset)
        } else {
            0
        };
        
        let asset_threshold = if (table::contains(&pool.asset_thresholds, asset)) {
            *table::borrow(&pool.asset_thresholds, asset)
        } else {
            0
        };
        
        let can_start = available_funds >= asset_threshold;
        (can_start, available_funds, asset_threshold)
    }

    /// Get period allocation for a specific period
    public fun get_period_allocation<CoinType>(admin_addr: address, asset: address, period_id: u64): u64 acquires TradingPool {
        assert!(exists<TradingPool<CoinType>>(admin_addr), E_POOL_NOT_INITIALIZED);
        let pool = borrow_global<TradingPool<CoinType>>(admin_addr);
        
        if (table::contains(&pool.period_asset_allocation, asset)) {
            let period_allocations = table::borrow(&pool.period_asset_allocation, asset);
            if (table::contains(period_allocations, period_id)) {
                *table::borrow(period_allocations, period_id)
            } else {
                0
            }
        } else {
            0
        }
    }

    #[test_only]
    public fun init_module_for_test<CoinType>(admin: &signer, threshold: u64, controller: address) {
        initialize<CoinType>(admin, threshold, controller);
    }
}
