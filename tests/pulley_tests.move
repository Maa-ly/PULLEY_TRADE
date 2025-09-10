/// Comprehensive test suite for Pulley Aptos implementation
/// Tests all core functionality including trading pools, controller, insurance token, AI wallet, and clone factory
module pulley::pulley_tests {
    use std::signer;
    use std::string;
    use std::vector;
    use aptos_framework::aptos_coin;
    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use pulley::trading_pool;
    use pulley::controller;
    use pulley::insurance_token;
    use pulley::ai_wallet;
    use pulley::clone_factory;
    use pulley::permission_manager;
    use pulley::price_oracle;

    /// Test constants
    const TEST_THRESHOLD: u64 = 1000000; // 1 USDC
    const TEST_AMOUNT: u64 = 500000; // 0.5 USDC
    const TEST_PRICE: u64 = 100000000; // $100 per token

    /// Test setup
    fun setup_test(): (signer, signer, signer, signer, signer) {
        let admin = account::create_account_for_test(@0x1);
        let user1 = account::create_account_for_test(@0x2);
        let user2 = account::create_account_for_test(@0x3);
        let ai_signer = account::create_account_for_test(@0x4);
        let price_feed = account::create_account_for_test(@0x5);
        
        // Initialize all modules
        price_oracle::init_module_for_test(&admin);
        permission_manager::init_module_for_test(&admin);
        insurance_token::init_module_for_test(&admin);
        trading_pool::init_module_for_test(&admin);
        controller::init_module_for_test(&admin);
        ai_wallet::init_module_for_test(&ai_signer);
        clone_factory::init_module_for_test(&admin, @0x0, @0x0, @0x0, @0x0, @0x0);
        
        (admin, user1, user2, ai_signer, price_feed)
    }

    /// Test price oracle functionality
    #[test]
    fun test_price_oracle_basic() {
        let (admin, user1, user2, ai_signer, price_feed) = setup_test();
        
        // Add price feed
        price_oracle::add_price_feed_default(
            &admin,
            @0x1, // APT
            signer::address_of(&price_feed),
            8
        );
        
        // Update price
        price_oracle::update_price(&price_feed, @0x1, TEST_PRICE);
        
        // Test price retrieval
        let price = price_oracle::get_asset_price(@0x1);
        assert!(price == TEST_PRICE, 0);
        
        // Test USD value calculation
        let usd_value = price_oracle::get_asset_usd_value(@0x1, 1000000);
        assert!(usd_value == 100000000, 1); // 1 token = $100
        
        // Test asset support
        assert!(price_oracle::is_asset_supported(@0x1), 2);
        assert!(!price_oracle::is_asset_supported(@0x2), 3);
    }

    /// Test permission manager functionality
    #[test]
    fun test_permission_manager_basic() {
        let (admin, user1, user2, ai_signer, price_feed) = setup_test();
        
        // Test role assignment
        permission_manager::assign_role(&admin, signer::address_of(&user1), permission_manager::ROLE_TRADER);
        permission_manager::assign_role(&admin, signer::address_of(&user2), permission_manager::ROLE_AI_WALLET);
        
        // Test permission checks
        assert!(permission_manager::has_permission(signer::address_of(&user1), permission_manager::PERMISSION_DEPOSIT), 0);
        assert!(permission_manager::has_permission(signer::address_of(&user1), permission_manager::PERMISSION_TRADE), 1);
        assert!(!permission_manager::has_permission(signer::address_of(&user1), permission_manager::PERMISSION_MANAGE_POOL), 2);
        
        // Test role checks
        assert!(permission_manager::is_trader(signer::address_of(&user1)), 3);
        assert!(permission_manager::is_ai_wallet(signer::address_of(&user2)), 4);
        assert!(!permission_manager::is_admin(signer::address_of(&user1)), 5);
        
        // Test role revocation
        permission_manager::revoke_role(&admin, signer::address_of(&user1), permission_manager::ROLE_TRADER);
        assert!(!permission_manager::has_permission(signer::address_of(&user1), permission_manager::PERMISSION_DEPOSIT), 6);
    }

    /// Test insurance token functionality
    #[test]
    fun test_insurance_token_basic() {
        let (admin, user1, user2, ai_signer, price_feed) = setup_test();
        
        // Test initial state
        let total_supply = insurance_token::get_total_supply();
        assert!(total_supply == 0, 0);
        
        // Test minting
        insurance_token::mint_insurance(&admin, signer::address_of(&user1), TEST_AMOUNT);
        let balance = insurance_token::balance_of(signer::address_of(&user1));
        assert!(balance == TEST_AMOUNT, 1);
        
        // Test price calculation
        let price = insurance_token::get_current_price();
        assert!(price > 0, 2);
        
        // Test burning
        insurance_token::burn(&user1, TEST_AMOUNT / 2);
        let new_balance = insurance_token::balance_of(signer::address_of(&user1));
        assert!(new_balance == TEST_AMOUNT / 2, 3);
    }

    /// Test trading pool functionality
    #[test]
    fun test_trading_pool_basic() {
        let (admin, user1, user2, ai_signer, price_feed) = setup_test();
        
        // Add asset to oracle
        price_oracle::add_price_feed_default(
            &admin,
            @0x1, // APT
            signer::address_of(&price_feed),
            8
        );
        price_oracle::update_price(&price_feed, @0x1, TEST_PRICE);
        
        // Initialize trading pool
        trading_pool::initialize<aptos_coin::AptosCoin>(
            &admin,
            TEST_THRESHOLD,
            @pulley // controller address
        );
        
        // Add asset to pool
        trading_pool::add_asset<aptos_coin::AptosCoin>(
            &admin,
            @pulley,
            @0x1,
            8,
            TEST_THRESHOLD,
            signer::address_of(&price_feed)
        );
        
        // Test deposit
        trading_pool::deposit<aptos_coin::AptosCoin>(
            &user1,
            @pulley,
            @0x1,
            TEST_AMOUNT
        );
        
        // Test pool info
        let pool_info = trading_pool::get_pool_info<aptos_coin::AptosCoin>(@pulley);
        assert!(pool_info.0 == TEST_THRESHOLD, 0); // threshold
        assert!(pool_info.1 > 0, 1); // total pool value
        
        // Test user info
        let user_info = trading_pool::get_user_info<aptos_coin::AptosCoin>(@pulley, signer::address_of(&user1));
        assert!(user_info.0 > 0, 2); // user pool tokens
        assert!(user_info.1 > 0, 3); // user USD value
    }

    /// Test controller functionality
    #[test]
    fun test_controller_basic() {
        let (admin, user1, user2, ai_signer, price_feed) = setup_test();
        
        // Initialize controller
        controller::initialize<aptos_coin::AptosCoin>(
            &admin,
            @pulley, // trading pool address
            @pulley, // insurance admin
            @pulley, // AI wallet address
            vector::empty<address>()
        );
        
        // Test fund allocation
        controller::allocate_funds<aptos_coin::AptosCoin>(
            &admin,
            @pulley,
            @0x1, // asset
            TEST_AMOUNT
        );
        
        // Test system metrics
        let metrics = controller::get_system_metrics<aptos_coin::AptosCoin>(@pulley);
        assert!(metrics.0 > 0, 0); // total funds
        assert!(metrics.1 > 0, 1); // insurance allocation
        assert!(metrics.2 > 0, 2); // trading allocation
    }

    /// Test AI wallet functionality
    #[test]
    fun test_ai_wallet_basic() {
        let (admin, user1, user2, ai_signer, price_feed) = setup_test();
        
        // Initialize AI wallet
        ai_wallet::initialize<aptos_coin::AptosCoin>(
            &ai_signer,
            @pulley, // controller address
            @pulley // AI signer address
        );
        
        // Test session info
        let session_info = ai_wallet::get_session_info<aptos_coin::AptosCoin>(@pulley);
        assert!(session_info.0 == 0, 0); // session ID
        assert!(session_info.1 == 0, 1); // balance
        
        // Test fund transfer (simplified for testing)
        ai_wallet::receive_funds<aptos_coin::AptosCoin>(
            &ai_signer,
            @pulley,
            @0x1, // asset
            TEST_AMOUNT
        );
        
        let new_session_info = ai_wallet::get_session_info<aptos_coin::AptosCoin>(@pulley);
        assert!(new_session_info.1 == TEST_AMOUNT, 2); // balance
    }

    /// Test clone factory functionality
    #[test]
    fun test_clone_factory_basic() {
        let (admin, user1, user2, ai_signer, price_feed) = setup_test();
        
        // Test strategy creation
        let supported_assets = vector::empty<address>();
        vector::push_back(&mut supported_assets, @0x1);
        
        let asset_thresholds = vector::empty<u64>();
        vector::push_back(&mut asset_thresholds, TEST_THRESHOLD);
        
        let asset_decimals = vector::empty<u8>();
        vector::push_back(&mut asset_decimals, 8);
        
        let price_feeds = vector::empty<address>();
        vector::push_back(&mut price_feeds, signer::address_of(&price_feed));
        
        let strategy_address = clone_factory::create_strategy(
            &user1,
            @pulley, // factory address
            string::utf8(b"Test Strategy"),
            string::utf8(b"TS"),
            TEST_THRESHOLD,
            supported_assets,
            asset_thresholds,
            asset_decimals,
            price_feeds
        );
        
        // Test strategy info
        let strategy_info = clone_factory::get_strategy_info(@pulley, strategy_address);
        assert!(string::bytes(&strategy_info.0) == b"Test Strategy", 0);
        assert!(strategy_info.1 == TEST_THRESHOLD, 1);
        assert!(strategy_info.3 == true, 2); // is_active
        
        // Test strategy count
        let count = clone_factory::get_strategy_count(@pulley);
        assert!(count == 1, 3);
    }

    /// Test end-to-end trading flow
    #[test]
    fun test_end_to_end_trading_flow() {
        let (admin, user1, user2, ai_signer, price_feed) = setup_test();
        
        // Setup price oracle
        price_oracle::add_price_feed_default(
            &admin,
            @0x1, // APT
            signer::address_of(&price_feed),
            8
        );
        price_oracle::update_price(&price_feed, @0x1, TEST_PRICE);
        
        // Setup trading pool
        trading_pool::initialize<aptos_coin::AptosCoin>(
            &admin,
            TEST_THRESHOLD,
            @pulley
        );
        trading_pool::add_asset<aptos_coin::AptosCoin>(
            &admin,
            @pulley,
            @0x1,
            8,
            TEST_THRESHOLD,
            signer::address_of(&price_feed)
        );
        
        // Setup controller
        controller::initialize<aptos_coin::AptosCoin>(
            &admin,
            @pulley,
            @pulley,
            @pulley,
            vector::empty<address>()
        );
        
        // Setup AI wallet
        ai_wallet::initialize<aptos_coin::AptosCoin>(
            &ai_signer,
            @pulley,
            @pulley
        );
        
        // User deposits
        trading_pool::deposit<aptos_coin::AptosCoin>(
            &user1,
            @pulley,
            @0x1,
            TEST_AMOUNT
        );
        
        // Check pool state
        let pool_info = trading_pool::get_pool_info<aptos_coin::AptosCoin>(@pulley);
        assert!(pool_info.1 > 0, 0); // total pool value
        
        // Check if new period can start
        let can_start = trading_pool::can_start_new_period<aptos_coin::AptosCoin>(@pulley, @0x1);
        assert!(can_start, 1);
        
        // Check available funds for trading
        let available_funds = trading_pool::get_available_funds_for_trading<aptos_coin::AptosCoin>(@pulley, @0x1);
        assert!(available_funds > 0, 2);
    }

    /// Test error handling
    #[test]
    #[expected_failure(abort_code = pulley::trading_pool::E_UNSUPPORTED_ASSET)]
    fun test_unsupported_asset_error() {
        let (admin, user1, user2, ai_signer, price_feed) = setup_test();
        
        trading_pool::initialize<aptos_coin::AptosCoin>(
            &admin,
            TEST_THRESHOLD,
            @pulley
        );
        
        // Try to deposit unsupported asset
        trading_pool::deposit<aptos_coin::AptosCoin>(
            &user1,
            @pulley,
            @0x1, // unsupported asset
            TEST_AMOUNT
        );
    }

    /// Test permission errors
    #[test]
    #[expected_failure(abort_code = pulley::permission_manager::E_PERMISSION_DENIED)]
    fun test_permission_denied_error() {
        let (admin, user1, user2, ai_signer, price_feed) = setup_test();
        
        // Try to assign role without admin permission
        permission_manager::assign_role(&user1, signer::address_of(&user2), permission_manager::ROLE_TRADER);
    }

    /// Test oracle errors
    #[test]
    #[expected_failure(abort_code = pulley::price_oracle::E_ASSET_NOT_SUPPORTED)]
    fun test_unsupported_asset_oracle_error() {
        let (admin, user1, user2, ai_signer, price_feed) = setup_test();
        
        // Try to get price for unsupported asset
        price_oracle::get_asset_price(@0x1);
    }

    /// Test insurance token errors
    #[test]
    #[expected_failure(abort_code = pulley::insurance_token::E_INSUFFICIENT_BALANCE)]
    fun test_insufficient_balance_error() {
        let (admin, user1, user2, ai_signer, price_feed) = setup_test();
        
        // Try to burn more than balance
        insurance_token::burn(&user1, TEST_AMOUNT);
    }

    /// Test controller errors
    #[test]
    #[expected_failure(abort_code = pulley::controller::E_AI_WALLET_NOT_SET)]
    fun test_ai_wallet_not_set_error() {
        let (admin, user1, user2, ai_signer, price_feed) = setup_test();
        
        // Initialize controller without AI wallet
        controller::initialize<aptos_coin::AptosCoin>(
            &admin,
            @pulley,
            @pulley,
            @0x0, // no AI wallet
            vector::empty<address>()
        );
        
        // Try to check AI wallet PnL
        controller::check_ai_wallet_pnl<aptos_coin::AptosCoin>(&admin, @pulley, @0x1, 1000);
    }

    /// Test clone factory errors
    #[test]
    #[expected_failure(abort_code = pulley::clone_factory::E_INVALID_THRESHOLD)]
    fun test_invalid_threshold_error() {
        let (admin, user1, user2, ai_signer, price_feed) = setup_test();
        
        // Try to create strategy with invalid threshold
        clone_factory::create_strategy(
            &user1,
            @pulley,
            string::utf8(b"Test"),
            string::utf8(b"T"),
            0, // invalid threshold
            vector::empty<address>(),
            vector::empty<u64>(),
            vector::empty<u8>(),
            vector::empty<address>()
        );
    }

    /// Test AI wallet errors
    #[test]
    #[expected_failure(abort_code = pulley::ai_wallet::E_NOT_AUTHORIZED)]
    fun test_ai_wallet_unauthorized_error() {
        let (admin, user1, user2, ai_signer, price_feed) = setup_test();
        
        ai_wallet::initialize<aptos_coin::AptosCoin>(
            &ai_signer,
            @pulley,
            @pulley
        );
        
        // Try to send funds without authorization
        ai_wallet::send_funds<aptos_coin::AptosCoin>(
            &user1, // not AI signer
            @pulley,
            @0x1,
            TEST_AMOUNT,
            vector::empty<u8>() // empty signature
        );
    }

    /// Test trading pool period management
    #[test]
    fun test_trading_pool_period_management() {
        let (admin, user1, user2, ai_signer, price_feed) = setup_test();
        
        // Setup
        price_oracle::add_price_feed_default(&admin, @0x1, signer::address_of(&price_feed), 8);
        price_oracle::update_price(&price_feed, @0x1, TEST_PRICE);
        
        trading_pool::initialize<aptos_coin::AptosCoin>(&admin, TEST_THRESHOLD, @pulley);
        trading_pool::add_asset<aptos_coin::AptosCoin>(
            &admin,
            @pulley,
            @0x1,
            8,
            TEST_THRESHOLD,
            signer::address_of(&price_feed)
        );
        
        // Deposit to trigger period start
        trading_pool::deposit<aptos_coin::AptosCoin>(&user1, @pulley, @0x1, TEST_AMOUNT);
        
        // Check active periods
        let active_periods = trading_pool::get_active_periods<aptos_coin::AptosCoin>(@pulley, @0x1);
        assert!(vector::length(&active_periods) > 0, 0);
        
        // Check period allocation
        let allocation = trading_pool::get_period_allocation<aptos_coin::AptosCoin>(@pulley, @0x1, 0);
        assert!(allocation > 0, 1);
    }

    /// Test profit distribution
    #[test]
    fun test_profit_distribution() {
        let (admin, user1, user2, ai_signer, price_feed) = setup_test();
        
        // Setup
        price_oracle::add_price_feed_default(&admin, @0x1, signer::address_of(&price_feed), 8);
        price_oracle::update_price(&price_feed, @0x1, TEST_PRICE);
        
        trading_pool::initialize<aptos_coin::AptosCoin>(&admin, TEST_THRESHOLD, @pulley);
        trading_pool::add_asset<aptos_coin::AptosCoin>(
            &admin,
            @pulley,
            @0x1,
            8,
            TEST_THRESHOLD,
            signer::address_of(&price_feed)
        );
        
        // Deposit
        trading_pool::deposit<aptos_coin::AptosCoin>(&user1, @pulley, @0x1, TEST_AMOUNT);
        
        // Record profit
        trading_pool::record_profit<aptos_coin::AptosCoin>(&admin, @pulley, @0x1, 100000); // $100 profit
        
        // Check profit distribution
        let pool_info = trading_pool::get_pool_info<aptos_coin::AptosCoin>(@pulley);
        assert!(pool_info.2 > 0, 0); // total profits
    }

    /// Test insurance token growth mechanism
    #[test]
    fun test_insurance_token_growth() {
        let (admin, user1, user2, ai_signer, price_feed) = setup_test();
        
        // Mint initial tokens
        insurance_token::mint_insurance(&admin, signer::address_of(&user1), TEST_AMOUNT);
        
        // Update utilization
        insurance_token::update_utilization(&admin, 5000); // 50% utilization
        
        // Update growth
        insurance_token::update_growth(&admin);
        
        // Check growth metrics
        let growth_metrics = insurance_token::get_growth_metrics();
        assert!(growth_metrics.0 > 0, 0); // utilization rate
        assert!(growth_metrics.1 > 0, 1); // growth rate
    }

    /// Test clone factory quick create
    #[test]
    fun test_clone_factory_quick_create() {
        let (admin, user1, user2, ai_signer, price_feed) = setup_test();
        
        // Quick create clone
        let strategy_address = clone_factory::quick_create_clone(
            &user1,
            @pulley,
            @0x1, // native asset
            @0x2, // custom asset
            8, // decimals
            TEST_THRESHOLD
        );
        
        // Verify strategy exists
        assert!(clone_factory::strategy_exists(@pulley, strategy_address), 0);
        
        // Check strategy count
        let count = clone_factory::get_strategy_count(@pulley);
        assert!(count == 1, 1);
    }

    /// Test permission manager role management
    #[test]
    fun test_permission_manager_role_management() {
        let (admin, user1, user2, ai_signer, price_feed) = setup_test();
        
        // Create custom role
        let custom_permissions = vector::empty<u64>();
        vector::push_back(&mut custom_permissions, permission_manager::PERMISSION_VIEW);
        vector::push_back(&mut custom_permissions, permission_manager::PERMISSION_TRADE);
        
        permission_manager::create_role(
            &admin,
            100, // custom role ID
            string::utf8(b"CUSTOM_TRADER"),
            custom_permissions
        );
        
        // Assign custom role
        permission_manager::assign_role(&admin, signer::address_of(&user1), 100);
        
        // Test permissions
        assert!(permission_manager::has_permission(signer::address_of(&user1), permission_manager::PERMISSION_VIEW), 0);
        assert!(permission_manager::has_permission(signer::address_of(&user1), permission_manager::PERMISSION_TRADE), 1);
        assert!(!permission_manager::has_permission(signer::address_of(&user1), permission_manager::PERMISSION_MANAGE_POOL), 2);
    }

    /// Test price oracle batch operations
    #[test]
    fun test_price_oracle_batch_operations() {
        let (admin, user1, user2, ai_signer, price_feed) = setup_test();
        
        // Add multiple assets
        price_oracle::add_price_feed_default(&admin, @0x1, signer::address_of(&price_feed), 8);
        price_oracle::add_price_feed_default(&admin, @0x2, signer::address_of(&price_feed), 6);
        price_oracle::add_price_feed_default(&admin, @0x3, signer::address_of(&price_feed), 18);
        
        // Batch update prices
        let assets = vector::empty<address>();
        vector::push_back(&mut assets, @0x1);
        vector::push_back(&mut assets, @0x2);
        vector::push_back(&mut assets, @0x3);
        
        let prices = vector::empty<u64>();
        vector::push_back(&mut prices, 100000000); // $100
        vector::push_back(&mut prices, 200000000); // $200
        vector::push_back(&mut prices, 300000000); // $300
        
        price_oracle::batch_update_prices(&price_feed, assets, prices);
        
        // Verify prices
        assert!(price_oracle::get_asset_price(@0x1) == 100000000, 0);
        assert!(price_oracle::get_asset_price(@0x2) == 200000000, 1);
        assert!(price_oracle::get_asset_price(@0x3) == 300000000, 2);
    }

    /// Test comprehensive system integration
    #[test]
    fun test_comprehensive_system_integration() {
        let (admin, user1, user2, ai_signer, price_feed) = setup_test();
        
        // Setup complete system
        price_oracle::add_price_feed_default(&admin, @0x1, signer::address_of(&price_feed), 8);
        price_oracle::update_price(&price_feed, @0x1, TEST_PRICE);
        
        trading_pool::initialize<aptos_coin::AptosCoin>(&admin, TEST_THRESHOLD, @pulley);
        trading_pool::add_asset<aptos_coin::AptosCoin>(
            &admin,
            @pulley,
            @0x1,
            8,
            TEST_THRESHOLD,
            signer::address_of(&price_feed)
        );
        
        controller::initialize<aptos_coin::AptosCoin>(&admin, @pulley, @pulley, @pulley, vector::empty<address>());
        ai_wallet::initialize<aptos_coin::AptosCoin>(&ai_signer, @pulley, @pulley);
        
        // Assign roles
        permission_manager::assign_role(&admin, signer::address_of(&user1), permission_manager::ROLE_TRADER);
        permission_manager::assign_role(&admin, signer::address_of(&ai_signer), permission_manager::ROLE_AI_WALLET);
        
        // User deposits
        trading_pool::deposit<aptos_coin::AptosCoin>(&user1, @pulley, @0x1, TEST_AMOUNT);
        
        // Check system state
        let pool_info = trading_pool::get_pool_info<aptos_coin::AptosCoin>(@pulley);
        let controller_metrics = controller::get_system_metrics<aptos_coin::AptosCoin>(@pulley);
        let insurance_info = insurance_token::get_insurance_info();
        
        // Verify system is working
        assert!(pool_info.1 > 0, 0); // pool has value
        assert!(controller_metrics.0 > 0, 1); // controller has funds
        assert!(insurance_info.0 > 0, 2); // insurance has reserve
        assert!(permission_manager::is_trader(signer::address_of(&user1)), 3);
        assert!(permission_manager::is_ai_wallet(signer::address_of(&ai_signer)), 4);
    }
}
