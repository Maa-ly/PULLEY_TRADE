/// Trading Pool Contract
/// Users can deposit funds and receive pool tokens representing their share
module pulley::trading_pool {
    use std::signer;
    use std::string;
    use aptos_framework::coin::{Self, Coin, MintCapability, BurnCapability, FreezeCapability};
    use aptos_framework::account;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::timestamp;
    use aptos_std::table::{Self, Table};

    /// Error codes
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_INSUFFICIENT_BALANCE: u64 = 2;
    const E_INVALID_AMOUNT: u64 = 3;
    const E_POOL_NOT_INITIALIZED: u64 = 4;
    const E_THRESHOLD_NOT_MET: u64 = 5;
    const E_CONTROLLER_NOT_SET: u64 = 6;

    /// Pool token struct
    struct PoolToken has key {}

    /// Pool token capabilities
    struct PoolCapabilities has key {
        mint_cap: MintCapability<PoolToken>,
        burn_cap: BurnCapability<PoolToken>,
        freeze_cap: FreezeCapability<PoolToken>,
    }

    /// Trading pool state
    struct TradingPool<phantom CoinType> has key {
        total_deposited: u64,
        total_pool_tokens: u64,
        threshold_amount: u64,
        controller_address: address,
        admin_address: address,
        is_active: bool,
        last_controller_transfer: u64,
        user_deposits: Table<address, u64>,
        deposit_events: EventHandle<DepositEvent>,
        withdrawal_events: EventHandle<WithdrawalEvent>,
        controller_transfer_events: EventHandle<ControllerTransferEvent>,
        profit_distribution_events: EventHandle<ProfitDistributionEvent>,
    }

    /// Events
    struct DepositEvent has drop, store {
        user: address,
        amount: u64,
        pool_tokens_minted: u64,
        timestamp: u64,
    }

    struct WithdrawalEvent has drop, store {
        user: address,
        amount: u64,
        pool_tokens_burned: u64,
        timestamp: u64,
    }

    struct ControllerTransferEvent has drop, store {
        amount_transferred: u64,
        new_pool_balance: u64,
        timestamp: u64,
    }

    struct ProfitDistributionEvent has drop, store {
        profit_amount: u64,
        insurance_share: u64,
        pool_share: u64,
        timestamp: u64,
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
            threshold_amount,
            controller_address,
            admin_address: admin_addr,
            is_active: true,
            last_controller_transfer: 0,
            user_deposits: table::new(),
            deposit_events: account::new_event_handle<DepositEvent>(admin),
            withdrawal_events: account::new_event_handle<WithdrawalEvent>(admin),
            controller_transfer_events: account::new_event_handle<ControllerTransferEvent>(admin),
            profit_distribution_events: account::new_event_handle<ProfitDistributionEvent>(admin),
        });
    }

    /// Deposit funds into the trading pool
    public fun deposit<CoinType>(
        user: &signer,
        admin_addr: address,
        deposit_coins: Coin<CoinType>,
    ) acquires TradingPool, PoolCapabilities {
        let user_addr = signer::address_of(user);
        assert!(exists<TradingPool<CoinType>>(admin_addr), E_POOL_NOT_INITIALIZED);
        
        let pool = borrow_global_mut<TradingPool<CoinType>>(admin_addr);
        assert!(pool.is_active, E_NOT_AUTHORIZED);
        
        let deposit_amount = coin::value(&deposit_coins);
        assert!(deposit_amount > 0, E_INVALID_AMOUNT);
        
        // Calculate pool tokens to mint (1:1 ratio initially, proportional after)
        let pool_tokens_to_mint = if (pool.total_pool_tokens == 0) {
            deposit_amount
        } else {
            // Calculate proportional share: (deposit_amount * total_pool_tokens) / total_deposited
            (deposit_amount * pool.total_pool_tokens) / pool.total_deposited
        };
        
        // Deposit the coins
        coin::deposit(admin_addr, deposit_coins);
        
        // Mint pool tokens to user
        let caps = borrow_global<PoolCapabilities>(admin_addr);
        let pool_tokens = coin::mint<PoolToken>(pool_tokens_to_mint, &caps.mint_cap);
        coin::deposit(user_addr, pool_tokens);
        
        // Update pool state
        pool.total_deposited = pool.total_deposited + deposit_amount;
        pool.total_pool_tokens = pool.total_pool_tokens + pool_tokens_to_mint;
        
        // Update user deposit tracking
        if (table::contains(&pool.user_deposits, user_addr)) {
            let current_deposit = table::borrow_mut(&mut pool.user_deposits, user_addr);
            *current_deposit = *current_deposit + deposit_amount;
        } else {
            table::add(&mut pool.user_deposits, user_addr, deposit_amount);
        };
        
        // Emit event
        event::emit_event(&mut pool.deposit_events, DepositEvent {
            user: user_addr,
            amount: deposit_amount,
            pool_tokens_minted: pool_tokens_to_mint,
            timestamp: timestamp::now_microseconds(),
        });
        
        // Check if threshold is met and transfer to controller if needed
        check_and_transfer_to_controller<CoinType>(admin_addr);
        
        // TODO: This should trigger Blocklock automation when threshold is met
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

    #[test_only]
    public fun init_module_for_test<CoinType>(admin: &signer, threshold: u64, controller: address) {
        initialize<CoinType>(admin, threshold, controller);
    }
}
