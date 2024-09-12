module middleware::index_registry{
    use aptos_framework::timestamp;
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_std::smart_table::{Self, SmartTable};
    use aptos_std::smart_vector::{Self, SmartVector};
    
    use std::string::{Self, String};
    use std::vector;
    use std::signer;

    use middleware::middleware_manager; 
    use middleware::registry_coordinator;

    friend middleware::registry_coordinator;

    const INDEX_REGISTRY_NAME: vector<u8> = b"INDEX_REGISTRY_NAME";

    const NOT_EXIST_ID: u64 = 0;

    const EQUORUM_NOT_EXIST: u64 = 1001;

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
        let operator_signer = &middleware_manager::get_signer();
        let (index_registry_signer, signer_cap) = account::create_resource_account(operator_signer, INDEX_REGISTRY_NAME);
        middleware_manager::add_address(string::utf8(INDEX_REGISTRY_NAME), signer::address_of(&index_registry_signer));
        move_to(&index_registry_signer, IndexRegistryConfigs {
            signer_cap,
        });
    }

    #[view]
    public fun is_initialized(): bool{
        middleware_manager::address_exists(string::utf8(INDEX_REGISTRY_NAME))
    }

    #[view]
    /// Return the address of the resource account that stores pool manager configs.
    public fun index_registry_address(): address {
      middleware_manager::get_address(string::utf8(INDEX_REGISTRY_NAME))
    }

    public(friend) fun register_operator(operator_id: String, quorum: vector<u8>): vector<u32> acquires IndexRegistryStore{
        let operators_per_quorum: vector<u32> = vector::empty();

        vector::for_each(quorum, |quorum_number| {
            let operator_count = count_operator(operator_id, quorum_number);
            vector::push_back(&mut operators_per_quorum, operator_count);
        });
        return operators_per_quorum
    }

    fun count_operator(operator_id: String, quorum_number: u8): u32 acquires IndexRegistryStore{
        let count_history = smart_table::borrow(&index_registry_store().count_history, quorum_number);
        let count_history_length = smart_vector::length(count_history);
        assert!(count_history_length > 0, EQUORUM_NOT_EXIST);

        // TODO
        increase_operator_count(quorum_number);
        return 0
    }

    fun increase_operator_count(quorum_number: u8): u32 {
        let last_update = latest_quorum_update(quorum_number);
        let new_operator_count = last_update.operators_count + 1;

        update_count_history(quorum_number, last_update, new_operator_count);
        return new_operator_count
    }

    fun decrease_operator_count(quorum_number: u8): u32 {
        let last_update = latest_quorum_update(quorum_number);
        let new_operator_count = last_update.operators_count -1;
       
        update_count_history(quorum_number, last_update, new_operator_count);
        return new_operator_count
    }

    fun update_count_history(quorum_number: u8, last_update: &QuorumUpdate, new_operator_count: u32) {
        let now = timestamp::now_seconds();
        if (last_update.timestamp == now) {
            
        }
    } 

    inline fun latest_quorum_update(quorum_number: u8): &QuorumUpdate acquires IndexRegistryStore{
        let count_history = smart_table::borrow(&index_registry_store().count_history, quorum_number);
        let latest_update = smart_vector::borrow(count_history, smart_vector::length(count_history) - 1);
        latest_update
    }

    inline fun index_registry_store(): &IndexRegistryStore  acquires IndexRegistryStore {
        borrow_global<IndexRegistryStore>(index_registry_address())
    }

}