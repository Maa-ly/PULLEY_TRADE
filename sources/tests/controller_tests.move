#[test_only]
module pulley::controller_tests {
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use pulley::controller;
    use pulley::insurance_token;

    #[test(framework = @aptos_framework, admin = @pulley, pool = @0x123, insurance_admin = @0x456, trading_addr = @0x789)]
    public fun test_controller_initialization(
        framework: &signer,
        admin: &signer, 
        pool: &signer,
        insurance_admin: &signer,
        trading_addr: &signer
    ) {
        // Setup accounts
        account::create_account_for_test(signer::address_of(framework));
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(pool));
        account::create_account_for_test(signer::address_of(insurance_admin));
        account::create_account_for_test(signer::address_of(trading_addr));
        
        // Initialize AptosCoin
        aptos_coin::initialize_for_test(framework);
        
        // Initialize insurance token
        insurance_token::init_module_for_test(insurance_admin);
        
        // Initialize controller
        controller::initialize<AptosCoin>(
            admin,
            signer::address_of(pool),
            signer::address_of(insurance_admin),
            signer::address_of(trading_addr)
        );
        
        // Test controller info
        let (managed_funds, profits, losses, active, trading_address) = 
            controller::get_controller_info<AptosCoin>(signer::address_of(admin));
        assert!(managed_funds == 0, 1);
        assert!(profits == 0, 2);
        assert!(losses == 0, 3);
        assert!(active == true, 4);
        assert!(trading_address == signer::address_of(trading_addr), 5);
    }

    #[test(framework = @aptos_framework, admin = @pulley, pool = @0x123, insurance_admin = @0x456, trading_addr = @0x789)]
    public fun test_fund_allocation(
        framework: &signer,
        admin: &signer,
        pool: &signer,
        insurance_admin: &signer,
        trading_addr: &signer
    ) {
        // Setup
        account::create_account_for_test(signer::address_of(framework));
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(pool));
        account::create_account_for_test(signer::address_of(insurance_admin));
        account::create_account_for_test(signer::address_of(trading_addr));
        
        aptos_coin::initialize_for_test(framework);
        insurance_token::init_module_for_test(insurance_admin);
        
        // Authorize controller in insurance token
        insurance_token::authorize_controller(insurance_admin, signer::address_of(pool));
        
        controller::initialize<AptosCoin>(
            admin,
            signer::address_of(pool),
            signer::address_of(insurance_admin),
            signer::address_of(trading_addr)
        );
        
        // Mint test coins to pool
        let pool_addr = signer::address_of(pool);
        let insurance_addr = signer::address_of(insurance_admin);
        let trading_address = signer::address_of(trading_addr);
        
        coin::register<AptosCoin>(pool);
        coin::register<AptosCoin>(insurance_admin);
        coin::register<AptosCoin>(trading_addr);
        
        let test_coins = coin::mint<AptosCoin>(1000, &aptos_coin::mint_capability_for_test());
        coin::deposit(pool_addr, test_coins);
        
        // Test fund allocation
        let funds = coin::withdraw<AptosCoin>(pool, 1000);
        controller::allocate_funds<AptosCoin>(pool, signer::address_of(admin), funds);
        
        // Check allocations: 15% to insurance (150), 85% to trading (850)
        let insurance_balance = coin::balance<AptosCoin>(insurance_addr);
        let trading_balance = coin::balance<AptosCoin>(trading_address);
        
        assert!(insurance_balance == 150, 6);
        assert!(trading_balance == 850, 7);
        
        // Check controller stats
        let (managed_funds, _, _, _, _) = 
            controller::get_controller_info<AptosCoin>(signer::address_of(admin));
        assert!(managed_funds == 1000, 8);
    }

    #[test(framework = @aptos_framework, admin = @pulley, pool = @0x123, insurance_admin = @0x456, trading_addr = @0x789)]
    public fun test_profit_reporting(
        framework: &signer,
        admin: &signer,
        pool: &signer,
        insurance_admin: &signer,
        trading_addr: &signer
    ) {
        // Setup
        account::create_account_for_test(signer::address_of(framework));
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(pool));
        account::create_account_for_test(signer::address_of(insurance_admin));
        account::create_account_for_test(signer::address_of(trading_addr));
        
        aptos_coin::initialize_for_test(framework);
        insurance_token::init_module_for_test(insurance_admin);
        
        insurance_token::authorize_controller(insurance_admin, signer::address_of(admin));
        
        controller::initialize<AptosCoin>(
            admin,
            signer::address_of(pool),
            signer::address_of(insurance_admin),
            signer::address_of(trading_addr)
        );
        
        // Register coins
        coin::register<AptosCoin>(admin);
        coin::register<AptosCoin>(pool);
        coin::register<AptosCoin>(insurance_admin);
        
        // Test profit reporting
        let profit_coins = coin::mint<AptosCoin>(1000, &aptos_coin::mint_capability_for_test());
        controller::report_profit<AptosCoin>(admin, signer::address_of(admin), profit_coins);
        
        // Check profit distribution: 10% to insurance (100), 90% to pool (900)
        let insurance_balance = coin::balance<AptosCoin>(signer::address_of(insurance_admin));
        let pool_balance = coin::balance<AptosCoin>(signer::address_of(pool));
        
        assert!(insurance_balance == 100, 9);
        assert!(pool_balance == 900, 10);
        
        // Check controller stats
        let (_, profits, _, _, _) = 
            controller::get_controller_info<AptosCoin>(signer::address_of(admin));
        assert!(profits == 1000, 11);
    }

    #[test(framework = @aptos_framework, admin = @pulley, pool = @0x123, insurance_admin = @0x456, trading_addr = @0x789)]
    public fun test_loss_reporting(
        framework: &signer,
        admin: &signer,
        pool: &signer,
        insurance_admin: &signer,
        trading_addr: &signer
    ) {
        // Setup
        account::create_account_for_test(signer::address_of(framework));
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(pool));
        account::create_account_for_test(signer::address_of(insurance_admin));
        account::create_account_for_test(signer::address_of(trading_addr));
        
        aptos_coin::initialize_for_test(framework);
        insurance_token::init_module_for_test(insurance_admin);
        
        insurance_token::authorize_controller(insurance_admin, signer::address_of(admin));
        
        controller::initialize<AptosCoin>(
            admin,
            signer::address_of(pool),
            signer::address_of(insurance_admin),
            signer::address_of(trading_addr)
        );
        
        // Pre-mint some insurance tokens for loss absorption
        insurance_token::mint_insurance(admin, signer::address_of(insurance_admin), 500);
        
        // Test loss reporting
        controller::report_loss<AptosCoin>(admin, signer::address_of(admin), 300);
        
        // Check controller stats
        let (_, _, losses, _, _) = 
            controller::get_controller_info<AptosCoin>(signer::address_of(admin));
        assert!(losses == 300, 12);
        
        // Check that insurance absorbed the loss
        let (insurance_supply, _, absorbed_losses, _, _) = 
            insurance_token::get_insurance_info(signer::address_of(insurance_admin));
        assert!(insurance_supply == 200, 13); // 500 - 300
        assert!(absorbed_losses == 300, 14);
    }

    #[test(framework = @aptos_framework, admin = @pulley, pool = @0x123, insurance_admin = @0x456, trading_addr = @0x789)]
    public fun test_trading_address_update(
        framework: &signer,
        admin: &signer,
        pool: &signer,
        insurance_admin: &signer,
        trading_addr: &signer
    ) {
        // Setup
        account::create_account_for_test(signer::address_of(framework));
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(pool));
        account::create_account_for_test(signer::address_of(insurance_admin));
        account::create_account_for_test(signer::address_of(trading_addr));
        
        controller::initialize<AptosCoin>(
            admin,
            signer::address_of(pool),
            signer::address_of(insurance_admin),
            signer::address_of(trading_addr)
        );
        
        // Test trading address update
        let new_trading_addr = @0xABC;
        controller::update_trading_address<AptosCoin>(admin, signer::address_of(admin), new_trading_addr);
        
        let updated_trading_addr = controller::get_trading_address<AptosCoin>(signer::address_of(admin));
        assert!(updated_trading_addr == new_trading_addr, 15);
    }

    #[test(framework = @aptos_framework, admin = @pulley, pool = @0x123, insurance_admin = @0x456, trading_addr = @0x789)]
    public fun test_automation_functions(
        framework: &signer,
        admin: &signer,
        pool: &signer,
        insurance_admin: &signer,
        trading_addr: &signer
    ) {
        // Setup
        account::create_account_for_test(signer::address_of(framework));
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(pool));
        account::create_account_for_test(signer::address_of(insurance_admin));
        account::create_account_for_test(signer::address_of(trading_addr));
        
        aptos_coin::initialize_for_test(framework);
        
        controller::initialize<AptosCoin>(
            admin,
            signer::address_of(pool),
            signer::address_of(insurance_admin),
            signer::address_of(trading_addr)
        );
        
        // Test has_funds_to_allocate when no funds
        let has_funds = controller::has_funds_to_allocate<AptosCoin>(signer::address_of(admin));
        assert!(has_funds == false, 16);
        
        // Add some funds and test again
        coin::register<AptosCoin>(admin);
        let test_coins = coin::mint<AptosCoin>(500, &aptos_coin::mint_capability_for_test());
        coin::deposit(signer::address_of(admin), test_coins);
        
        let has_funds = controller::has_funds_to_allocate<AptosCoin>(signer::address_of(admin));
        assert!(has_funds == true, 17);
    }
}
