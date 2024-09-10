module restaking::index_registry{
    use aptos_framework::timestamp;
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_std::smart_table::{Self, SmartTable};
    use aptos_std::smart_vector::{Self, SmartVector};
    
    use std::string::{Self, String};
    use std::vector;
    use std::signer;

    use restaking::package_manager; 
    use restaking::registry_coordinator;

    const INDEX_REGISTRY_NAME: vector<u8> = b"INDEX_REGISTRY_NAME";

    const NOT_EXIST_ID: u64 = 0;

    struct OperatorUpdate has store, drop {
        operator_id: String, 
        timestamp: u64
    }

    struct QuorumUpdate has store, drop {
        operators_count: u32,
        timestamp: u64
    }
    struct IndexRegistryStore has key {
        operator_index: SmartTable<u8, SmartTable<String, u32>>,
        update_history: SmartTable<u8, SmartTable<u32, SmartVector<OperatorUpdate>>>,
        count_history: SmartTable<u8, SmartVector<QuorumUpdate>>
    }

    struct IndexRegistryConfigs has key {
        signer_cap: SignerCapability,
    }
    public entry fun initialize() {
        if (is_initialized()) {
            return
        };

        // derive a resource account from signer to manage User share Account
        let staking_signer = &package_manager::get_signer();
        let (index_registry_signer, signer_cap) = account::create_resource_account(staking_signer, INDEX_REGISTRY_NAME);
        package_manager::add_address(string::utf8(INDEX_REGISTRY_NAME), signer::address_of(&index_registry_signer));
        move_to(&index_registry_signer, IndexRegistryConfigs {
            signer_cap,
        });
    }

    #[view]
    public fun is_initialized(): bool{
        package_manager::address_exists(string::utf8(INDEX_REGISTRY_NAME))
    }

    
}