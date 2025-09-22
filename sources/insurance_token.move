/// PULLEY Insurance Token - Floating Stablecoin
/// This contract manages the PULLEY (PUL) insurance token using Fungible Asset standard
/// Anyone can mint it outside trading, controller mints for trading insurance
module pulley::insurance_token {
    use std::signer;
    use std::string::{Self, utf8};
    use std::option;
    use aptos_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, Metadata};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::account;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::timestamp;
    use aptos_std::table::{Self, Table};

    /// Error codes
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_INSUFFICIENT_BALANCE: u64 = 2;
    const E_INSUFFICIENT_INSURANCE: u64 = 3;
    const E_INVALID_AMOUNT: u64 = 4;

    /// PULLEY token constants
    const ASSET_NAME: vector<u8> = b"PULLEY Insurance Token";
    const ASSET_SYMBOL: vector<u8> = b"PUL";

    /// Managed fungible asset for PULLEY token
    struct ManagedFungibleAsset has key {
        mint_ref: MintRef,
        transfer_ref: TransferRef,
        burn_ref: BurnRef,
    }

    /// Insurance pool state
    struct InsurancePool has key {
        total_insurance_supply: u64,  // Insurance tokens minted for trading
        total_external_supply: u64,   // Tokens minted outside trading
        total_absorbed_losses: u64,
        profit_collected: u64,
        market_utilization: u64,      // For floating stablecoin price calculation
        utilization_rate: u64,        // Current utilization rate (basis points)
        growth_rate: u64,             // Current growth rate (basis points per day)
        last_growth_update: u64,      // Last time growth was applied
        insurance_reserve: u64,       // Insurance funds from trading pool
        total_backing_value: u64,     // Total USD value backing tokens
        authorized_controllers: Table<address, bool>,
        
        // Growth parameters
        base_growth_rate: u64,        // 1% base daily growth
        utilization_multiplier: u64,  // 0.5% additional per utilization point
        max_growth_rate: u64,         // 10% max daily growth
        
        // Asset backing
        asset_backing: Table<address, u64>,
        supported_assets: Table<address, bool>,
        backing_assets: vector<address>,
        
        // Events
        mint_events: EventHandle<MintEvent>,
        burn_events: EventHandle<BurnEvent>,
        loss_absorption_events: EventHandle<LossAbsorptionEvent>,
        profit_deposit_events: EventHandle<ProfitDepositEvent>,
        growth_events: EventHandle<GrowthEvent>,
        price_update_events: EventHandle<PriceUpdateEvent>,
    }

    /// Events
    struct MintEvent has drop, store {
        recipient: address,
        amount: u64,
        mint_type: u8, // 1 = external mint, 2 = trading insurance mint
        timestamp: u64,
    }

    struct BurnEvent has drop, store {
        account: address,
        amount: u64,
        timestamp: u64,
    }

    struct LossAbsorptionEvent has drop, store {
        loss_amount: u64,
        insurance_used: u64,
        remaining_loss: u64,
        timestamp: u64,
    }

    struct ProfitDepositEvent has drop, store {
        profit_amount: u64,
        timestamp: u64,
    }

    struct GrowthEvent has drop, store {
        growth_amount: u64,
        new_insurance_reserve: u64,
        utilization_rate: u64,
        timestamp: u64,
    }

    struct PriceUpdateEvent has drop, store {
        old_price: u64,
        new_price: u64,
        total_supply: u64,
        total_backing: u64,
        timestamp: u64,
    }

    struct AssetSupportUpdatedEvent has drop, store {
        asset: address,
        supported: bool,
    }

    /// Initialize the PULLEY insurance token using Fungible Asset standard
    fun init_module(admin: &signer) {
        let constructor_ref = &object::create_named_object(admin, ASSET_SYMBOL);
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructor_ref,
            option::none(),
            utf8(ASSET_NAME), /* name */
            utf8(ASSET_SYMBOL), /* symbol */
            8, /* decimals */
            utf8(b"http://example.com/pulley-icon.ico"), /* icon */ //replace - make one
            utf8(b"http://pulley.finance"), /* project */
        );

        let mint_ref = fungible_asset::generate_mint_ref(constructor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(constructor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(constructor_ref);
        let metadata_object_signer = object::generate_signer(constructor_ref);
        
        // Store managed fungible asset capabilities
        move_to(
            &metadata_object_signer,
            ManagedFungibleAsset { mint_ref, transfer_ref, burn_ref }
        );

        // Initialize insurance pool state
        move_to(admin, InsurancePool {
            total_insurance_supply: 0,
            total_external_supply: 0,
            total_absorbed_losses: 0,
            profit_collected: 0,
            market_utilization: 0,
            utilization_rate: 0,
            growth_rate: 0,
            last_growth_update: timestamp::now_microseconds(),
            insurance_reserve: 0,
            total_backing_value: 0,
            authorized_controllers: table::new(),
            base_growth_rate: 100,        // 1% base daily growth (basis points)
            utilization_multiplier: 50,   // 0.5% additional per utilization point
            max_growth_rate: 1000,        // 10% max daily growth
            asset_backing: table::new(),
            supported_assets: table::new(),
            backing_assets: vector::empty(),
            mint_events: account::new_event_handle<MintEvent>(admin),
            burn_events: account::new_event_handle<BurnEvent>(admin),
            loss_absorption_events: account::new_event_handle<LossAbsorptionEvent>(admin),
            profit_deposit_events: account::new_event_handle<ProfitDepositEvent>(admin),
            growth_events: account::new_event_handle<GrowthEvent>(admin),
            price_update_events: account::new_event_handle<PriceUpdateEvent>(admin),
        });
    }

    /// Get the metadata object for PULLEY token
    #[view]
    public fun get_metadata(): Object<Metadata> {
        let asset_address = object::create_object_address(&@pulley, ASSET_SYMBOL);
        object::address_to_object<Metadata>(asset_address)
    }

    /// Get the name of PULLEY token
    #[view]
    public fun get_name(): string::String {
        let metadata = get_metadata();
        fungible_asset::name(metadata)
    }

    /// Get authorized borrow refs for minting/burning operations
    inline fun authorized_borrow_refs(admin: &signer, asset: Object<Metadata>): &ManagedFungibleAsset {
        let admin_addr = signer::address_of(admin);
        assert!(exists<InsurancePool>(admin_addr), E_NOT_AUTHORIZED);
        borrow_global<ManagedFungibleAsset>(object::object_address(&asset))
    }

    /// Authorize a controller to interact with insurance
    public fun authorize_controller(admin: &signer, controller: address) acquires InsurancePool {
        let admin_addr = signer::address_of(admin);
        assert!(exists<InsurancePool>(admin_addr), E_NOT_AUTHORIZED);
        
        let pool = borrow_global_mut<InsurancePool>(admin_addr);
        table::upsert(&mut pool.authorized_controllers, controller, true);
    }

    /// Mint PULLEY tokens for external users (callable by anyone)
    public entry fun mint_external(recipient: &signer, admin_addr: address, amount: u64) acquires ManagedFungibleAsset, InsurancePool {
        assert!(amount > 0, E_INVALID_AMOUNT);
        
        let recipient_addr = signer::address_of(recipient);
        let asset = get_metadata();
        let managed_fungible_asset = borrow_global<ManagedFungibleAsset>(object::object_address(&asset));
        let pool = borrow_global_mut<InsurancePool>(admin_addr);
        
        // Ensure recipient has a primary store
        let to_wallet = primary_fungible_store::ensure_primary_store_exists(recipient_addr, asset);
        
        // Mint fungible asset tokens
        let fa = fungible_asset::mint(&managed_fungible_asset.mint_ref, amount);
        fungible_asset::deposit_with_ref(&managed_fungible_asset.transfer_ref, to_wallet, fa);
        
        // Update pool state - external supply
        pool.total_external_supply = pool.total_external_supply + amount;
        
        // Emit event
        event::emit_event(&mut pool.mint_events, MintEvent {
            recipient: recipient_addr,
            amount,
            mint_type: 1, // External mint
            timestamp: timestamp::now_microseconds(),
        });
    }

    /// Mint PULLEY tokens for trading insurance (only callable by authorized controllers)
    public fun mint_insurance(controller: &signer, admin_addr: address, amount: u64) acquires ManagedFungibleAsset, InsurancePool {
        assert!(amount > 0, E_INVALID_AMOUNT);
        
        let controller_addr = signer::address_of(controller);
        let asset = get_metadata();
        let managed_fungible_asset = borrow_global<ManagedFungibleAsset>(object::object_address(&asset));
        let pool = borrow_global_mut<InsurancePool>(admin_addr);
        
        // Check authorization
        assert!(table::contains(&pool.authorized_controllers, controller_addr), E_NOT_AUTHORIZED);
        
        // Ensure controller has a primary store
        let to_wallet = primary_fungible_store::ensure_primary_store_exists(controller_addr, asset);
        
        // Mint fungible asset tokens
        let fa = fungible_asset::mint(&managed_fungible_asset.mint_ref, amount);
        fungible_asset::deposit_with_ref(&managed_fungible_asset.transfer_ref, to_wallet, fa);
        
        // Update pool state - insurance supply
        pool.total_insurance_supply = pool.total_insurance_supply + amount;
        
        // Emit event
        event::emit_event(&mut pool.mint_events, MintEvent {
            recipient: controller_addr,
            amount,
            mint_type: 2, // Trading insurance mint
            timestamp: timestamp::now_microseconds(),
        });
    }

    /// Absorb loss from trading activities (only callable by authorized controllers)
    public fun absorb_loss(controller: &signer, admin_addr: address, loss_amount: u64): u64 acquires InsurancePool, ManagedFungibleAsset {
        let controller_addr = signer::address_of(controller);
        assert!(exists<InsurancePool>(admin_addr), E_NOT_AUTHORIZED);
        
        let pool = borrow_global_mut<InsurancePool>(admin_addr);
        assert!(table::contains(&pool.authorized_controllers, controller_addr), E_NOT_AUTHORIZED);
        
        let available_insurance = pool.total_insurance_supply;
        let absorbed_amount = if (available_insurance >= loss_amount) {
            loss_amount
        } else {
            available_insurance
        };
        
        let remaining_loss = loss_amount - absorbed_amount;
        
        // Burn insurance tokens to absorb loss
        if (absorbed_amount > 0) {
            let asset = get_metadata();
            let managed_fungible_asset = borrow_global<ManagedFungibleAsset>(object::object_address(&asset));
            let controller_wallet = primary_fungible_store::primary_store(controller_addr, asset);
            
            // Withdraw and burn tokens
            let fa_to_burn = fungible_asset::withdraw_with_ref(&managed_fungible_asset.transfer_ref, controller_wallet, absorbed_amount);
            fungible_asset::burn(&managed_fungible_asset.burn_ref, fa_to_burn);
            
            pool.total_insurance_supply = pool.total_insurance_supply - absorbed_amount;
            pool.total_absorbed_losses = pool.total_absorbed_losses + absorbed_amount;
        };
        
        // Emit event
        event::emit_event(&mut pool.loss_absorption_events, LossAbsorptionEvent {
            loss_amount,
            insurance_used: absorbed_amount,
            remaining_loss,
            timestamp: timestamp::now_microseconds(),
        });
        
        remaining_loss
    }

    /// Deposit profit into insurance (10% of trading profits)
    public fun deposit_profit(controller: &signer, admin_addr: address, profit_amount: u64) acquires InsurancePool, ManagedFungibleAsset {
        let controller_addr = signer::address_of(controller);
        assert!(exists<InsurancePool>(admin_addr), E_NOT_AUTHORIZED);
        
        let pool = borrow_global_mut<InsurancePool>(admin_addr);
        assert!(table::contains(&pool.authorized_controllers, controller_addr), E_NOT_AUTHORIZED);
        assert!(profit_amount > 0, E_INVALID_AMOUNT);
        
        // Mint new insurance tokens equivalent to 10% of profit
        let asset = get_metadata();
        let managed_fungible_asset = borrow_global<ManagedFungibleAsset>(object::object_address(&asset));
        let admin_wallet = primary_fungible_store::ensure_primary_store_exists(admin_addr, asset);
        
        let fa = fungible_asset::mint(&managed_fungible_asset.mint_ref, profit_amount);
        fungible_asset::deposit_with_ref(&managed_fungible_asset.transfer_ref, admin_wallet, fa);
        
        pool.total_insurance_supply = pool.total_insurance_supply + profit_amount;
        pool.profit_collected = pool.profit_collected + profit_amount;
        
        // Emit event
        event::emit_event(&mut pool.profit_deposit_events, ProfitDepositEvent {
            profit_amount,
            timestamp: timestamp::now_microseconds(),
        });
    }

    /// Get insurance pool info
    public fun get_insurance_info(admin_addr: address): (u64, u64, u64, u64, u64) acquires InsurancePool {
        assert!(exists<InsurancePool>(admin_addr), E_NOT_AUTHORIZED);
        let pool = borrow_global<InsurancePool>(admin_addr);
        (pool.total_insurance_supply, pool.total_external_supply, pool.total_absorbed_losses, pool.profit_collected, pool.market_utilization)
    }

    /// Check if controller is authorized
    public fun is_controller_authorized(admin_addr: address, controller: address): bool acquires InsurancePool {
        if (!exists<InsurancePool>(admin_addr)) {
            return false
        };
        let pool = borrow_global<InsurancePool>(admin_addr);
        table::contains(&pool.authorized_controllers, controller)
    }

    /// Get available insurance amount
    public fun get_available_insurance(admin_addr: address): u64 acquires InsurancePool {
        assert!(exists<InsurancePool>(admin_addr), E_NOT_AUTHORIZED);
        let pool = borrow_global<InsurancePool>(admin_addr);
        pool.total_insurance_supply
    }

    /// Get total PULLEY supply (external + insurance)
    public fun get_total_supply(admin_addr: address): u64 acquires InsurancePool {
        assert!(exists<InsurancePool>(admin_addr), E_NOT_AUTHORIZED);
        let pool = borrow_global<InsurancePool>(admin_addr);
        pool.total_insurance_supply + pool.total_external_supply
    }

    /// Update market utilization (for floating stablecoin price calculation)
    public fun update_market_utilization(controller: &signer, admin_addr: address, utilization: u64) acquires InsurancePool {
        let controller_addr = signer::address_of(controller);
        assert!(exists<InsurancePool>(admin_addr), E_NOT_AUTHORIZED);
        
        let pool = borrow_global_mut<InsurancePool>(admin_addr);
        assert!(table::contains(&pool.authorized_controllers, controller_addr), E_NOT_AUTHORIZED);
        
        pool.market_utilization = utilization;
    }

    /// Get current token price (floating, not 1:1)
    public fun get_current_price(admin_addr: address): u64 acquires InsurancePool {
        assert!(exists<InsurancePool>(admin_addr), E_NOT_AUTHORIZED);
        let pool = borrow_global<InsurancePool>(admin_addr);
        
        let total_supply = pool.total_insurance_supply + pool.total_external_supply;
        if (total_supply == 0) {
            return 100000000 // 1 USD in 8 decimals
        };
        
        // Price increases with growth and utilization
        // Base price + growth premium + utilization premium
        let base_price = 100000000; // 1 USD base (8 decimals)
        
        // Growth premium based on total growth applied
        let growth_premium = if (total_supply > 0) {
            (pool.insurance_reserve * 100000000) / total_supply
        } else {
            0
        };
        
        // Utilization premium
        let utilization_premium = (pool.utilization_rate * 10000) / 10000; // Max 1% premium
        
        base_price + growth_premium + utilization_premium
    }

    /// Update growth based on utilization (can be called by anyone)
    public fun update_growth(admin_addr: address) acquires InsurancePool, ManagedFungibleAsset {
        assert!(exists<InsurancePool>(admin_addr), E_NOT_AUTHORIZED);
        let pool = borrow_global_mut<InsurancePool>(admin_addr);
        
        let current_time = timestamp::now_microseconds();
        let growth_interval = 86400000000; // 1 day in microseconds
        
        if (current_time < pool.last_growth_update + growth_interval) {
            return // Not enough time passed
        };
        
        let total_supply = pool.total_insurance_supply + pool.total_external_supply;
        if (total_supply == 0) {
            pool.last_growth_update = current_time;
            return // No tokens to grow
        };
        
        // Calculate periods elapsed
        let periods_elapsed = (current_time - pool.last_growth_update) / growth_interval;
        
        // Calculate current growth rate based on utilization
        let current_growth_rate = calculate_growth_rate(pool);
        
        // Apply compound growth for each period
        let mut new_supply = total_supply;
        let i = 0;
        while (i < periods_elapsed) {
            new_supply = (new_supply * (10000 + current_growth_rate)) / 10000;
            i = i + 1;
        };
        
        if (new_supply > total_supply) {
            let growth_amount = new_supply - total_supply;
            
            // Mint growth to insurance reserve (increases token value for holders)
            pool.insurance_reserve = pool.insurance_reserve + growth_amount;
            pool.total_insurance_supply = pool.total_insurance_supply + growth_amount;
            
            // Emit event
            event::emit_event(&mut pool.growth_events, GrowthEvent {
                growth_amount,
                new_insurance_reserve: pool.insurance_reserve,
                utilization_rate: pool.utilization_rate,
                timestamp: current_time,
            });
        };
        
        pool.last_growth_update = current_time;
        pool.growth_rate = current_growth_rate;
    }

    /// Calculate current growth rate based on utilization
    fun calculate_growth_rate(pool: &InsurancePool): u64 {
        // Growth rate = base rate + (utilization * multiplier)
        let rate = pool.base_growth_rate + (pool.utilization_rate * pool.utilization_multiplier) / 10000;
        
        // Cap at maximum
        if (rate > pool.max_growth_rate) {
            pool.max_growth_rate
        } else {
            rate
        }
    }

    /// Update utilization rate (called by controller)
    public fun update_utilization(
        controller: &signer,
        admin_addr: address,
        new_utilization_rate: u64,
    ) acquires InsurancePool {
        let controller_addr = signer::address_of(controller);
        assert!(exists<InsurancePool>(admin_addr), E_NOT_AUTHORIZED);
        
        let pool = borrow_global_mut<InsurancePool>(admin_addr);
        assert!(table::contains(&pool.authorized_controllers, controller_addr), E_NOT_AUTHORIZED);
        
        pool.utilization_rate = new_utilization_rate;
        
        // Trigger growth update when utilization changes
        update_growth(admin_addr);
    }

    /// Add supported asset for backing
    public fun add_supported_asset(
        admin: &signer,
        admin_addr: address,
        asset: address,
    ) acquires InsurancePool {
        let admin_addr_signer = signer::address_of(admin);
        assert!(exists<InsurancePool>(admin_addr), E_NOT_AUTHORIZED);
        
        let pool = borrow_global_mut<InsurancePool>(admin_addr);
        assert!(admin_addr_signer == admin_addr, E_NOT_AUTHORIZED);
        
        if (!table::contains(&pool.supported_assets, asset)) {
            table::add(&mut pool.supported_assets, asset, true);
            vector::push_back(&mut pool.backing_assets, asset);
            
            // Emit event
            event::emit_event(&mut pool.mint_events, AssetSupportUpdatedEvent {
                asset,
                supported: true,
            });
        };
    }

    /// Remove supported asset
    public fun remove_supported_asset(
        admin: &signer,
        admin_addr: address,
        asset: address,
    ) acquires InsurancePool {
        let admin_addr_signer = signer::address_of(admin);
        assert!(exists<InsurancePool>(admin_addr), E_NOT_AUTHORIZED);
        
        let pool = borrow_global_mut<InsurancePool>(admin_addr);
        assert!(admin_addr_signer == admin_addr, E_NOT_AUTHORIZED);
        
        if (table::contains(&pool.supported_assets, asset)) {
            table::remove(&mut pool.supported_assets, asset);
            
            // Remove from backing assets
            let (found, index) = vector::index_of(&pool.backing_assets, &asset);
            if (found) {
                vector::remove(&mut pool.backing_assets, index);
            };
            
            // Emit event
            event::emit_event(&mut pool.mint_events, AssetSupportUpdatedEvent {
                asset,
                supported: false,
            });
        };
    }

    /// Update growth parameters
    public fun update_growth_parameters(
        admin: &signer,
        admin_addr: address,
        base_growth_rate: u64,
        utilization_multiplier: u64,
        max_growth_rate: u64,
    ) acquires InsurancePool {
        let admin_addr_signer = signer::address_of(admin);
        assert!(exists<InsurancePool>(admin_addr), E_NOT_AUTHORIZED);
        
        let pool = borrow_global_mut<InsurancePool>(admin_addr);
        assert!(admin_addr_signer == admin_addr, E_NOT_AUTHORIZED);
        
        pool.base_growth_rate = base_growth_rate;
        pool.utilization_multiplier = utilization_multiplier;
        pool.max_growth_rate = max_growth_rate;
    }

    /// Get growth metrics
    public fun get_growth_metrics(admin_addr: address): (u64, u64, u64, u64) acquires InsurancePool {
        assert!(exists<InsurancePool>(admin_addr), E_NOT_AUTHORIZED);
        let pool = borrow_global<InsurancePool>(admin_addr);
        
        let current_price = get_current_price(admin_addr);
        let current_growth_rate = calculate_growth_rate(pool);
        
        (current_price, current_growth_rate, pool.utilization_rate, pool.insurance_reserve)
    }

    /// Get backing information for an asset
    public fun get_backing_info(admin_addr: address, asset: address): u64 acquires InsurancePool {
        assert!(exists<InsurancePool>(admin_addr), E_NOT_AUTHORIZED);
        let pool = borrow_global<InsurancePool>(admin_addr);
        
        if (table::contains(&pool.asset_backing, asset)) {
            *table::borrow(&pool.asset_backing, asset)
        } else {
            0
        }
    }

    /// Get supported assets
    public fun get_supported_assets(admin_addr: address): vector<address> acquires InsurancePool {
        assert!(exists<InsurancePool>(admin_addr), E_NOT_AUTHORIZED);
        let pool = borrow_global<InsurancePool>(admin_addr);
        pool.backing_assets
    }

    /// Check if asset is supported
    public fun is_asset_supported(admin_addr: address, asset: address): bool acquires InsurancePool {
        if (!exists<InsurancePool>(admin_addr)) {
            return false
        };
        let pool = borrow_global<InsurancePool>(admin_addr);
        table::contains(&pool.supported_assets, asset)
    }

    /// Get total PULLEY supply (external + insurance)
    public fun get_total_supply(admin_addr: address): u64 acquires InsurancePool {
        assert!(exists<InsurancePool>(admin_addr), E_NOT_AUTHORIZED);
        let pool = borrow_global<InsurancePool>(admin_addr);
        pool.total_insurance_supply + pool.total_external_supply
    }

    /// Get comprehensive insurance info
    public fun get_insurance_info(admin_addr: address): (u64, u64, u64, u64, u64, u64, u64) acquires InsurancePool {
        assert!(exists<InsurancePool>(admin_addr), E_NOT_AUTHORIZED);
        let pool = borrow_global<InsurancePool>(admin_addr);
        (
            pool.total_insurance_supply,
            pool.total_external_supply,
            pool.total_absorbed_losses,
            pool.profit_collected,
            pool.market_utilization,
            pool.insurance_reserve,
            pool.total_backing_value
        )
    }

    #[test_only]
    public fun init_module_for_test(admin: &signer) {
        init_module(admin);
    }
}
