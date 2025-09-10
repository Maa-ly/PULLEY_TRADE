/// Clone Factory Contract
/// Enables strategy creation by cloning core components
/// Allows anyone to create their own trading strategy with custom parameters
module pulley::clone_factory {
    use std::signer;
    use std::string;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::timestamp;
    use aptos_std::table::{Self, Table};
    use pulley::trading_pool;
    use pulley::controller;
    use pulley::ai_wallet;
    use pulley::insurance_token;
    use pulley::price_oracle;

    /// Error codes
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_INVALID_AMOUNT: u64 = 2;
    const E_FACTORY_NOT_INITIALIZED: u64 = 3;
    const E_STRATEGY_ALREADY_EXISTS: u64 = 4;
    const E_STRATEGY_NOT_FOUND: u64 = 5;
    const E_INVALID_THRESHOLD: u64 = 6;

    /// Strategy configuration
    struct StrategyConfig has store {
        strategy_name: string::String,
        strategy_symbol: string::String,
        threshold_amount: u64,
        supported_assets: vector<address>,
        asset_thresholds: Table<address, u64>,
        asset_decimals: Table<address, u8>,
        price_feeds: Table<address, address>,
        is_active: bool,
        created_at: u64,
    }

    /// Clone configuration
    struct CloneConfig has store {
        trading_pool_address: address,
        controller_address: address,
        ai_wallet_address: address,
        strategy_config: StrategyConfig,
    }

    /// Factory state
    struct CloneFactory has key {
        admin_address: address,
        trading_pool_implementation: address,
        controller_implementation: address,
        ai_wallet_implementation: address,
        insurance_token_address: address,
        price_oracle_address: address,
        
        // Strategy tracking
        strategies: Table<address, CloneConfig>,
        strategy_creators: Table<address, address>,
        strategy_count: u64,
        
        // Events
        strategy_created_events: EventHandle<StrategyCreatedEvent>,
        strategy_updated_events: EventHandle<StrategyUpdatedEvent>,
        strategy_deactivated_events: EventHandle<StrategyDeactivatedEvent>,
    }

    /// Events
    struct StrategyCreatedEvent has drop, store {
        creator: address,
        strategy_address: address,
        strategy_name: string::String,
        threshold_amount: u64,
        supported_assets_count: u64,
        timestamp: u64,
    }

    struct StrategyUpdatedEvent has drop, store {
        strategy_address: address,
        field: string::String,
        old_value: string::String,
        new_value: string::String,
        timestamp: u64,
    }

    struct StrategyDeactivatedEvent has drop, store {
        strategy_address: address,
        deactivated_by: address,
        timestamp: u64,
    }

    /// Initialize the clone factory
    public fun initialize(
        admin: &signer,
        trading_pool_implementation: address,
        controller_implementation: address,
        ai_wallet_implementation: address,
        insurance_token_address: address,
        price_oracle_address: address,
    ) {
        let admin_addr = signer::address_of(admin);
        
        move_to(admin, CloneFactory {
            admin_address: admin_addr,
            trading_pool_implementation,
            controller_implementation,
            ai_wallet_implementation,
            insurance_token_address,
            price_oracle_address,
            strategies: table::new(),
            strategy_creators: table::new(),
            strategy_count: 0,
            strategy_created_events: account::new_event_handle<StrategyCreatedEvent>(admin),
            strategy_updated_events: account::new_event_handle<StrategyUpdatedEvent>(admin),
            strategy_deactivated_events: account::new_event_handle<StrategyDeactivatedEvent>(admin),
        });
    }

    /// Create a new trading strategy
    public fun create_strategy(
        creator: &signer,
        factory_addr: address,
        strategy_name: string::String,
        strategy_symbol: string::String,
        threshold_amount: u64,
        supported_assets: vector<address>,
        asset_thresholds: vector<u64>,
        asset_decimals: vector<u8>,
        price_feeds: vector<address>,
    ): address acquires CloneFactory {
        let creator_addr = signer::address_of(creator);
        assert!(exists<CloneFactory>(factory_addr), E_FACTORY_NOT_INITIALIZED);
        assert!(threshold_amount > 0, E_INVALID_THRESHOLD);
        assert!(vector::length(&supported_assets) == vector::length(&asset_thresholds), E_INVALID_AMOUNT);
        assert!(vector::length(&supported_assets) == vector::length(&asset_decimals), E_INVALID_AMOUNT);
        assert!(vector::length(&supported_assets) == vector::length(&price_feeds), E_INVALID_AMOUNT);
        
        let factory = borrow_global_mut<CloneFactory>(factory_addr);
        
        // Create strategy configuration
        let mut asset_thresholds_table = table::new<address, u64>();
        let mut asset_decimals_table = table::new<address, u8>();
        let mut price_feeds_table = table::new<address, address>();
        
        let i = 0;
        while (i < vector::length(&supported_assets)) {
            let asset = *vector::borrow(&supported_assets, i);
            let threshold = *vector::borrow(&asset_thresholds, i);
            let decimals = *vector::borrow(&asset_decimals, i);
            let price_feed = *vector::borrow(&price_feeds, i);
            
            table::add(&mut asset_thresholds_table, asset, threshold);
            table::add(&mut asset_decimals_table, asset, decimals);
            table::add(&mut price_feeds_table, asset, price_feed);
            
            i = i + 1;
        };
        
        let strategy_config = StrategyConfig {
            strategy_name,
            strategy_symbol,
            threshold_amount,
            supported_assets,
            asset_thresholds: asset_thresholds_table,
            asset_decimals: asset_decimals_table,
            price_feeds: price_feeds_table,
            is_active: true,
            created_at: timestamp::now_microseconds(),
        };
        
        // Generate strategy address (simplified - would use proper address generation)
        let strategy_address = creator_addr; // In production, this would be a proper clone address
        
        // Create clone configuration
        let clone_config = CloneConfig {
            trading_pool_address: strategy_address, // Simplified - would be actual clone addresses
            controller_address: strategy_address,
            ai_wallet_address: strategy_address,
            strategy_config,
        };
        
        // Store strategy
        table::add(&mut factory.strategies, strategy_address, clone_config);
        table::add(&mut factory.strategy_creators, strategy_address, creator_addr);
        factory.strategy_count = factory.strategy_count + 1;
        
        // Initialize components (simplified - would initialize actual clones)
        initialize_strategy_components(creator, strategy_address, &clone_config);
        
        // Emit event
        event::emit_event(&mut factory.strategy_created_events, StrategyCreatedEvent {
            creator: creator_addr,
            strategy_address,
            strategy_name: clone_config.strategy_config.strategy_name,
            threshold_amount,
            supported_assets_count: vector::length(&supported_assets),
            timestamp: timestamp::now_microseconds(),
        });
        
        strategy_address
    }

    /// Initialize strategy components
    fun initialize_strategy_components(
        creator: &signer,
        strategy_address: address,
        clone_config: &CloneConfig,
    ) {
        // Initialize trading pool
        trading_pool::initialize<aptos_framework::aptos_coin::AptosCoin>(
            creator,
            clone_config.strategy_config.threshold_amount,
            clone_config.controller_address
        );
        
        // Initialize controller
        controller::initialize<aptos_framework::aptos_coin::AptosCoin>(
            creator,
            clone_config.trading_pool_address,
            @pulley, // insurance admin address
            clone_config.ai_wallet_address,
            clone_config.strategy_config.supported_assets
        );
        
        // Initialize AI wallet
        ai_wallet::initialize<aptos_framework::aptos_coin::AptosCoin>(
            creator,
            clone_config.controller_address,
            @pulley // AI signer address
        );
        
        // Configure assets in trading pool
        let i = 0;
        while (i < vector::length(&clone_config.strategy_config.supported_assets)) {
            let asset = *vector::borrow(&clone_config.strategy_config.supported_assets, i);
            let threshold = *table::borrow(&clone_config.strategy_config.asset_thresholds, asset);
            let decimals = *table::borrow(&clone_config.strategy_config.asset_decimals, asset);
            let price_feed = *table::borrow(&clone_config.strategy_config.price_feeds, asset);
            
            trading_pool::add_asset<aptos_framework::aptos_coin::AptosCoin>(
                creator,
                clone_config.trading_pool_address,
                asset,
                decimals,
                threshold,
                price_feed
            );
            
            i = i + 1;
        };
    }

    /// Quick create clone with minimal configuration
    public fun quick_create_clone(
        creator: &signer,
        factory_addr: address,
        native_asset: address,
        custom_asset: address,
        custom_asset_decimals: u8,
        threshold_amount: u64,
    ): address acquires CloneFactory {
        let creator_addr = signer::address_of(creator);
        assert!(exists<CloneFactory>(factory_addr), E_FACTORY_NOT_INITIALIZED);
        assert!(threshold_amount > 0, E_INVALID_THRESHOLD);
        
        // Create default configuration
        let strategy_name = string::utf8(b"Quick Strategy");
        let strategy_symbol = string::utf8(b"QS");
        
        let supported_assets = vector::empty<address>();
        vector::push_back(&mut supported_assets, native_asset);
        vector::push_back(&mut supported_assets, custom_asset);
        
        let asset_thresholds = vector::empty<u64>();
        vector::push_back(&mut asset_thresholds, threshold_amount);
        vector::push_back(&mut asset_thresholds, threshold_amount);
        
        let asset_decimals = vector::empty<u8>();
        vector::push_back(&mut asset_decimals, 8); // Default for native
        vector::push_back(&mut asset_decimals, custom_asset_decimals);
        
        let price_feeds = vector::empty<address>();
        vector::push_back(&mut price_feeds, @0x0); // Default price feed
        vector::push_back(&mut price_feeds, @0x0); // Default price feed
        
        create_strategy(
            creator,
            factory_addr,
            strategy_name,
            strategy_symbol,
            threshold_amount,
            supported_assets,
            asset_thresholds,
            asset_decimals,
            price_feeds
        )
    }

    /// Update strategy configuration
    public fun update_strategy_config(
        admin: &signer,
        factory_addr: address,
        strategy_address: address,
        new_threshold: u64,
    ) acquires CloneFactory {
        let admin_addr = signer::address_of(admin);
        assert!(exists<CloneFactory>(factory_addr), E_FACTORY_NOT_INITIALIZED);
        
        let factory = borrow_global<CloneFactory>(factory_addr);
        assert!(admin_addr == factory.admin_address, E_NOT_AUTHORIZED);
        assert!(table::contains(&factory.strategies, strategy_address), E_STRATEGY_NOT_FOUND);
        
        let clone_config = table::borrow_mut(&mut factory.strategies, strategy_address);
        let old_threshold = clone_config.strategy_config.threshold_amount;
        clone_config.strategy_config.threshold_amount = new_threshold;
        
        // Update trading pool threshold
        trading_pool::update_threshold<aptos_framework::aptos_coin::AptosCoin>(
            admin,
            clone_config.trading_pool_address,
            new_threshold
        );
        
        // Emit event
        event::emit_event(&mut factory.strategy_updated_events, StrategyUpdatedEvent {
            strategy_address,
            field: string::utf8(b"threshold"),
            old_value: string::utf8(b""), // Would convert old_threshold to string
            new_value: string::utf8(b""), // Would convert new_threshold to string
            timestamp: timestamp::now_microseconds(),
        });
    }

    /// Deactivate strategy
    public fun deactivate_strategy(
        admin: &signer,
        factory_addr: address,
        strategy_address: address,
    ) acquires CloneFactory {
        let admin_addr = signer::address_of(admin);
        assert!(exists<CloneFactory>(factory_addr), E_FACTORY_NOT_INITIALIZED);
        
        let factory = borrow_global<CloneFactory>(factory_addr);
        assert!(admin_addr == factory.admin_address, E_NOT_AUTHORIZED);
        assert!(table::contains(&factory.strategies, strategy_address), E_STRATEGY_NOT_FOUND);
        
        let clone_config = table::borrow_mut(&mut factory.strategies, strategy_address);
        clone_config.strategy_config.is_active = false;
        
        // Emit event
        event::emit_event(&mut factory.strategy_deactivated_events, StrategyDeactivatedEvent {
            strategy_address,
            deactivated_by: admin_addr,
            timestamp: timestamp::now_microseconds(),
        });
    }

    /// Get strategy information
    public fun get_strategy_info(factory_addr: address, strategy_address: address): (string::String, u64, vector<address>, bool) acquires CloneFactory {
        assert!(exists<CloneFactory>(factory_addr), E_FACTORY_NOT_INITIALIZED);
        let factory = borrow_global<CloneFactory>(factory_addr);
        assert!(table::contains(&factory.strategies, strategy_address), E_STRATEGY_NOT_FOUND);
        
        let clone_config = table::borrow(&factory.strategies, strategy_address);
        (
            clone_config.strategy_config.strategy_name,
            clone_config.strategy_config.threshold_amount,
            clone_config.strategy_config.supported_assets,
            clone_config.strategy_config.is_active
        )
    }

    /// Get strategy addresses
    public fun get_strategy_addresses(factory_addr: address, strategy_address: address): (address, address, address) acquires CloneFactory {
        assert!(exists<CloneFactory>(factory_addr), E_FACTORY_NOT_INITIALIZED);
        let factory = borrow_global<CloneFactory>(factory_addr);
        assert!(table::contains(&factory.strategies, strategy_address), E_STRATEGY_NOT_FOUND);
        
        let clone_config = table::borrow(&factory.strategies, strategy_address);
        (
            clone_config.trading_pool_address,
            clone_config.controller_address,
            clone_config.ai_wallet_address
        )
    }

    /// Get strategy creator
    public fun get_strategy_creator(factory_addr: address, strategy_address: address): address acquires CloneFactory {
        assert!(exists<CloneFactory>(factory_addr), E_FACTORY_NOT_INITIALIZED);
        let factory = borrow_global<CloneFactory>(factory_addr);
        assert!(table::contains(&factory.strategy_creators, strategy_address), E_STRATEGY_NOT_FOUND);
        
        *table::borrow(&factory.strategy_creators, strategy_address)
    }

    /// Get all strategies
    public fun get_all_strategies(factory_addr: address): vector<address> acquires CloneFactory {
        assert!(exists<CloneFactory>(factory_addr), E_FACTORY_NOT_INITIALIZED);
        let factory = borrow_global<CloneFactory>(factory_addr);
        
        // In production, this would return all strategy addresses
        // For now, return empty vector
        vector::empty<address>()
    }

    /// Get strategy count
    public fun get_strategy_count(factory_addr: address): u64 acquires CloneFactory {
        assert!(exists<CloneFactory>(factory_addr), E_FACTORY_NOT_INITIALIZED);
        let factory = borrow_global<CloneFactory>(factory_addr);
        factory.strategy_count
    }

    /// Update implementation addresses
    public fun update_implementations(
        admin: &signer,
        factory_addr: address,
        new_trading_pool_impl: address,
        new_controller_impl: address,
        new_ai_wallet_impl: address,
    ) acquires CloneFactory {
        let admin_addr = signer::address_of(admin);
        assert!(exists<CloneFactory>(factory_addr), E_FACTORY_NOT_INITIALIZED);
        
        let factory = borrow_global_mut<CloneFactory>(factory_addr);
        assert!(admin_addr == factory.admin_address, E_NOT_AUTHORIZED);
        
        if (new_trading_pool_impl != @0x0) {
            factory.trading_pool_implementation = new_trading_pool_impl;
        };
        if (new_controller_impl != @0x0) {
            factory.controller_implementation = new_controller_impl;
        };
        if (new_ai_wallet_impl != @0x0) {
            factory.ai_wallet_implementation = new_ai_wallet_impl;
        };
    }

    /// Check if strategy exists
    public fun strategy_exists(factory_addr: address, strategy_address: address): bool acquires CloneFactory {
        if (!exists<CloneFactory>(factory_addr)) {
            return false
        };
        let factory = borrow_global<CloneFactory>(factory_addr);
        table::contains(&factory.strategies, strategy_address)
    }

    /// Get factory information
    public fun get_factory_info(factory_addr: address): (address, address, address, address, u64) acquires CloneFactory {
        assert!(exists<CloneFactory>(factory_addr), E_FACTORY_NOT_INITIALIZED);
        let factory = borrow_global<CloneFactory>(factory_addr);
        (
            factory.trading_pool_implementation,
            factory.controller_implementation,
            factory.ai_wallet_implementation,
            factory.insurance_token_address,
            factory.strategy_count
        )
    }

    #[test_only]
    public fun init_module_for_test(
        admin: &signer,
        trading_pool_impl: address,
        controller_impl: address,
        ai_wallet_impl: address,
        insurance_token: address,
        price_oracle: address
    ) {
        initialize(admin, trading_pool_impl, controller_impl, ai_wallet_impl, insurance_token, price_oracle);
    }
}
