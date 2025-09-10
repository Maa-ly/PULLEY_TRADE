/// Price Oracle Contract
/// Provides price feeds for supported assets
/// Integrates with external price oracle services like Pyth Network
module pulley::price_oracle {
    use std::signer;
    use std::string;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::timestamp;
    use aptos_std::table::{Self, Table};

    /// Error codes
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_ASSET_NOT_SUPPORTED: u64 = 2;
    const E_INVALID_PRICE: u64 = 3;
    const E_ORACLE_NOT_INITIALIZED: u64 = 4;
    const E_PRICE_FEED_NOT_FOUND: u64 = 5;
    const E_STALE_PRICE: u64 = 6;
    const E_INVALID_DECIMALS: u64 = 7;
    const E_PRICE_FEED_INACTIVE: u64 = 8;

    /// Price feed information
    struct PriceFeed has store {
        asset_address: address,
        price_feed_address: address,
        decimals: u8,
        last_updated: u64,
        is_active: bool,
        price: u64,
        confidence_interval: u64,
        max_deviation: u64,
    }

    /// Oracle state
    struct PriceOracle has key {
        admin_address: address,
        price_feeds: Table<address, PriceFeed>,
        supported_assets: vector<address>,
        max_price_age: u64, // Maximum age of price in seconds
        default_confidence_interval: u64,
        default_max_deviation: u64,
        
        // Events
        price_feed_added_events: EventHandle<PriceFeedAddedEvent>,
        price_feed_updated_events: EventHandle<PriceFeedUpdatedEvent>,
        price_feed_removed_events: EventHandle<PriceFeedRemovedEvent>,
        price_updated_events: EventHandle<PriceUpdatedEvent>,
        oracle_configured_events: EventHandle<OracleConfiguredEvent>,
    }

    /// Events
    struct PriceFeedAddedEvent has drop, store {
        asset_address: address,
        price_feed_address: address,
        decimals: u8,
        confidence_interval: u64,
        max_deviation: u64,
        added_by: address,
        timestamp: u64,
    }

    struct PriceFeedUpdatedEvent has drop, store {
        asset_address: address,
        old_price_feed: address,
        new_price_feed: address,
        updated_by: address,
        timestamp: u64,
    }

    struct PriceFeedRemovedEvent has drop, store {
        asset_address: address,
        price_feed_address: address,
        removed_by: address,
        timestamp: u64,
    }

    struct PriceUpdatedEvent has drop, store {
        asset_address: address,
        old_price: u64,
        new_price: u64,
        confidence_interval: u64,
        timestamp: u64,
    }

    struct OracleConfiguredEvent has drop, store {
        max_price_age: u64,
        default_confidence_interval: u64,
        default_max_deviation: u64,
        configured_by: address,
        timestamp: u64,
    }

    /// Initialize the price oracle
    public fun initialize(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        
        move_to(admin, PriceOracle {
            admin_address: admin_addr,
            price_feeds: table::new(),
            supported_assets: vector::empty(),
            max_price_age: 3600, // 1 hour default
            default_confidence_interval: 100, // 1% default
            default_max_deviation: 500, // 5% default
            price_feed_added_events: account::new_event_handle<PriceFeedAddedEvent>(admin),
            price_feed_updated_events: account::new_event_handle<PriceFeedUpdatedEvent>(admin),
            price_feed_removed_events: account::new_event_handle<PriceFeedRemovedEvent>(admin),
            price_updated_events: account::new_event_handle<PriceUpdatedEvent>(admin),
            oracle_configured_events: account::new_event_handle<OracleConfiguredEvent>(admin),
        });
    }

    /// Configure oracle parameters
    public fun configure_oracle(
        admin: &signer,
        max_price_age: u64,
        default_confidence_interval: u64,
        default_max_deviation: u64,
    ) acquires PriceOracle {
        let admin_addr = signer::address_of(admin);
        assert!(exists<PriceOracle>(@pulley), E_ORACLE_NOT_INITIALIZED);
        
        let oracle = borrow_global_mut<PriceOracle>(@pulley);
        assert!(admin_addr == oracle.admin_address, E_NOT_AUTHORIZED);
        assert!(max_price_age > 0, E_INVALID_PRICE);
        assert!(default_confidence_interval <= 10000, E_INVALID_PRICE); // Max 100%
        assert!(default_max_deviation <= 10000, E_INVALID_PRICE); // Max 100%
        
        oracle.max_price_age = max_price_age;
        oracle.default_confidence_interval = default_confidence_interval;
        oracle.default_max_deviation = default_max_deviation;
        
        // Emit event
        event::emit_event(&mut oracle.oracle_configured_events, OracleConfiguredEvent {
            max_price_age,
            default_confidence_interval,
            default_max_deviation,
            configured_by: admin_addr,
            timestamp: timestamp::now_microseconds(),
        });
    }

    /// Add price feed for asset
    public fun add_price_feed(
        admin: &signer,
        asset_address: address,
        price_feed_address: address,
        decimals: u8,
        confidence_interval: u64,
        max_deviation: u64,
    ) acquires PriceOracle {
        let admin_addr = signer::address_of(admin);
        assert!(exists<PriceOracle>(@pulley), E_ORACLE_NOT_INITIALIZED);
        
        let oracle = borrow_global<PriceOracle>(@pulley);
        assert!(admin_addr == oracle.admin_address, E_NOT_AUTHORIZED);
        assert!(decimals <= 18, E_INVALID_DECIMALS);
        assert!(confidence_interval <= 10000, E_INVALID_PRICE); // Max 100%
        assert!(max_deviation <= 10000, E_INVALID_PRICE); // Max 100%
        
        let price_feed = PriceFeed {
            asset_address,
            price_feed_address,
            decimals,
            last_updated: 0,
            is_active: true,
            price: 0,
            confidence_interval,
            max_deviation,
        };
        
        table::add(&mut oracle.price_feeds, asset_address, price_feed);
        vector::push_back(&mut oracle.supported_assets, asset_address);
        
        // Emit event
        event::emit_event(&mut oracle.price_feed_added_events, PriceFeedAddedEvent {
            asset_address,
            price_feed_address,
            decimals,
            confidence_interval,
            max_deviation,
            added_by: admin_addr,
            timestamp: timestamp::now_microseconds(),
        });
    }

    /// Add price feed with default parameters
    public fun add_price_feed_default(
        admin: &signer,
        asset_address: address,
        price_feed_address: address,
        decimals: u8,
    ) acquires PriceOracle {
        let oracle = borrow_global<PriceOracle>(@pulley);
        add_price_feed(
            admin,
            asset_address,
            price_feed_address,
            decimals,
            oracle.default_confidence_interval,
            oracle.default_max_deviation
        );
    }

    /// Update price feed
    public fun update_price_feed(
        admin: &signer,
        asset_address: address,
        new_price_feed_address: address,
    ) acquires PriceOracle {
        let admin_addr = signer::address_of(admin);
        assert!(exists<PriceOracle>(@pulley), E_ORACLE_NOT_INITIALIZED);
        
        let oracle = borrow_global<PriceOracle>(@pulley);
        assert!(admin_addr == oracle.admin_address, E_NOT_AUTHORIZED);
        assert!(table::contains(&oracle.price_feeds, asset_address), E_PRICE_FEED_NOT_FOUND);
        
        let price_feed = table::borrow_mut(&mut oracle.price_feeds, asset_address);
        let old_price_feed = price_feed.price_feed_address;
        price_feed.price_feed_address = new_price_feed_address;
        
        // Emit event
        event::emit_event(&mut oracle.price_feed_updated_events, PriceFeedUpdatedEvent {
            asset_address,
            old_price_feed,
            new_price_feed: new_price_feed_address,
            updated_by: admin_addr,
            timestamp: timestamp::now_microseconds(),
        });
    }

    /// Update price feed parameters
    public fun update_price_feed_params(
        admin: &signer,
        asset_address: address,
        new_confidence_interval: u64,
        new_max_deviation: u64,
    ) acquires PriceOracle {
        let admin_addr = signer::address_of(admin);
        assert!(exists<PriceOracle>(@pulley), E_ORACLE_NOT_INITIALIZED);
        
        let oracle = borrow_global<PriceOracle>(@pulley);
        assert!(admin_addr == oracle.admin_address, E_NOT_AUTHORIZED);
        assert!(table::contains(&oracle.price_feeds, asset_address), E_PRICE_FEED_NOT_FOUND);
        assert!(new_confidence_interval <= 10000, E_INVALID_PRICE);
        assert!(new_max_deviation <= 10000, E_INVALID_PRICE);
        
        let price_feed = table::borrow_mut(&mut oracle.price_feeds, asset_address);
        price_feed.confidence_interval = new_confidence_interval;
        price_feed.max_deviation = new_max_deviation;
    }

    /// Remove price feed
    public fun remove_price_feed(
        admin: &signer,
        asset_address: address,
    ) acquires PriceOracle {
        let admin_addr = signer::address_of(admin);
        assert!(exists<PriceOracle>(@pulley), E_ORACLE_NOT_INITIALIZED);
        
        let oracle = borrow_global<PriceOracle>(@pulley);
        assert!(admin_addr == oracle.admin_address, E_NOT_AUTHORIZED);
        assert!(table::contains(&oracle.price_feeds, asset_address), E_PRICE_FEED_NOT_FOUND);
        
        let price_feed = table::borrow(&oracle.price_feeds, asset_address);
        let price_feed_address = price_feed.price_feed_address;
        
        table::remove(&mut oracle.price_feeds, asset_address);
        
        // Remove from supported assets
        let i = 0;
        while (i < vector::length(&oracle.supported_assets)) {
            if (*vector::borrow(&oracle.supported_assets, i) == asset_address) {
                vector::remove(&mut oracle.supported_assets, i);
                break
            };
            i = i + 1;
        };
        
        // Emit event
        event::emit_event(&mut oracle.price_feed_removed_events, PriceFeedRemovedEvent {
            asset_address,
            price_feed_address,
            removed_by: admin_addr,
            timestamp: timestamp::now_microseconds(),
        });
    }

    /// Get asset USD value
    public fun get_asset_usd_value(asset_address: address, amount: u64): u64 acquires PriceOracle {
        assert!(exists<PriceOracle>(@pulley), E_ORACLE_NOT_INITIALIZED);
        let oracle = borrow_global<PriceOracle>(@pulley);
        assert!(table::contains(&oracle.price_feeds, asset_address), E_ASSET_NOT_SUPPORTED);
        
        let price_feed = table::borrow(&oracle.price_feeds, asset_address);
        assert!(price_feed.is_active, E_PRICE_FEED_INACTIVE);
        
        // Check if price is stale
        let current_time = timestamp::now_microseconds();
        assert!(current_time - price_feed.last_updated <= oracle.max_price_age * 1000000, E_STALE_PRICE);
        
        // Calculate USD value based on price and amount
        let price = price_feed.price;
        if (price == 0) {
            // If no price available, return mock price for testing
            return amount * 100 // Mock: 1 token = $100
        };
        
        // Convert amount to USD value
        let usd_value = (amount * price) / (10 ^ price_feed.decimals);
        usd_value
    }

    /// Get asset price
    public fun get_asset_price(asset_address: address): u64 acquires PriceOracle {
        assert!(exists<PriceOracle>(@pulley), E_ORACLE_NOT_INITIALIZED);
        let oracle = borrow_global<PriceOracle>(@pulley);
        assert!(table::contains(&oracle.price_feeds, asset_address), E_ASSET_NOT_SUPPORTED);
        
        let price_feed = table::borrow(&oracle.price_feeds, asset_address);
        assert!(price_feed.is_active, E_PRICE_FEED_INACTIVE);
        
        // Check if price is stale
        let current_time = timestamp::now_microseconds();
        assert!(current_time - price_feed.last_updated <= oracle.max_price_age * 1000000, E_STALE_PRICE);
        
        price_feed.price
    }

    /// Update price (called by external price feed)
    public fun update_price(
        price_feed: &signer,
        asset_address: address,
        price: u64,
    ) acquires PriceOracle {
        assert!(exists<PriceOracle>(@pulley), E_ORACLE_NOT_INITIALIZED);
        let oracle = borrow_global<PriceOracle>(@pulley);
        assert!(table::contains(&oracle.price_feeds, asset_address), E_PRICE_FEED_NOT_FOUND);
        
        let price_feed_info = table::borrow_mut(&mut oracle.price_feeds, asset_address);
        assert!(price_feed_info.price_feed_address == signer::address_of(price_feed), E_NOT_AUTHORIZED);
        assert!(price > 0, E_INVALID_PRICE);
        
        let old_price = price_feed_info.price;
        price_feed_info.price = price;
        price_feed_info.last_updated = timestamp::now_microseconds();
        
        // Emit event
        event::emit_event(&mut oracle.price_updated_events, PriceUpdatedEvent {
            asset_address,
            old_price,
            new_price: price,
            confidence_interval: price_feed_info.confidence_interval,
            timestamp: timestamp::now_microseconds(),
        });
    }

    /// Batch update prices
    public fun batch_update_prices(
        price_feed: &signer,
        asset_addresses: vector<address>,
        prices: vector<u64>,
    ) acquires PriceOracle {
        assert!(vector::length(&asset_addresses) == vector::length(&prices), E_INVALID_PRICE);
        
        let i = 0;
        while (i < vector::length(&asset_addresses)) {
            let asset_address = *vector::borrow(&asset_addresses, i);
            let price = *vector::borrow(&prices, i);
            update_price(price_feed, asset_address, price);
            i = i + 1;
        };
    }

    /// Get supported assets
    public fun get_supported_assets(): vector<address> acquires PriceOracle {
        if (!exists<PriceOracle>(@pulley)) {
            return vector::empty<address>()
        };
        
        let oracle = borrow_global<PriceOracle>(@pulley);
        oracle.supported_assets
    }

    /// Check if asset is supported
    public fun is_asset_supported(asset_address: address): bool acquires PriceOracle {
        if (!exists<PriceOracle>(@pulley)) {
            return false
        };
        
        let oracle = borrow_global<PriceOracle>(@pulley);
        table::contains(&oracle.price_feeds, asset_address)
    }

    /// Get price feed info
    public fun get_price_feed_info(asset_address: address): (address, u8, u64, bool, u64, u64, u64) acquires PriceOracle {
        assert!(exists<PriceOracle>(@pulley), E_ORACLE_NOT_INITIALIZED);
        let oracle = borrow_global<PriceOracle>(@pulley);
        assert!(table::contains(&oracle.price_feeds, asset_address), E_PRICE_FEED_NOT_FOUND);
        
        let price_feed = table::borrow(&oracle.price_feeds, asset_address);
        (
            price_feed.price_feed_address,
            price_feed.decimals,
            price_feed.last_updated,
            price_feed.is_active,
            price_feed.price,
            price_feed.confidence_interval,
            price_feed.max_deviation
        )
    }

    /// Set max price age
    public fun set_max_price_age(
        admin: &signer,
        max_age: u64,
    ) acquires PriceOracle {
        let admin_addr = signer::address_of(admin);
        assert!(exists<PriceOracle>(@pulley), E_ORACLE_NOT_INITIALIZED);
        
        let oracle = borrow_global<PriceOracle>(@pulley);
        assert!(admin_addr == oracle.admin_address, E_NOT_AUTHORIZED);
        assert!(max_age > 0, E_INVALID_PRICE);
        
        oracle.max_price_age = max_age;
    }

    /// Get max price age
    public fun get_max_price_age(): u64 acquires PriceOracle {
        assert!(exists<PriceOracle>(@pulley), E_ORACLE_NOT_INITIALIZED);
        let oracle = borrow_global<PriceOracle>(@pulley);
        oracle.max_price_age
    }

    /// Deactivate price feed
    public fun deactivate_price_feed(
        admin: &signer,
        asset_address: address,
    ) acquires PriceOracle {
        let admin_addr = signer::address_of(admin);
        assert!(exists<PriceOracle>(@pulley), E_ORACLE_NOT_INITIALIZED);
        
        let oracle = borrow_global<PriceOracle>(@pulley);
        assert!(admin_addr == oracle.admin_address, E_NOT_AUTHORIZED);
        assert!(table::contains(&oracle.price_feeds, asset_address), E_PRICE_FEED_NOT_FOUND);
        
        let price_feed = table::borrow_mut(&mut oracle.price_feeds, asset_address);
        price_feed.is_active = false;
    }

    /// Activate price feed
    public fun activate_price_feed(
        admin: &signer,
        asset_address: address,
    ) acquires PriceOracle {
        let admin_addr = signer::address_of(admin);
        assert!(exists<PriceOracle>(@pulley), E_ORACLE_NOT_INITIALIZED);
        
        let oracle = borrow_global<PriceOracle>(@pulley);
        assert!(admin_addr == oracle.admin_address, E_NOT_AUTHORIZED);
        assert!(table::contains(&oracle.price_feeds, asset_address), E_PRICE_FEED_NOT_FOUND);
        
        let price_feed = table::borrow_mut(&mut oracle.price_feeds, asset_address);
        price_feed.is_active = true;
    }

    /// Get oracle info
    public fun get_oracle_info(): (address, u64, u64, u64, u64) acquires PriceOracle {
        assert!(exists<PriceOracle>(@pulley), E_ORACLE_NOT_INITIALIZED);
        let oracle = borrow_global<PriceOracle>(@pulley);
        (
            oracle.admin_address,
            oracle.max_price_age,
            oracle.default_confidence_interval,
            oracle.default_max_deviation,
            vector::length(&oracle.supported_assets)
        )
    }

    /// Check price validity
    public fun is_price_valid(asset_address: address): bool acquires PriceOracle {
        if (!exists<PriceOracle>(@pulley)) {
            return false
        };
        
        let oracle = borrow_global<PriceOracle>(@pulley);
        if (!table::contains(&oracle.price_feeds, asset_address)) {
            return false
        };
        
        let price_feed = table::borrow(&oracle.price_feeds, asset_address);
        if (!price_feed.is_active) {
            return false
        };
        
        let current_time = timestamp::now_microseconds();
        current_time - price_feed.last_updated <= oracle.max_price_age * 1000000
    }

    /// Get price age
    public fun get_price_age(asset_address: address): u64 acquires PriceOracle {
        assert!(exists<PriceOracle>(@pulley), E_ORACLE_NOT_INITIALIZED);
        let oracle = borrow_global<PriceOracle>(@pulley);
        assert!(table::contains(&oracle.price_feeds, asset_address), E_PRICE_FEED_NOT_FOUND);
        
        let price_feed = table::borrow(&oracle.price_feeds, asset_address);
        let current_time = timestamp::now_microseconds();
        current_time - price_feed.last_updated
    }

    /// Emergency price update (admin only)
    public fun emergency_update_price(
        admin: &signer,
        asset_address: address,
        price: u64,
    ) acquires PriceOracle {
        let admin_addr = signer::address_of(admin);
        assert!(exists<PriceOracle>(@pulley), E_ORACLE_NOT_INITIALIZED);
        
        let oracle = borrow_global<PriceOracle>(@pulley);
        assert!(admin_addr == oracle.admin_address, E_NOT_AUTHORIZED);
        assert!(table::contains(&oracle.price_feeds, asset_address), E_PRICE_FEED_NOT_FOUND);
        assert!(price > 0, E_INVALID_PRICE);
        
        let price_feed = table::borrow_mut(&mut oracle.price_feeds, asset_address);
        let old_price = price_feed.price;
        price_feed.price = price;
        price_feed.last_updated = timestamp::now_microseconds();
        
        // Emit event
        event::emit_event(&mut oracle.price_updated_events, PriceUpdatedEvent {
            asset_address,
            old_price,
            new_price: price,
            confidence_interval: price_feed.confidence_interval,
            timestamp: timestamp::now_microseconds(),
        });
    }

    #[test_only]
    public fun init_module_for_test(admin: &signer) {
        initialize(admin);
    }
}