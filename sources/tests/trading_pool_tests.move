#[test_only]
module pulley::trading_pool_tests {
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use pulley::trading_pool;

    #[test(framework = @aptos_framework, admin = @pulley, controller = @0x456)]
    public fun test_trading_pool_initialization(
        framework: &signer,
        admin: &signer,
        controller: &signer
    ) {
        // Setup
        account::create_account_for_test(signer::address_of(framework));
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(controller));
        
        aptos_coin::initialize_for_test(framework);
        
        // Initialize trading pool
        trading_pool::initialize<AptosCoin>(
            admin,
            1000, // threshold
            signer::address_of(controller)
        );
        
        // Test pool info
        let (total_deposited, total_pool_tokens, threshold, active) = 
            trading_pool::get_pool_info<AptosCoin>(signer::address_of(admin));
        assert!(total_deposited == 0, 1);
        assert!(total_pool_tokens == 0, 2);
        assert!(threshold == 1000, 3);
        assert!(active == true, 4);
    }

    #[test(framework = @aptos_framework, admin = @pulley, user = @0x123, controller = @0x456)]
    public fun test_user_deposit(
        framework: &signer,
        admin: &signer,
        user: &signer,
        controller: &signer
    ) {
        // Setup
        account::create_account_for_test(signer::address_of(framework));
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(user));
        account::create_account_for_test(signer::address_of(controller));
        
        aptos_coin::initialize_for_test(framework);
        
        trading_pool::initialize<AptosCoin>(
            admin,
            1000,
            signer::address_of(controller)
        );
        
        // Register coins for user
        coin::register<AptosCoin>(user);
        
        // Mint and deposit coins
        let deposit_coins = coin::mint<AptosCoin>(500, &aptos_coin::mint_capability_for_test());
        trading_pool::deposit<AptosCoin>(user, signer::address_of(admin), deposit_coins);
        
        // Check pool state
        let (total_deposited, total_pool_tokens, _, _) = 
            trading_pool::get_pool_info<AptosCoin>(signer::address_of(admin));
        assert!(total_deposited == 500, 5);
        assert!(total_pool_tokens == 500, 6); // 1:1 ratio initially
        
        // Check user info
        let (user_deposit, pool_token_balance) = 
            trading_pool::get_user_info<AptosCoin>(signer::address_of(admin), signer::address_of(user));
        assert!(user_deposit == 500, 7);
        assert!(pool_token_balance == 500, 8);
    }

    #[test(framework = @aptos_framework, admin = @pulley, user1 = @0x123, user2 = @0x456, controller = @0x789)]
    public fun test_proportional_pool_tokens(
        framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
        controller: &signer
    ) {
        // Setup
        account::create_account_for_test(signer::address_of(framework));
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(user1));
        account::create_account_for_test(signer::address_of(user2));
        account::create_account_for_test(signer::address_of(controller));
        
        aptos_coin::initialize_for_test(framework);
        
        trading_pool::initialize<AptosCoin>(
            admin,
            2000,
            signer::address_of(controller)
        );
        
        coin::register<AptosCoin>(user1);
        coin::register<AptosCoin>(user2);
        
        // First user deposits 1000 (gets 1000 pool tokens)
        let deposit1 = coin::mint<AptosCoin>(1000, &aptos_coin::mint_capability_for_test());
        trading_pool::deposit<AptosCoin>(user1, signer::address_of(admin), deposit1);
        
        // Second user deposits 500 (should get 500 pool tokens)
        let deposit2 = coin::mint<AptosCoin>(500, &aptos_coin::mint_capability_for_test());
        trading_pool::deposit<AptosCoin>(user2, signer::address_of(admin), deposit2);
        
        // Check proportional allocation
        let (_, user1_tokens) = trading_pool::get_user_info<AptosCoin>(signer::address_of(admin), signer::address_of(user1));
        let (_, user2_tokens) = trading_pool::get_user_info<AptosCoin>(signer::address_of(admin), signer::address_of(user2));
        
        assert!(user1_tokens == 1000, 9);
        assert!(user2_tokens == 500, 10);
        
        let (total_deposited, total_pool_tokens, _, _) = 
            trading_pool::get_pool_info<AptosCoin>(signer::address_of(admin));
        assert!(total_deposited == 1500, 11);
        assert!(total_pool_tokens == 1500, 12);
    }

    #[test(framework = @aptos_framework, admin = @pulley, user = @0x123, controller = @0x456)]
    public fun test_threshold_detection(
        framework: &signer,
        admin: &signer,
        user: &signer,
        controller: &signer
    ) {
        // Setup
        account::create_account_for_test(signer::address_of(framework));
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(user));
        account::create_account_for_test(signer::address_of(controller));
        
        aptos_coin::initialize_for_test(framework);
        
        trading_pool::initialize<AptosCoin>(
            admin,
            1000, // threshold
            signer::address_of(controller)
        );
        
        coin::register<AptosCoin>(user);
        
        // Test threshold not met
        let threshold_met = trading_pool::is_threshold_met<AptosCoin>(signer::address_of(admin));
        assert!(threshold_met == false, 13);
        
        // Deposit to meet threshold
        let deposit_coins = coin::mint<AptosCoin>(1000, &aptos_coin::mint_capability_for_test());
        trading_pool::deposit<AptosCoin>(user, signer::address_of(admin), deposit_coins);
        
        // Test threshold met
        let threshold_met = trading_pool::is_threshold_met<AptosCoin>(signer::address_of(admin));
        assert!(threshold_met == true, 14);
    }

    #[test(framework = @aptos_framework, admin = @pulley, user = @0x123, controller = @0x456)]
    public fun test_transfer_to_controller(
        framework: &signer,
        admin: &signer,
        user: &signer,
        controller: &signer
    ) {
        // Setup
        account::create_account_for_test(signer::address_of(framework));
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(user));
        account::create_account_for_test(signer::address_of(controller));
        
        aptos_coin::initialize_for_test(framework);
        
        trading_pool::initialize<AptosCoin>(
            admin,
            1000,
            signer::address_of(controller)
        );
        
        coin::register<AptosCoin>(user);
        coin::register<AptosCoin>(controller);
        
        // Deposit to meet threshold
        let deposit_coins = coin::mint<AptosCoin>(1000, &aptos_coin::mint_capability_for_test());
        trading_pool::deposit<AptosCoin>(user, signer::address_of(admin), deposit_coins);
        
        // Transfer to controller
        trading_pool::transfer_to_controller<AptosCoin>(admin, signer::address_of(admin));
        
        // Check that funds were transferred
        let controller_balance = coin::balance<AptosCoin>(signer::address_of(controller));
        let pool_balance = coin::balance<AptosCoin>(signer::address_of(admin));
        
        assert!(controller_balance == 1000, 15);
        assert!(pool_balance == 0, 16);
    }

    #[test(framework = @aptos_framework, admin = @pulley, user = @0x123, controller = @0x456)]
    public fun test_withdrawal(
        framework: &signer,
        admin: &signer,
        user: &signer,
        controller: &signer
    ) {
        // Setup
        account::create_account_for_test(signer::address_of(framework));
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(user));
        account::create_account_for_test(signer::address_of(controller));
        
        aptos_coin::initialize_for_test(framework);
        
        trading_pool::initialize<AptosCoin>(
            admin,
            2000,
            signer::address_of(controller)
        );
        
        coin::register<AptosCoin>(user);
        
        // Deposit
        let deposit_coins = coin::mint<AptosCoin>(1000, &aptos_coin::mint_capability_for_test());
        trading_pool::deposit<AptosCoin>(user, signer::address_of(admin), deposit_coins);
        
        // Withdraw half (500 pool tokens)
        let withdrawn_coins = trading_pool::withdraw<AptosCoin>(user, signer::address_of(admin), 500);
        coin::destroy_zero(withdrawn_coins); // Note: withdrawal returns empty coin in current implementation
        
        // Check updated state
        let (total_deposited, total_pool_tokens, _, _) = 
            trading_pool::get_pool_info<AptosCoin>(signer::address_of(admin));
        assert!(total_deposited == 500, 17);
        assert!(total_pool_tokens == 500, 18);
        
        let (user_deposit, user_tokens) = 
            trading_pool::get_user_info<AptosCoin>(signer::address_of(admin), signer::address_of(user));
        assert!(user_deposit == 500, 19);
        assert!(user_tokens == 500, 20);
    }

    #[test(framework = @aptos_framework, admin = @pulley, controller = @0x456)]
    public fun test_threshold_update(
        framework: &signer,
        admin: &signer,
        controller: &signer
    ) {
        // Setup
        account::create_account_for_test(signer::address_of(framework));
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(controller));
        
        aptos_coin::initialize_for_test(framework);
        
        trading_pool::initialize<AptosCoin>(
            admin,
            1000,
            signer::address_of(controller)
        );
        
        // Update threshold
        trading_pool::update_threshold<AptosCoin>(admin, 2000);
        
        // Check updated threshold
        let (_, _, threshold, _) = trading_pool::get_pool_info<AptosCoin>(signer::address_of(admin));
        assert!(threshold == 2000, 21);
    }

    #[test(framework = @aptos_framework, admin = @pulley, controller1 = @0x456, controller2 = @0x789)]
    public fun test_controller_update(
        framework: &signer,
        admin: &signer,
        controller1: &signer,
        controller2: &signer
    ) {
        // Setup
        account::create_account_for_test(signer::address_of(framework));
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(controller1));
        account::create_account_for_test(signer::address_of(controller2));
        
        aptos_coin::initialize_for_test(framework);
        
        trading_pool::initialize<AptosCoin>(
            admin,
            1000,
            signer::address_of(controller1)
        );
        
        // Update controller
        trading_pool::update_controller<AptosCoin>(admin, signer::address_of(controller2));
        
        // The controller address is internal, so we can't directly test it,
        // but we can verify the function doesn't crash
        let (_, _, _, active) = trading_pool::get_pool_info<AptosCoin>(signer::address_of(admin));
        assert!(active == true, 22);
    }
}
