/// Permission Manager Contract
/// Manages access control and permissions for the Pulley protocol
/// Provides role-based access control for different components
module pulley::permission_manager {
    use std::signer;
    use std::string;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::timestamp;
    use aptos_std::table::{Self, Table};

    /// Error codes
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_ROLE_NOT_FOUND: u64 = 2;
    const E_PERMISSION_DENIED: u64 = 3;
    const E_INVALID_ROLE: u64 = 4;
    const E_ALREADY_HAS_ROLE: u64 = 5;
    const E_DOES_NOT_HAVE_ROLE: u64 = 6;
    const E_INVALID_PERMISSION: u64 = 7;
    const E_MANAGER_NOT_INITIALIZED: u64 = 8;

    /// Role types
    const ROLE_ADMIN: u64 = 1;
    const ROLE_TRADER: u64 = 2;
    const ROLE_AI_WALLET: u64 = 3;
    const ROLE_ORACLE: u64 = 4;
    const ROLE_AUTOMATION: u64 = 5;
    const ROLE_INSURANCE: u64 = 6;
    const ROLE_VIEWER: u64 = 7;

    /// Permission types
    const PERMISSION_DEPOSIT: u64 = 1;
    const PERMISSION_WITHDRAW: u64 = 2;
    const PERMISSION_TRADE: u64 = 3;
    const PERMISSION_MANAGE_POOL: u64 = 4;
    const PERMISSION_MANAGE_CONTROLLER: u64 = 5;
    const PERMISSION_MANAGE_AI_WALLET: u64 = 6;
    const PERMISSION_MANAGE_INSURANCE: u64 = 7;
    const PERMISSION_UPDATE_ORACLE: u64 = 8;
    const PERMISSION_AUTOMATE: u64 = 9;
    const PERMISSION_VIEW: u64 = 10;
    const PERMISSION_MANAGE_PERMISSIONS: u64 = 11;

    /// Role structure
    struct Role has store {
        role_id: u64,
        role_name: string::String,
        permissions: vector<u64>,
        is_active: bool,
        created_at: u64,
    }

    /// User role assignment
    struct UserRole has store {
        user_address: address,
        role_id: u64,
        assigned_at: u64,
        assigned_by: address,
        is_active: bool,
    }

    /// Permission manager state
    struct PermissionManager has key {
        admin_address: address,
        roles: Table<u64, Role>,
        user_roles: Table<address, vector<u64>>,
        role_permissions: Table<u64, vector<u64>>,
        permission_names: Table<u64, string::String>,
        
        // Events
        role_created_events: EventHandle<RoleCreatedEvent>,
        role_assigned_events: EventHandle<RoleAssignedEvent>,
        role_revoked_events: EventHandle<RoleRevokedEvent>,
        permission_granted_events: EventHandle<PermissionGrantedEvent>,
        permission_revoked_events: EventHandle<PermissionRevokedEvent>,
    }

    /// Events
    struct RoleCreatedEvent has drop, store {
        role_id: u64,
        role_name: string::String,
        permissions: vector<u64>,
        created_by: address,
        timestamp: u64,
    }

    struct RoleAssignedEvent has drop, store {
        user_address: address,
        role_id: u64,
        assigned_by: address,
        timestamp: u64,
    }

    struct RoleRevokedEvent has drop, store {
        user_address: address,
        role_id: u64,
        revoked_by: address,
        timestamp: u64,
    }

    struct PermissionGrantedEvent has drop, store {
        user_address: address,
        permission_id: u64,
        granted_by: address,
        timestamp: u64,
    }

    struct PermissionRevokedEvent has drop, store {
        user_address: address,
        permission_id: u64,
        revoked_by: address,
        timestamp: u64,
    }

    /// Initialize the permission manager
    public fun initialize(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        
        move_to(admin, PermissionManager {
            admin_address: admin_addr,
            roles: table::new(),
            user_roles: table::new(),
            role_permissions: table::new(),
            permission_names: table::new(),
            role_created_events: account::new_event_handle<RoleCreatedEvent>(admin),
            role_assigned_events: account::new_event_handle<RoleAssignedEvent>(admin),
            role_revoked_events: account::new_event_handle<RoleRevokedEvent>(admin),
            permission_granted_events: account::new_event_handle<PermissionGrantedEvent>(admin),
            permission_revoked_events: account::new_event_handle<PermissionRevokedEvent>(admin),
        });
        
        // Initialize default roles and permissions
        initialize_default_roles(admin_addr);
    }

    /// Initialize default roles and permissions
    fun initialize_default_roles(admin_addr: address) acquires PermissionManager {
        let manager = borrow_global_mut<PermissionManager>(@pulley);
        
        // Initialize permission names
        table::add(&mut manager.permission_names, PERMISSION_DEPOSIT, string::utf8(b"DEPOSIT"));
        table::add(&mut manager.permission_names, PERMISSION_WITHDRAW, string::utf8(b"WITHDRAW"));
        table::add(&mut manager.permission_names, PERMISSION_TRADE, string::utf8(b"TRADE"));
        table::add(&mut manager.permission_names, PERMISSION_MANAGE_POOL, string::utf8(b"MANAGE_POOL"));
        table::add(&mut manager.permission_names, PERMISSION_MANAGE_CONTROLLER, string::utf8(b"MANAGE_CONTROLLER"));
        table::add(&mut manager.permission_names, PERMISSION_MANAGE_AI_WALLET, string::utf8(b"MANAGE_AI_WALLET"));
        table::add(&mut manager.permission_names, PERMISSION_MANAGE_INSURANCE, string::utf8(b"MANAGE_INSURANCE"));
        table::add(&mut manager.permission_names, PERMISSION_UPDATE_ORACLE, string::utf8(b"UPDATE_ORACLE"));
        table::add(&mut manager.permission_names, PERMISSION_AUTOMATE, string::utf8(b"AUTOMATE"));
        table::add(&mut manager.permission_names, PERMISSION_VIEW, string::utf8(b"VIEW"));
        table::add(&mut manager.permission_names, PERMISSION_MANAGE_PERMISSIONS, string::utf8(b"MANAGE_PERMISSIONS"));
        
        // Create admin role
        let admin_permissions = vector::empty<u64>();
        vector::push_back(&mut admin_permissions, PERMISSION_DEPOSIT);
        vector::push_back(&mut admin_permissions, PERMISSION_WITHDRAW);
        vector::push_back(&mut admin_permissions, PERMISSION_TRADE);
        vector::push_back(&mut admin_permissions, PERMISSION_MANAGE_POOL);
        vector::push_back(&mut admin_permissions, PERMISSION_MANAGE_CONTROLLER);
        vector::push_back(&mut admin_permissions, PERMISSION_MANAGE_AI_WALLET);
        vector::push_back(&mut admin_permissions, PERMISSION_MANAGE_INSURANCE);
        vector::push_back(&mut admin_permissions, PERMISSION_UPDATE_ORACLE);
        vector::push_back(&mut admin_permissions, PERMISSION_AUTOMATE);
        vector::push_back(&mut admin_permissions, PERMISSION_VIEW);
        vector::push_back(&mut admin_permissions, PERMISSION_MANAGE_PERMISSIONS);
        
        create_role_internal(
            ROLE_ADMIN,
            string::utf8(b"ADMIN"),
            admin_permissions,
            admin_addr
        );
        
        // Create trader role
        let trader_permissions = vector::empty<u64>();
        vector::push_back(&mut trader_permissions, PERMISSION_DEPOSIT);
        vector::push_back(&mut trader_permissions, PERMISSION_WITHDRAW);
        vector::push_back(&mut trader_permissions, PERMISSION_TRADE);
        vector::push_back(&mut trader_permissions, PERMISSION_VIEW);
        
        create_role_internal(
            ROLE_TRADER,
            string::utf8(b"TRADER"),
            trader_permissions,
            admin_addr
        );
        
        // Create AI wallet role
        let ai_wallet_permissions = vector::empty<u64>();
        vector::push_back(&mut ai_wallet_permissions, PERMISSION_TRADE);
        vector::push_back(&mut ai_wallet_permissions, PERMISSION_VIEW);
        
        create_role_internal(
            ROLE_AI_WALLET,
            string::utf8(b"AI_WALLET"),
            ai_wallet_permissions,
            admin_addr
        );
        
        // Create oracle role
        let oracle_permissions = vector::empty<u64>();
        vector::push_back(&mut oracle_permissions, PERMISSION_UPDATE_ORACLE);
        vector::push_back(&mut oracle_permissions, PERMISSION_VIEW);
        
        create_role_internal(
            ROLE_ORACLE,
            string::utf8(b"ORACLE"),
            oracle_permissions,
            admin_addr
        );
        
        // Create automation role
        let automation_permissions = vector::empty<u64>();
        vector::push_back(&mut automation_permissions, PERMISSION_AUTOMATE);
        vector::push_back(&mut automation_permissions, PERMISSION_VIEW);
        
        create_role_internal(
            ROLE_AUTOMATION,
            string::utf8(b"AUTOMATION"),
            automation_permissions,
            admin_addr
        );
        
        // Create insurance role
        let insurance_permissions = vector::empty<u64>();
        vector::push_back(&mut insurance_permissions, PERMISSION_MANAGE_INSURANCE);
        vector::push_back(&mut insurance_permissions, PERMISSION_VIEW);
        
        create_role_internal(
            ROLE_INSURANCE,
            string::utf8(b"INSURANCE"),
            insurance_permissions,
            admin_addr
        );
        
        // Create viewer role
        let viewer_permissions = vector::empty<u64>();
        vector::push_back(&mut viewer_permissions, PERMISSION_VIEW);
        
        create_role_internal(
            ROLE_VIEWER,
            string::utf8(b"VIEWER"),
            viewer_permissions,
            admin_addr
        );
    }

    /// Create a new role
    public fun create_role(
        admin: &signer,
        role_id: u64,
        role_name: string::String,
        permissions: vector<u64>,
    ) acquires PermissionManager {
        let admin_addr = signer::address_of(admin);
        assert!(exists<PermissionManager>(@pulley), E_MANAGER_NOT_INITIALIZED);
        
        let manager = borrow_global<PermissionManager>(@pulley);
        assert!(admin_addr == manager.admin_address, E_NOT_AUTHORIZED);
        
        create_role_internal(role_id, role_name, permissions, admin_addr);
    }

    /// Internal function to create role
    fun create_role_internal(
        role_id: u64,
        role_name: string::String,
        permissions: vector<u64>,
        created_by: address,
    ) acquires PermissionManager {
        let manager = borrow_global_mut<PermissionManager>(@pulley);
        
        // Create role
        let role = Role {
            role_id,
            role_name,
            permissions: permissions,
            is_active: true,
            created_at: timestamp::now_microseconds(),
        };
        
        table::add(&mut manager.roles, role_id, role);
        table::add(&mut manager.role_permissions, role_id, permissions);
        
        // Emit event
        event::emit_event(&mut manager.role_created_events, RoleCreatedEvent {
            role_id,
            role_name,
            permissions,
            created_by,
            timestamp: timestamp::now_microseconds(),
        });
    }

    /// Assign role to user
    public fun assign_role(
        admin: &signer,
        user_address: address,
        role_id: u64,
    ) acquires PermissionManager {
        let admin_addr = signer::address_of(admin);
        assert!(exists<PermissionManager>(@pulley), E_MANAGER_NOT_INITIALIZED);
        
        let manager = borrow_global<PermissionManager>(@pulley);
        assert!(admin_addr == manager.admin_address, E_NOT_AUTHORIZED);
        assert!(table::contains(&manager.roles, role_id), E_ROLE_NOT_FOUND);
        
        // Check if user already has this role
        if (table::contains(&manager.user_roles, user_address)) {
            let user_roles = table::borrow(&manager.user_roles, user_address);
            let i = 0;
            while (i < vector::length(user_roles)) {
                assert!(*vector::borrow(user_roles, i) != role_id, E_ALREADY_HAS_ROLE);
                i = i + 1;
            };
        };
        
        // Add role to user
        if (!table::contains(&manager.user_roles, user_address)) {
            table::add(&mut manager.user_roles, user_address, vector::empty<u64>());
        };
        
        let user_roles = table::borrow_mut(&mut manager.user_roles, user_address);
        vector::push_back(user_roles, role_id);
        
        // Emit event
        event::emit_event(&mut manager.role_assigned_events, RoleAssignedEvent {
            user_address,
            role_id,
            assigned_by: admin_addr,
            timestamp: timestamp::now_microseconds(),
        });
    }

    /// Revoke role from user
    public fun revoke_role(
        admin: &signer,
        user_address: address,
        role_id: u64,
    ) acquires PermissionManager {
        let admin_addr = signer::address_of(admin);
        assert!(exists<PermissionManager>(@pulley), E_MANAGER_NOT_INITIALIZED);
        
        let manager = borrow_global<PermissionManager>(@pulley);
        assert!(admin_addr == manager.admin_address, E_NOT_AUTHORIZED);
        assert!(table::contains(&manager.user_roles, user_address), E_DOES_NOT_HAVE_ROLE);
        
        let user_roles = table::borrow_mut(&mut manager.user_roles, user_address);
        let i = 0;
        let found = false;
        while (i < vector::length(user_roles)) {
            if (*vector::borrow(user_roles, i) == role_id) {
                vector::remove(user_roles, i);
                found = true;
                break
            };
            i = i + 1;
        };
        assert!(found, E_DOES_NOT_HAVE_ROLE);
        
        // Emit event
        event::emit_event(&mut manager.role_revoked_events, RoleRevokedEvent {
            user_address,
            role_id,
            revoked_by: admin_addr,
            timestamp: timestamp::now_microseconds(),
        });
    }

    /// Check if user has permission
    public fun has_permission(user_address: address, permission_id: u64): bool acquires PermissionManager {
        if (!exists<PermissionManager>(@pulley)) {
            return false
        };
        
        let manager = borrow_global<PermissionManager>(@pulley);
        if (!table::contains(&manager.user_roles, user_address)) {
            return false
        };
        
        let user_roles = table::borrow(&manager.user_roles, user_address);
        let i = 0;
        while (i < vector::length(user_roles)) {
            let role_id = *vector::borrow(user_roles, i);
            if (table::contains(&manager.role_permissions, role_id)) {
                let role_permissions = table::borrow(&manager.role_permissions, role_id);
                let j = 0;
                while (j < vector::length(role_permissions)) {
                    if (*vector::borrow(role_permissions, j) == permission_id) {
                        return true
                    };
                    j = j + 1;
                };
            };
            i = i + 1;
        };
        
        false
    }

    /// Check if user has role
    public fun has_role(user_address: address, role_id: u64): bool acquires PermissionManager {
        if (!exists<PermissionManager>(@pulley)) {
            return false
        };
        
        let manager = borrow_global<PermissionManager>(@pulley);
        if (!table::contains(&manager.user_roles, user_address)) {
            return false
        };
        
        let user_roles = table::borrow(&manager.user_roles, user_address);
        let i = 0;
        while (i < vector::length(user_roles)) {
            if (*vector::borrow(user_roles, i) == role_id) {
                return true
            };
            i = i + 1;
        };
        
        false
    }

    /// Get user roles
    public fun get_user_roles(user_address: address): vector<u64> acquires PermissionManager {
        if (!exists<PermissionManager>(@pulley)) {
            return vector::empty<u64>()
        };
        
        let manager = borrow_global<PermissionManager>(@pulley);
        if (!table::contains(&manager.user_roles, user_address)) {
            return vector::empty<u64>()
        };
        
        *table::borrow(&manager.user_roles, user_address)
    }

    /// Get role permissions
    public fun get_role_permissions(role_id: u64): vector<u64> acquires PermissionManager {
        if (!exists<PermissionManager>(@pulley)) {
            return vector::empty<u64>()
        };
        
        let manager = borrow_global<PermissionManager>(@pulley);
        if (!table::contains(&manager.role_permissions, role_id)) {
            return vector::empty<u64>()
        };
        
        *table::borrow(&manager.role_permissions, role_id)
    }

    /// Get role information
    public fun get_role_info(role_id: u64): (string::String, vector<u64>, bool) acquires PermissionManager {
        assert!(exists<PermissionManager>(@pulley), E_MANAGER_NOT_INITIALIZED);
        let manager = borrow_global<PermissionManager>(@pulley);
        assert!(table::contains(&manager.roles, role_id), E_ROLE_NOT_FOUND);
        
        let role = table::borrow(&manager.roles, role_id);
        (role.role_name, role.permissions, role.is_active)
    }

    /// Get permission name
    public fun get_permission_name(permission_id: u64): string::String acquires PermissionManager {
        assert!(exists<PermissionManager>(@pulley), E_MANAGER_NOT_INITIALIZED);
        let manager = borrow_global<PermissionManager>(@pulley);
        assert!(table::contains(&manager.permission_names, permission_id), E_INVALID_PERMISSION);
        
        *table::borrow(&manager.permission_names, permission_id)
    }

    /// Update role permissions
    public fun update_role_permissions(
        admin: &signer,
        role_id: u64,
        new_permissions: vector<u64>,
    ) acquires PermissionManager {
        let admin_addr = signer::address_of(admin);
        assert!(exists<PermissionManager>(@pulley), E_MANAGER_NOT_INITIALIZED);
        
        let manager = borrow_global<PermissionManager>(@pulley);
        assert!(admin_addr == manager.admin_address, E_NOT_AUTHORIZED);
        assert!(table::contains(&manager.roles, role_id), E_ROLE_NOT_FOUND);
        
        // Update role permissions
        let role = table::borrow_mut(&mut manager.roles, role_id);
        role.permissions = new_permissions;
        
        // Update role permissions table
        table::upsert(&mut manager.role_permissions, role_id, new_permissions);
    }

    /// Deactivate role
    public fun deactivate_role(
        admin: &signer,
        role_id: u64,
    ) acquires PermissionManager {
        let admin_addr = signer::address_of(admin);
        assert!(exists<PermissionManager>(@pulley), E_MANAGER_NOT_INITIALIZED);
        
        let manager = borrow_global<PermissionManager>(@pulley);
        assert!(admin_addr == manager.admin_address, E_NOT_AUTHORIZED);
        assert!(table::contains(&manager.roles, role_id), E_ROLE_NOT_FOUND);
        
        let role = table::borrow_mut(&mut manager.roles, role_id);
        role.is_active = false;
    }

    /// Activate role
    public fun activate_role(
        admin: &signer,
        role_id: u64,
    ) acquires PermissionManager {
        let admin_addr = signer::address_of(admin);
        assert!(exists<PermissionManager>(@pulley), E_MANAGER_NOT_INITIALIZED);
        
        let manager = borrow_global<PermissionManager>(@pulley);
        assert!(admin_addr == manager.admin_address, E_NOT_AUTHORIZED);
        assert!(table::contains(&manager.roles, role_id), E_ROLE_NOT_FOUND);
        
        let role = table::borrow_mut(&mut manager.roles, role_id);
        role.is_active = true;
    }

    /// Require permission (for use in other contracts)
    public fun require_permission(user_address: address, permission_id: u64) acquires PermissionManager {
        assert!(has_permission(user_address, permission_id), E_PERMISSION_DENIED);
    }

    /// Require role (for use in other contracts)
    public fun require_role(user_address: address, role_id: u64) acquires PermissionManager {
        assert!(has_role(user_address, role_id), E_PERMISSION_DENIED);
    }

    /// Get all roles
    public fun get_all_roles(): vector<u64> acquires PermissionManager {
        if (!exists<PermissionManager>(@pulley)) {
            return vector::empty<u64>()
        };
        
        // In production, this would return all role IDs
        // For now, return default roles
        let roles = vector::empty<u64>();
        vector::push_back(&mut roles, ROLE_ADMIN);
        vector::push_back(&mut roles, ROLE_TRADER);
        vector::push_back(&mut roles, ROLE_AI_WALLET);
        vector::push_back(&mut roles, ROLE_ORACLE);
        vector::push_back(&mut roles, ROLE_AUTOMATION);
        vector::push_back(&mut roles, ROLE_INSURANCE);
        vector::push_back(&mut roles, ROLE_VIEWER);
        roles
    }

    /// Get all permissions
    public fun get_all_permissions(): vector<u64> acquires PermissionManager {
        if (!exists<PermissionManager>(@pulley)) {
            return vector::empty<u64>()
        };
        
        // In production, this would return all permission IDs
        // For now, return default permissions
        let permissions = vector::empty<u64>();
        vector::push_back(&mut permissions, PERMISSION_DEPOSIT);
        vector::push_back(&mut permissions, PERMISSION_WITHDRAW);
        vector::push_back(&mut permissions, PERMISSION_TRADE);
        vector::push_back(&mut permissions, PERMISSION_MANAGE_POOL);
        vector::push_back(&mut permissions, PERMISSION_MANAGE_CONTROLLER);
        vector::push_back(&mut permissions, PERMISSION_MANAGE_AI_WALLET);
        vector::push_back(&mut permissions, PERMISSION_MANAGE_INSURANCE);
        vector::push_back(&mut permissions, PERMISSION_UPDATE_ORACLE);
        vector::push_back(&mut permissions, PERMISSION_AUTOMATE);
        vector::push_back(&mut permissions, PERMISSION_VIEW);
        vector::push_back(&mut permissions, PERMISSION_MANAGE_PERMISSIONS);
        permissions
    }

    /// Check if user is admin
    public fun is_admin(user_address: address): bool acquires PermissionManager {
        has_role(user_address, ROLE_ADMIN)
    }

    /// Check if user is trader
    public fun is_trader(user_address: address): bool acquires PermissionManager {
        has_role(user_address, ROLE_TRADER)
    }

    /// Check if user is AI wallet
    public fun is_ai_wallet(user_address: address): bool acquires PermissionManager {
        has_role(user_address, ROLE_AI_WALLET)
    }

    /// Check if user is oracle
    public fun is_oracle(user_address: address): bool acquires PermissionManager {
        has_role(user_address, ROLE_ORACLE)
    }

    /// Check if user is automation
    public fun is_automation(user_address: address): bool acquires PermissionManager {
        has_role(user_address, ROLE_AUTOMATION)
    }

    /// Check if user is insurance
    public fun is_insurance(user_address: address): bool acquires PermissionManager {
        has_role(user_address, ROLE_INSURANCE)
    }

    /// Check if user is viewer
    public fun is_viewer(user_address: address): bool acquires PermissionManager {
        has_role(user_address, ROLE_VIEWER)
    }

    #[test_only]
    public fun init_module_for_test(admin: &signer) {
        initialize(admin);
    }
}
