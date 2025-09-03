/// Controller Contract
/// Manages fund allocation: 15% to insurance, 85% to external trading address
module pulley::controller {
    use std::signer;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::account;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::timestamp;
    use aptos_std::table;
    use pulley::insurance_token;
    // use pulley::trading_pool;

    /// Error codes
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_INSUFFICIENT_BALANCE: u64 = 2;
    const E_INVALID_AMOUNT: u64 = 3;
    const E_CONTROLLER_NOT_INITIALIZED: u64 = 4;
    const E_VAULT_NOT_REGISTERED: u64 = 5;
    const E_INVALID_VAULT_COUNT: u64 = 6;

    /// Fund allocation percentages (basis points: 10000 = 100%)
    const INSURANCE_PERCENTAGE: u64 = 1500; // 15% for insurance
    const TRADING_PERCENTAGE: u64 = 8500; // 85% for external trading
    const PROFIT_INSURANCE_PERCENTAGE: u64 = 1000; // 10% to insurance
    const PROFIT_TRADERS_PERCENTAGE: u64 = 9000; // 90% to traders

    /// Controller state
    struct Controller<phantom CoinType> has key {
        admin_address: address,
        trading_pool_address: address,
        insurance_admin_address: address,
        trading_address: address, // Address used for external trading (controlled by admin)
        total_managed_funds: u64,
        total_profits: u64,
        total_losses: u64,
        is_active: bool,
        allocation_events: EventHandle<AllocationEvent>,
        profit_events: EventHandle<ProfitEvent>,
        loss_events: EventHandle<LossEvent>,
        trading_transfer_events: EventHandle<TradingTransferEvent>,
    }

    /// Events
    struct AllocationEvent has drop, store {
        total_amount: u64,
        insurance_amount: u64,
        trading_amount: u64,
        timestamp: u64,
    }

    struct TradingTransferEvent has drop, store {
        amount: u64,
        trading_address: address,
        timestamp: u64,
    }

    struct ProfitEvent has drop, store {
        profit_amount: u64,
        insurance_share: u64,
        traders_share: u64,
        timestamp: u64,
    }

    struct LossEvent has drop, store {
        loss_amount: u64,
        insurance_absorbed: u64,
        remaining_loss: u64,
        timestamp: u64,
    }

    /// Initialize the controller
    public fun initialize<CoinType>(
        admin: &signer,
        trading_pool_address: address,
        insurance_admin_address: address,
        trading_address: address,
    ) {
        let admin_addr = signer::address_of(admin);
        
        move_to(admin, Controller<CoinType> {
            admin_address: admin_addr,
            trading_pool_address,
            insurance_admin_address,
            trading_address,
            total_managed_funds: 0,
            total_profits: 0,
            total_losses: 0,
            is_active: true,
            allocation_events: account::new_event_handle<AllocationEvent>(admin),
            profit_events: account::new_event_handle<ProfitEvent>(admin),
            loss_events: account::new_event_handle<LossEvent>(admin),
            trading_transfer_events: account::new_event_handle<TradingTransferEvent>(admin),
        });

        // Note: Insurance authorization should be done separately by the insurance admin
    }

    /// Allocate funds received from trading pool: 15% to insurance, 85% to trading address
    public fun allocate_funds<CoinType>(
        pool_signer: &signer,
        controller_addr: address,
        funds: Coin<CoinType>,
    ) acquires Controller {
        assert!(exists<Controller<CoinType>>(controller_addr), E_CONTROLLER_NOT_INITIALIZED);
        
        let controller = borrow_global_mut<Controller<CoinType>>(controller_addr);
        let pool_addr = signer::address_of(pool_signer);
        assert!(pool_addr == controller.trading_pool_address, E_NOT_AUTHORIZED);
        assert!(controller.is_active, E_NOT_AUTHORIZED);
        
        let total_amount = coin::value(&funds);
        assert!(total_amount > 0, E_INVALID_AMOUNT);
        
        // Calculate allocation amounts: 15% insurance, 85% trading
        let insurance_amount = (total_amount * INSURANCE_PERCENTAGE) / 10000;
        let trading_amount = total_amount - insurance_amount;
        
        // Split the funds
        let insurance_coins = coin::extract(&mut funds, insurance_amount);
        let trading_coins = funds; // Remaining funds go to trading
        
        // Deposit to insurance and mint PULLEY insurance tokens
        coin::deposit(controller.insurance_admin_address, insurance_coins);
        
        // Mint insurance tokens for trading
        insurance_token::mint_insurance(pool_signer, controller.insurance_admin_address, insurance_amount);
        
        // Send to trading address (controlled by admin for external trading)
        coin::deposit(controller.trading_address, trading_coins);
        
        controller.total_managed_funds = controller.total_managed_funds + total_amount;
        
        // Emit allocation event
        event::emit_event(&mut controller.allocation_events, AllocationEvent {
            total_amount,
            insurance_amount,
            trading_amount,
            timestamp: timestamp::now_microseconds(),
        });

        // Emit trading transfer event
        event::emit_event(&mut controller.trading_transfer_events, TradingTransferEvent {
            amount: trading_amount,
            trading_address: controller.trading_address,
            timestamp: timestamp::now_microseconds(),
        });
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

    /// Check if funds are available for allocation (for Blocklock automation)
    public fun has_funds_to_allocate<CoinType>(controller_addr: address): bool acquires Controller {
        assert!(exists<Controller<CoinType>>(controller_addr), E_CONTROLLER_NOT_INITIALIZED);
        let _controller = borrow_global<Controller<CoinType>>(controller_addr);
        coin::balance<CoinType>(controller_addr) > 0
    }

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

    #[test_only]
    public fun init_module_for_test<CoinType>(
        admin: &signer,
        trading_pool: address,
        insurance_admin: address,
        trading_address: address
    ) {
        initialize<CoinType>(admin, trading_pool, insurance_admin, trading_address);
    }
}
