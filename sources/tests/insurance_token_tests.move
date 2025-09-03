#[test_only]
module pulley::insurance_token_tests {
    use std::signer;
    use std::string;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use pulley::insurance_token;

    #[test(admin = @pulley)]
    public fun test_init_module(admin: &signer) {
        account::create_account_for_test(signer::address_of(admin));
        insurance_token::init_module_for_test(admin);
        
        // Test that metadata is created correctly
        let metadata = insurance_token::get_metadata();
        let name = insurance_token::get_name();
        assert!(name == string::utf8(b"PULLEY Insurance Token"), 1);
    }

    #[test(admin = @pulley, user = @0x123)]
    public fun test_external_minting(admin: &signer, user: &signer) {
        // Setup
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(user));
        insurance_token::init_module_for_test(admin);
        
        let admin_addr = signer::address_of(admin);
        let user_addr = signer::address_of(user);
        
        // Test external minting
        insurance_token::mint_external(user, admin_addr, 1000);
        
        // Check supply tracking
        let (insurance_supply, external_supply, _, _, _) = insurance_token::get_insurance_info(admin_addr);
        assert!(insurance_supply == 0, 2);
        assert!(external_supply == 1000, 3);
        assert!(insurance_token::get_total_supply(admin_addr) == 1000, 4);
    }

    #[test(admin = @pulley, controller = @0x456)]
    public fun test_insurance_minting(admin: &signer, controller: &signer) {
        // Setup
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(controller));
        insurance_token::init_module_for_test(admin);
        
        let admin_addr = signer::address_of(admin);
        let controller_addr = signer::address_of(controller);
        
        // Authorize controller
        insurance_token::authorize_controller(admin, controller_addr);
        
        // Test insurance minting
        insurance_token::mint_insurance(controller, admin_addr, 500);
        
        // Check supply tracking
        let (insurance_supply, external_supply, _, _, _) = insurance_token::get_insurance_info(admin_addr);
        assert!(insurance_supply == 500, 5);
        assert!(external_supply == 0, 6);
        assert!(insurance_token::get_total_supply(admin_addr) == 500, 7);
    }

    #[test(admin = @pulley, controller = @0x456)]
    public fun test_loss_absorption(admin: &signer, controller: &signer) {
        // Setup
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(controller));
        insurance_token::init_module_for_test(admin);
        
        let admin_addr = signer::address_of(admin);
        let controller_addr = signer::address_of(controller);
        
        // Authorize controller and mint insurance tokens
        insurance_token::authorize_controller(admin, controller_addr);
        insurance_token::mint_insurance(controller, admin_addr, 1000);
        
        // Test loss absorption
        let remaining_loss = insurance_token::absorb_loss(controller, admin_addr, 300);
        assert!(remaining_loss == 0, 8); // Should fully absorb
        
        // Check updated supply
        let (insurance_supply, _, absorbed_losses, _, _) = insurance_token::get_insurance_info(admin_addr);
        assert!(insurance_supply == 700, 9); // 1000 - 300
        assert!(absorbed_losses == 300, 10);
    }

    #[test(admin = @pulley, controller = @0x456)]
    public fun test_profit_deposit(admin: &signer, controller: &signer) {
        // Setup
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(controller));
        insurance_token::init_module_for_test(admin);
        
        let admin_addr = signer::address_of(admin);
        let controller_addr = signer::address_of(controller);
        
        // Authorize controller
        insurance_token::authorize_controller(admin, controller_addr);
        
        // Test profit deposit
        insurance_token::deposit_profit(controller, admin_addr, 200);
        
        // Check updated supply
        let (insurance_supply, _, _, profit_collected, _) = insurance_token::get_insurance_info(admin_addr);
        assert!(insurance_supply == 200, 11);
        assert!(profit_collected == 200, 12);
    }

    #[test(admin = @pulley, controller = @0x456)]
    public fun test_market_utilization_update(admin: &signer, controller: &signer) {
        // Setup
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(controller));
        insurance_token::init_module_for_test(admin);
        
        let admin_addr = signer::address_of(admin);
        let controller_addr = signer::address_of(controller);
        
        // Authorize controller
        insurance_token::authorize_controller(admin, controller_addr);
        
        // Test market utilization update
        insurance_token::update_market_utilization(controller, admin_addr, 7500); // 75%
        
        // Check utilization
        let (_, _, _, _, utilization) = insurance_token::get_insurance_info(admin_addr);
        assert!(utilization == 7500, 13);
    }

    #[test(admin = @pulley, unauthorized = @0x789)]
    #[expected_failure(abort_code = 1)] // E_NOT_AUTHORIZED
    public fun test_unauthorized_insurance_minting(admin: &signer, unauthorized: &signer) {
        // Setup
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(unauthorized));
        insurance_token::init_module_for_test(admin);
        
        let admin_addr = signer::address_of(admin);
        
        // Try to mint without authorization - should fail
        insurance_token::mint_insurance(unauthorized, admin_addr, 500);
    }
}
