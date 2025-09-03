#[test_only]
module pulley::integration_test {
    use std::signer;
    use std::string;
    use std::vector;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptos_framework::aptos_coin::{AptosCoin};
    use pulley::insurance_token::{Self, InsuranceToken};
    use pulley::trading_pool::{Self, PoolToken};
    use pulley::controller;
    use pulley::yield_vault;

    #[test(aptos_framework = @0x1, admin = @0x123, user1 = @0x456, user2 = @0x789)]
    public fun test_full_system_flow(
        aptos_framework: &signer,
        admin: &signer,
        user1: &signer,
        user2: &signer,
    ) {
        // Setup framework
        timestamp::set_time_has_started_for_testing(aptos_framework);
        let (burn_cap, mint_cap) = aptos_framework::aptos_coin::initialize_for_test(aptos_framework);
        
        let admin_addr = signer::address_of(admin);
        let user1_addr = signer::address_of(user1);
        let user2_addr = signer::address_of(user2);
        
        // Create accounts
        account::create_account_for_test(admin_addr);
        account::create_account_for_test(user1_addr);
        account::create_account_for_test(user2_addr);
        
        // Setup vault addresses
        let vault1_addr = @0xabc;
        let vault2_addr = @0xdef;
        let vault3_addr = @0x111;
        account::create_account_for_test(vault1_addr);
        account::create_account_for_test(vault2_addr);
        account::create_account_for_test(vault3_addr);
        
        // Initialize insurance token
        insurance_token::init_module_for_test(admin);
        
        // Initialize trading pool with 1000 APT threshold
        let threshold = 1000 * 100000000; // 1000 APT in octas
        trading_pool::init_module_for_test<AptosCoin>(admin, threshold, admin_addr);
        
        // Initialize controller
        let vault_addresses = vector::empty<address>();
        vector::push_back(&mut vault_addresses, vault1_addr);
        vector::push_back(&mut vault_addresses, vault2_addr);
        vector::push_back(&mut vault_addresses, vault3_addr);
        controller::init_module_for_test<AptosCoin>(admin, admin_addr, admin_addr, vault_addresses);
        
        // Initialize vaults
        let vault1_signer = account::create_signer_with_capability(&account::create_test_signer_cap(vault1_addr));
        let vault2_signer = account::create_signer_with_capability(&account::create_test_signer_cap(vault2_addr));
        let vault3_signer = account::create_signer_with_capability(&account::create_test_signer_cap(vault3_addr));
        
        yield_vault::init_module_for_test<AptosCoin>(
            &vault1_signer,
            admin_addr,
            1, // STRATEGY_LENDING
            string::utf8(b"Lending Strategy"),
            200 // 2% performance fee
        );
        
        yield_vault::init_module_for_test<AptosCoin>(
            &vault2_signer,
            admin_addr,
            2, // STRATEGY_LIQUIDITY_MINING
            string::utf8(b"Liquidity Mining Strategy"),
            300 // 3% performance fee
        );
        
        yield_vault::init_module_for_test<AptosCoin>(
            &vault3_signer,
            admin_addr,
            3, // STRATEGY_STAKING
            string::utf8(b"Staking Strategy"),
            250 // 2.5% performance fee
        );
        
        // Mint some APT to users
        let user1_coins = coin::mint<AptosCoin>(2000 * 100000000, &mint_cap); // 2000 APT
        let user2_coins = coin::mint<AptosCoin>(1500 * 100000000, &mint_cap); // 1500 APT
        coin::deposit(user1_addr, user1_coins);
        coin::deposit(user2_addr, user2_coins);
        
        // Test 1: User deposits into trading pool
        let deposit_amount = 800 * 100000000; // 800 APT
        let deposit_coins = coin::withdraw<AptosCoin>(user1, deposit_amount);
        trading_pool::deposit<AptosCoin>(user1, admin_addr, deposit_coins);
        
        // Verify pool state
        let (total_deposited, total_pool_tokens, threshold_amt, is_active) = 
            trading_pool::get_pool_info<AptosCoin>(admin_addr);
        assert!(total_deposited == deposit_amount, 1);
        assert!(total_pool_tokens == deposit_amount, 2);
        assert!(is_active, 3);
        
        // Test 2: Second user deposit triggers threshold
        let deposit_amount2 = 500 * 100000000; // 500 APT
        let deposit_coins2 = coin::withdraw<AptosCoin>(user2, deposit_amount2);
        trading_pool::deposit<AptosCoin>(user2, admin_addr, deposit_coins2);
        
        // Verify funds were transferred to controller and allocated
        let (total_managed, total_profits, total_losses, controller_active) = 
            controller::get_controller_info<AptosCoin>(admin_addr);
        assert!(total_managed > 0, 4);
        assert!(controller_active, 5);
        
        // Test 3: Mint insurance tokens directly
        insurance_token::mint_insurance(user1, admin_addr, 100 * 100000000);
        let (insurance_supply, absorbed_losses, profit_collected) = 
            insurance_token::get_insurance_info(admin_addr);
        assert!(insurance_supply > 0, 6);
        
        // Test 4: Simulate vault harvest (profit)
        // First, we need to add some time and simulate yield
        timestamp::fast_forward_seconds(86400); // 1 day
        
        // Manually add some coins to vault to simulate yield
        let vault1_yield = coin::mint<AptosCoin>(50 * 100000000, &mint_cap); // 50 APT yield
        coin::deposit(vault1_addr, vault1_yield);
        
        // Harvest yield
        yield_vault::harvest<AptosCoin>(admin, vault1_addr);
        
        // Test 5: Simulate vault loss
        yield_vault::report_loss<AptosCoin>(&vault1_signer, vault1_addr, 20 * 100000000); // 20 APT loss
        
        // Test 6: Verify insurance absorbed some loss
        let (new_insurance_supply, new_absorbed_losses, new_profit_collected) = 
            insurance_token::get_insurance_info(admin_addr);
        assert!(new_absorbed_losses > absorbed_losses, 7);
        
        // Test 7: User withdrawal
        let user1_pool_balance = coin::balance<PoolToken>(user1_addr);
        let withdrawal_amount = user1_pool_balance / 2; // Withdraw half
        let withdrawn_coins = trading_pool::withdraw<AptosCoin>(user1, admin_addr, withdrawal_amount);
        assert!(coin::value(&withdrawn_coins) > 0, 8);
        coin::deposit(user1_addr, withdrawn_coins);
        
        // Cleanup
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(aptos_framework = @0x1, admin = @0x123, user = @0x456)]
    public fun test_insurance_token_operations(
        aptos_framework: &signer,
        admin: &signer,
        user: &signer,
    ) {
        // Setup
        timestamp::set_time_has_started_for_testing(aptos_framework);
        let admin_addr = signer::address_of(admin);
        let user_addr = signer::address_of(user);
        
        account::create_account_for_test(admin_addr);
        account::create_account_for_test(user_addr);
        
        // Initialize insurance token
        insurance_token::init_module_for_test(admin);
        
        // Test minting
        insurance_token::mint_insurance(user, admin_addr, 1000 * 100000000);
        let insurance_balance = coin::balance<InsuranceToken>(user_addr);
        assert!(insurance_balance == 1000 * 100000000, 1);
        
        // Test authorization
        insurance_token::authorize_controller(admin, user_addr);
        assert!(insurance_token::is_controller_authorized(admin_addr, user_addr), 2);
        
        // Test loss absorption
        let remaining_loss = insurance_token::absorb_loss(user, admin_addr, 300 * 100000000);
        assert!(remaining_loss == 0, 3); // Should absorb full loss
        
        let (supply_after_loss, absorbed_losses, _) = insurance_token::get_insurance_info(admin_addr);
        assert!(absorbed_losses == 300 * 100000000, 4);
        assert!(supply_after_loss == 700 * 100000000, 5); // 1000 - 300
    }

    #[test(aptos_framework = @0x1, admin = @0x123)]
    public fun test_vault_strategies(
        aptos_framework: &signer,
        admin: &signer,
    ) {
        // Setup
        timestamp::set_time_has_started_for_testing(aptos_framework);
        let (burn_cap, mint_cap) = aptos_framework::aptos_coin::initialize_for_test(aptos_framework);
        
        let admin_addr = signer::address_of(admin);
        account::create_account_for_test(admin_addr);
        
        // Initialize vault
        yield_vault::init_module_for_test<AptosCoin>(
            admin,
            admin_addr, // controller
            1, // STRATEGY_LENDING
            string::utf8(b"Test Lending Strategy"),
            500 // 5% performance fee
        );
        
        // Test vault info
        let (deposited, yield_earned, losses, strategy_type, active, paused) = 
            yield_vault::get_vault_info<AptosCoin>(admin_addr);
        assert!(deposited == 0, 1);
        assert!(strategy_type == 1, 2);
        assert!(active && !paused, 3);
        
        // Test strategy name
        let strategy_name = yield_vault::get_strategy_name<AptosCoin>(admin_addr);
        assert!(strategy_name == string::utf8(b"Test Lending Strategy"), 4);
        
        // Test pause functionality
        yield_vault::toggle_pause<AptosCoin>(admin, admin_addr);
        let (_, _, _, _, _, paused_after) = yield_vault::get_vault_info<AptosCoin>(admin_addr);
        assert!(paused_after, 5);
        
        // Test performance fee update
        yield_vault::update_performance_fee<AptosCoin>(admin, admin_addr, 1000); // 10%
        
        // Cleanup
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(aptos_framework = @0x1, admin = @0x123, controller = @0x456)]
    public fun test_controller_operations(
        aptos_framework: &signer,
        admin: &signer,
        controller: &signer,
    ) {
        // Setup
        timestamp::set_time_has_started_for_testing(aptos_framework);
        let admin_addr = signer::address_of(admin);
        let controller_addr = signer::address_of(controller);
        
        account::create_account_for_test(admin_addr);
        account::create_account_for_test(controller_addr);
        
        // Setup vault addresses
        let vault_addresses = vector::empty<address>();
        vector::push_back(&mut vault_addresses, @0x111);
        vector::push_back(&mut vault_addresses, @0x222);
        vector::push_back(&mut vault_addresses, @0x333);
        
        // Initialize controller
        controller::init_module_for_test<AptosCoin>(
            admin,
            controller_addr, // trading pool
            admin_addr, // insurance admin
            vault_addresses
        );
        
        // Test controller info
        let (managed_funds, profits, losses, active) = 
            controller::get_controller_info<AptosCoin>(admin_addr);
        assert!(managed_funds == 0, 1);
        assert!(active, 2);
        
        // Test vault addresses
        let retrieved_vaults = controller::get_vault_addresses<AptosCoin>(admin_addr);
        assert!(vector::length(&retrieved_vaults) == 3, 3);
        
        // Test vault balance (should be 0 initially)
        let vault_balance = controller::get_vault_balance<AptosCoin>(admin_addr, @0x111);
        assert!(vault_balance == 0, 4);
        
        // Test toggle active
        controller::toggle_active<AptosCoin>(admin);
        let (_, _, _, active_after) = controller::get_controller_info<AptosCoin>(admin_addr);
        assert!(!active_after, 5);
    }
}
