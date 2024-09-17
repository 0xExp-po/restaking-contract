module middleware::index_registry{
    use aptos_framework::event;
    use aptos_framework::object;
    use aptos_framework::timestamp;
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_std::smart_table::{Self, SmartTable};
    use aptos_std::smart_vector::{Self, SmartVector};
    
    use std::string::{Self, String};
    use std::bcs;
    use std::vector;
    use std::signer;

    use middleware::middleware_manager; 
    use middleware::registry_coordinator;

    friend middleware::registry_coordinator;

    const INDEX_REGISTRY_NAME: vector<u8> = b"INDEX_REGISTRY_NAME";
    const INDEX_REGISTRY_PREFIX: vector<u8> = b"INDEX_REGISTRY_PREFIX";


    const NOT_EXIST_ID: vector<u8> = b"NOT_EXIST_ID";

    const EQUORUM_NOT_EXIST: u64 = 1001;
    const EQUORUM_ALREADY_EXIST: u64 = 1002;

    struct OperatorUpdate has copy, store, drop {
        operator_id: String, 
        timestamp: u64
    }

    struct QuorumUpdate has copy, store, drop {
        operator_count: u32,
        timestamp: u64
    }
    // TODO: create store
    struct IndexRegistryStore has key {
        operator_index: SmartTable<u8, SmartTable<String, u32>>,
        update_history: SmartTable<u8, SmartTable<u32, vector<OperatorUpdate>>>,
        count_history: SmartTable<u8, vector<QuorumUpdate>>
    }

    struct IndexRegistryConfigs has key {
        signer_cap: SignerCapability,
    }

    #[event]
    struct QuorumIndexUpdate has drop, store {
        operator_id: String,
        quorum_number: u8,
        operator_index: u32
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

    fun ensure_index_regsitry_store() acquires IndexRegistryConfigs{
        if(!exists<IndexRegistryStore>(index_registry_address())){
            create_index_registry_store();
        }
    }

    public fun create_index_registry_store() acquires IndexRegistryConfigs{
        let index_registry_signer = index_registry_signer();
        move_to(index_registry_signer, IndexRegistryStore{
            operator_index: smart_table::new(),
            update_history: smart_table::new(),
            count_history: smart_table::new()
        })
    }

    public(friend) fun register_operator(operator_id: String, quorum: vector<u8>): vector<u32> acquires IndexRegistryStore{
        let operators_per_quorum: vector<u32> = vector::empty();

        vector::for_each(quorum, |quorum_number| {
            assert!(smart_table::contains(&index_registry_store().count_history, quorum_number), EQUORUM_NOT_EXIST);
            let count_history = smart_table::borrow(&index_registry_store().count_history, quorum_number);

            let new_operator_count = increase_operator_count(quorum_number);
            assign_operator_to_index(operator_id, quorum_number, new_operator_count - 1);
            vector::push_back(&mut operators_per_quorum, new_operator_count);
        });
        return operators_per_quorum
    }

    public(friend) fun deregister_operator(operator_id: String, quorum: vector<u8>) acquires IndexRegistryStore{
        vector::for_each(quorum, |quorum_number| {
            assert!(smart_table::contains(&index_registry_store().count_history, quorum_number), EQUORUM_NOT_EXIST);
            let count_history = smart_table::borrow(&index_registry_store().count_history, quorum_number);

            let index_to_remove = get_operator_index(quorum_number, operator_id);
            let new_operator_count = decrease_operator_count(quorum_number);
            let last_operator_id = pop_last_operator(quorum_number, new_operator_count);
            if (operator_id != last_operator_id) {
                assign_operator_to_index(last_operator_id, quorum_number, index_to_remove);
            }
        });
    }

    public(friend) fun initialize_quorum(quorum_number: u8) acquires IndexRegistryStore, IndexRegistryConfigs{
        ensure_index_regsitry_store();
        let store = index_registry_store_mut();
        assert!(!smart_table::contains(&store.count_history, quorum_number), EQUORUM_ALREADY_EXIST);
        let count_history: vector<QuorumUpdate> = vector::empty();
        let now = timestamp::now_seconds();
        vector::push_back(&mut count_history, QuorumUpdate{
            operator_count: 0,
            timestamp: now
        });
        smart_table::add(&mut store.count_history, quorum_number, count_history);
        smart_table::add(&mut store.operator_index, quorum_number, smart_table::new());
        smart_table::add(&mut store.update_history, quorum_number, smart_table::new());
    }

    fun assign_operator_to_index(operator_id: String, quorum_number: u8, index: u32) acquires IndexRegistryStore {
        update_operator_history(quorum_number, index, operator_id);
        set_operator_index(quorum_number, operator_id, index);

        event::emit(QuorumIndexUpdate{
            operator_id,
            quorum_number,
            operator_index: index
        });
    }

    fun pop_last_operator(quorum_number: u8, index: u32): String acquires IndexRegistryStore {
        let latest_update = latest_operator_update_mut(quorum_number, index);
        let remove_operator_id = latest_update.operator_id;
        update_operator_history(quorum_number, index, string::utf8(NOT_EXIST_ID));

        return remove_operator_id
    }
    fun increase_operator_count(quorum_number: u8): u32 acquires IndexRegistryStore {
        let latest_update = latest_quorum_update_mut(quorum_number);
        let new_operator_count = latest_update.operator_count + 1;

        update_count_history(quorum_number, new_operator_count);
        return new_operator_count
    }

    fun decrease_operator_count(quorum_number: u8): u32 acquires IndexRegistryStore {
        let latest_update = latest_quorum_update_mut(quorum_number);
        let new_operator_count = latest_update.operator_count -1;
       
        update_count_history(quorum_number, new_operator_count);
        return new_operator_count
    }

    fun update_operator_history(quorum_number: u8, operator_count: u32, new_operator_id: String) acquires IndexRegistryStore {
        let empty = operator_update_empty(quorum_number, operator_count);
        let now = timestamp::now_seconds();
        
        if (empty){
            let operator_update = vector::singleton(OperatorUpdate{
                operator_id: new_operator_id,
                timestamp: now
            });
            let store_mut = index_registry_store_mut();
            let operator_history_table = smart_table::borrow_mut(&mut store_mut.update_history, quorum_number);
            smart_table::add(operator_history_table, operator_count, operator_update);
            return
        };
        let latest_update = latest_operator_update_mut(quorum_number, operator_count);
        if (latest_update.timestamp == now) {
            latest_update.operator_id = new_operator_id;
        } else {
            let operator_history = operator_history_mut(quorum_number, operator_count);
            vector::push_back(operator_history, OperatorUpdate{
                operator_id: new_operator_id,
                timestamp: now
            });
        }
    }

    fun update_count_history(quorum_number: u8, new_operator_count: u32) acquires IndexRegistryStore {
        let latest_update = latest_quorum_update_mut(quorum_number);
        let now = timestamp::now_seconds();
        if (latest_update.timestamp == now) {
            latest_update.operator_count = new_operator_count;
        } else {
            let store = index_registry_store_mut();
            let count_history = smart_table::borrow_mut(&mut store.count_history, quorum_number);
            vector::push_back(count_history, QuorumUpdate{
                operator_count: new_operator_count,
                timestamp: now
            });
        }
    } 

    #[view]
    public fun count_history(quorum_number: u8): vector<QuorumUpdate> acquires IndexRegistryStore {
        *smart_table::borrow(&index_registry_store().count_history, quorum_number)
    }

    inline fun operator_update_empty(quorum_number: u8, operator_count: u32): bool acquires IndexRegistryStore {
        let store = index_registry_store();
        let operator_history_table = smart_table::borrow(&store.update_history, quorum_number);
        let is_empty = !smart_table::contains(operator_history_table, operator_count);
        is_empty
    }
    inline fun latest_operator_update_mut(quorum_number: u8, operator_count: u32): &mut OperatorUpdate acquires IndexRegistryStore{
        let store = index_registry_store();
        let operator_history_length = vector::length(smart_table::borrow(smart_table::borrow(&store.update_history, quorum_number), operator_count));
        let operator_history_mut = operator_history_mut(quorum_number, operator_count);
        let latest_update = vector::borrow_mut(operator_history_mut, operator_history_length - 1);
        latest_update
    }

    inline fun latest_quorum_update_mut(quorum_number: u8): &mut QuorumUpdate acquires IndexRegistryStore{
        let store = index_registry_store();
        let count_history_length = vector::length(smart_table::borrow(&store.count_history, quorum_number));
        let store_mut = index_registry_store_mut();
        let count_history_mut = smart_table::borrow_mut(&mut store_mut.count_history, quorum_number);
        let latest_update = vector::borrow_mut(count_history_mut, count_history_length - 1);
        latest_update
    }

    inline fun operator_history_mut(quorum_number: u8, operator_count: u32): &mut vector<OperatorUpdate> acquires IndexRegistryStore {
        let store_mut = index_registry_store_mut();
        // let update_history = smart_table::borrow_mut(&mut store_mut.update_history, quorum_number);
        let operator_history = smart_table::borrow_mut(smart_table::borrow_mut(&mut store_mut.update_history, quorum_number), operator_count);
        operator_history

    }

    inline fun operator_history(quorum_number: u8, operator_count: u32): &vector<OperatorUpdate> acquires IndexRegistryStore {
        let store = index_registry_store();
        let operator_history = smart_table::borrow(smart_table::borrow(&store.update_history, quorum_number), operator_count);
        operator_history
    }

    inline fun set_operator_index(quorum_number: u8, operator_id: String, index: u32) acquires IndexRegistryStore {
        let store = index_registry_store_mut();
        let operator_index = smart_table::borrow_mut(&mut store.operator_index, quorum_number);
        smart_table::upsert(operator_index, operator_id, index);
    }  

    inline fun get_operator_index(quorum_number: u8, operator_id: String): u32 acquires IndexRegistryStore {
        let operator_index = smart_table::borrow(&index_registry_store().operator_index, quorum_number);
        let index = *smart_table::borrow(operator_index, operator_id);
        index
    }

    inline fun index_registry_store(): &IndexRegistryStore  acquires IndexRegistryStore {
        borrow_global<IndexRegistryStore>(index_registry_address())
    }

    inline fun index_registry_store_mut(): &mut IndexRegistryStore  acquires IndexRegistryStore {
        borrow_global_mut<IndexRegistryStore>(index_registry_address())
    }

    inline fun index_registry_signer(): &signer acquires IndexRegistryConfigs{
        &account::create_signer_with_capability(&borrow_global<IndexRegistryConfigs>(index_registry_address()).signer_cap)
    }

    #[test_only]
    friend middleware::index_registry_tests;
}