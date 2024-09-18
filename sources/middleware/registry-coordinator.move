module middleware::registry_coordinator{
    use aptos_framework::event;
    use aptos_framework::fungible_asset::{
    Self, Metadata,
    };
    use aptos_framework::object::{Self, Object};
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::timestamp;
    use aptos_framework::primary_fungible_store;

    use middleware::middleware_manager;

    use restaking::staker_manager;

    use middleware::service_manager;
    use middleware::bls_apk_registry;
    use middleware::stake_registry;
    use middleware::index_registry;

    use restaking::operator_manager;

    use restaking::math_utils;

    use aptos_std::smart_table::{Self, SmartTable};
    use aptos_std::smart_vector::{Self, SmartVector};
    use aptos_std::bn254_algebra::{G1, G2};
    
    use aptos_std::aptos_hash;
    use aptos_std::comparator;

    use std::string;
    use std::bcs;
    use std::vector;
    use std::signer;

    const REGISTRY_COORDINATOR_NAME: vector<u8> = b"REGISTRY_COORDINATOR_NAME";
    const REGISTRY_COORDINATOR_PREFIX: vector<u8> = b"REGISTRY_COORDINATOR_PREFIX";

    struct RegistryCoordinatorConfigs has key {
        signer_cap: SignerCapability,
    }
    struct RegistryCoordinatorStore has key {
        quorum_count: u8,
        quorum_params: SmartTable<u8, OperatorSetParam>,
        operator_infos: SmartTable<address, OperatorInfo>,
        operator_bitmap: SmartTable<vector<u8>, u256>,
        operator_bitmap_history: SmartTable<vector<u8>, vector<QuorumBitmapUpdate>>,
    }

    struct PubkeyRegistrationParams has copy, drop, store {
        pubkey_registration_signature: vector<u8>,
        pubkeyG1: vector<u8>,
        pubkeyG2: vector<u8>,
    }

    struct OperatorInfo has copy, drop, store {
        operator_id: vector<u8>,
        operator_status: u8, // 0: NEVER_REGISTERED, 1: REGISTERED, 2: DEREGISTERED
    }

    struct QuorumBitmapUpdate has copy, drop, store {
        update_timestamp: u64,
        next_update_timestamp: u64, 
        quorum_bitmap: u256,
    }

    struct OperatorSetParam has copy, drop, store {
        max_operator_count: u32,
    }

    public entry fun initialize() {
        if (is_initialized()) {
            return
        };

        // derive a resource account from signer to manage User share Account
        let operator_signer = &middleware_manager::get_signer();
        let (registry_coordinator_signer, signer_cap) = account::create_resource_account(operator_signer, REGISTRY_COORDINATOR_NAME);
        middleware_manager::add_address(string::utf8(REGISTRY_COORDINATOR_NAME), signer::address_of(&registry_coordinator_signer));
        move_to(&registry_coordinator_signer, RegistryCoordinatorConfigs {
            signer_cap,
        });
    }

    public fun create_registry_coordinator_store() acquires RegistryCoordinatorConfigs{
        let registry_coordinator_signer = registry_coordinator_signer();
        move_to(registry_coordinator_signer, RegistryCoordinatorStore{
            quorum_count: 0,
            quorum_params: smart_table::new(),
            operator_infos: smart_table::new(),
            operator_bitmap: smart_table::new(),
            operator_bitmap_history: smart_table::new(),
        })
    }

    #[view]
    public fun is_initialized(): bool{
        middleware_manager::address_exists(string::utf8(REGISTRY_COORDINATOR_NAME))
    }

    fun ensure_registry_coordinator_store() acquires RegistryCoordinatorConfigs{
        if(!exists<RegistryCoordinatorStore>(registry_coordinator_address())){
            create_registry_coordinator_store();
        }
    }

    // TODO: not done
    public fun registor_operator(quorum_numbers: vector<u8>, operator: &signer, params: bls_apk_registry::PubkeyRegistrationParams) acquires RegistryCoordinatorStore{
        let operator_id = get_or_create_operator_id(operator, params);

        let (_ , _ , num_operators_per_quorum) = register_operator_internal(operator, operator_id, quorum_numbers);

        let quorum_numbers_length = vector::length(&quorum_numbers);


        // TODO: limit num operators per quorum
        return
    }

    fun register_operator_internal(operator: &signer, operator_id: vector<u8>, quorum_numbers: vector<u8>): (vector<u128>, vector<u128>, vector<u32>) acquires RegistryCoordinatorStore {
        // TODO: using orderedBytesArrayToBitmap
        let quorum_to_add = math_utils::bytes32_to_u256(quorum_numbers);
        let current_bitmap = current_operator_bitmap(operator_id); 
        // TODO: error name
        assert!(quorum_to_add!=0, 301);
        // TODO: assert no bit in common
        let new_bitmap = current_bitmap | quorum_to_add;

        update_operator_bitmap(operator_id, new_bitmap);

        let mut_store = mut_registry_coordinator_store();
        let operator_address = signer::address_of(operator);
        let mut_operator_info = smart_table::borrow_mut(&mut mut_store.operator_infos, operator_address);
        
        if (mut_operator_info.operator_status != 1) {
            *mut_operator_info = OperatorInfo{
                operator_id: operator_id,
                operator_status: 1,
            };
            // TODO: 
            operator_manager::create_operator_store(operator_address);
        };

        bls_apk_registry::register_operator(operator, quorum_numbers);

        let (operator_stakes, total_stakes) = stake_registry::register_operator(operator_address, operator_id, quorum_numbers);
        let num_operators_per_quorum = index_registry::register_operator(string::utf8(operator_id), quorum_numbers);
        return (operator_stakes, total_stakes, num_operators_per_quorum)
    }

    public fun deregister_operator(operator: &signer, quorumNumbers: vector<u8>) acquires RegistryCoordinatorStore{
        deregister_operator_internal(operator, quorumNumbers);
    }

    fun deregister_operator_internal(operator: &signer, quorum_numbers: vector<u8>) acquires RegistryCoordinatorStore {
        let operator_address = signer::address_of(operator);
        let store = registry_coordinator_store();
        let operator_info = smart_table::borrow(&store.operator_infos, operator_address);
        let operator_id = operator_info.operator_id;
        assert!(operator_info.operator_status == 1, 202);

        let quorums_to_remove = ordered_vecu8_to_bitmap(quorum_numbers);

        let current_bitmap = current_operator_bitmap(operator_id);

        // TODO: assert here
        let new_bitmap = current_bitmap&(0xff^quorums_to_remove);
        update_operator_bitmap(operator_id, new_bitmap);


        let mut_store = mut_registry_coordinator_store();
        let mut_operator_info = smart_table::borrow_mut(&mut mut_store.operator_infos, operator_address);
        if (new_bitmap == 0) {
            mut_operator_info.operator_status = 2;
            // TODO: serviceManager.deregisterOperatorFromAVS(operator);

        };

        bls_apk_registry::deregister_operator(operator, quorum_numbers);
        stake_registry::deregister_operator(operator_id, quorum_numbers);
        index_registry::deregister_operator(string::utf8(operator_id), quorum_numbers);
    }

    public(friend) fun create_quorum(operator_set_params: OperatorSetParam, minumum_stake: u128, strategy_params: vector<stake_registry::StrategyParams>) acquires RegistryCoordinatorStore, RegistryCoordinatorConfigs {
        ensure_registry_coordinator_store();
        create_quorum_internal(operator_set_params, minumum_stake, strategy_params);
    }

    fun create_quorum_internal(operator_set_params: OperatorSetParam, minumum_stake: u128, strategy_params: vector<stake_registry::StrategyParams>) acquires RegistryCoordinatorStore {
        let pre_quorum_count = quorum_count();
        let mut_store = mut_registry_coordinator_store();
        let mut_quorum_count = &mut mut_store.quorum_count;
        *mut_quorum_count = *mut_quorum_count + 1;

        set_operator_set_params_internal(pre_quorum_count, operator_set_params);
        stake_registry::initialize_quorum(pre_quorum_count, minumum_stake, strategy_params);
        index_registry::initialize_quorum(pre_quorum_count);
        bls_apk_registry::initialize_quorum(pre_quorum_count);
    }

    public fun set_operator_set_params(quorum_number: u8, operator_set_params: OperatorSetParam) acquires RegistryCoordinatorStore {
        set_operator_set_params_internal(quorum_number, operator_set_params);
    }

    fun set_operator_set_params_internal(quorum_number: u8, operator_set_params: OperatorSetParam) acquires RegistryCoordinatorStore {
        let mut_store = mut_registry_coordinator_store();
        let mut_quorum_param = smart_table::borrow_mut_with_default(&mut mut_store.quorum_params, quorum_number, operator_set_params);
        *mut_quorum_param = operator_set_params
    }

    fun ordered_vecu8_to_bitmap(vec: vector<u8>): u256 {
        let bitmap: u256 = 0;
        let bitmask : u256 = 0;
        let vec_length = vector::length(&vec);
        let first_element = vector::borrow(&vec, 0);
        bitmap = 1 << (*first_element as u8);

        for (i in 1..vec_length) {
            let next_element = vector::borrow(&vec, i);
            bitmask = 1 << *next_element;

            assert!(bitmask > bitmap, 203);
            bitmap = (bitmap | bitmask);
        };
        return bitmap
    }


    fun get_or_create_operator_id(operator: &signer, params: bls_apk_registry::PubkeyRegistrationParams): vector<u8>{
        let operator_address = signer::address_of(operator);
        let operator_id = bls_apk_registry::get_operator_id(operator_address);
        if (vector::is_empty(&operator_id)) {
            // TODO: help
            operator_id = bls_apk_registry::register_bls_pubkey(operator, params, vector::empty<u8>());
        };
        return operator_id
    }

    fun pubkey_registration_message_hash(operator: &signer) {
        // TODO: help
    }

    fun current_operator_bitmap(operator_id: vector<u8>):u256 acquires RegistryCoordinatorStore {
        let store = registry_coordinator_store();
        let operator_bitmap_history_length = vector::length(smart_table::borrow(&store.operator_bitmap_history, operator_id));
        if (operator_bitmap_history_length == 0) {
            return 0
        } else {
            return vector::borrow(smart_table::borrow(&store.operator_bitmap_history, operator_id), operator_bitmap_history_length-1).quorum_bitmap
        }
    }

    fun update_operator_bitmap(operator_id : vector<u8>, new_bitmap: u256) acquires RegistryCoordinatorStore {
        let mut_store = mut_registry_coordinator_store();
        let mut_operator_bitmap = smart_table::borrow_mut(&mut mut_store.operator_bitmap_history, operator_id);
        let history_length = vector::length(mut_operator_bitmap);
        if (history_length == 0) {
            vector::push_back(mut_operator_bitmap, QuorumBitmapUpdate{
                update_timestamp: timestamp::now_seconds(),
                next_update_timestamp: 0,
                quorum_bitmap: new_bitmap,
            })
        } else {
            let last_update = vector::borrow_mut(mut_operator_bitmap, history_length-1);
            if (last_update.update_timestamp == timestamp::now_seconds()) {
                last_update.quorum_bitmap = new_bitmap;
            } else {
                last_update.next_update_timestamp = timestamp::now_seconds();
                vector::push_back(mut_operator_bitmap, QuorumBitmapUpdate{
                    update_timestamp: timestamp::now_seconds(),
                    next_update_timestamp: 0,
                    quorum_bitmap: new_bitmap,
                });
            }
        }
    }

    #[view]
    public fun get_operator_id(operator: address): vector<u8> acquires RegistryCoordinatorStore {
        let store = registry_coordinator_store();
        smart_table::borrow(&store.operator_infos, operator).operator_id
    }

    #[view]
    public fun get_current_quorum_bitmap(operator_id: vector<u8>): u256 acquires RegistryCoordinatorStore {
        let store = registry_coordinator_store();
        *smart_table::borrow(&store.operator_bitmap, operator_id)
    }

    #[view]
    public fun quorum_count(): u8 acquires RegistryCoordinatorStore {
        let store = registry_coordinator_store();
        store.quorum_count
    }

    inline fun registry_coordinator_store(): &RegistryCoordinatorStore acquires RegistryCoordinatorStore{
        borrow_global<RegistryCoordinatorStore>(registry_coordinator_address())
    }

    inline fun mut_registry_coordinator_store(): &mut RegistryCoordinatorStore acquires RegistryCoordinatorStore {
        borrow_global_mut<RegistryCoordinatorStore>(registry_coordinator_address())
    }

    #[view]
    public fun registry_coordinator_address(): address {
        middleware_manager::get_address(string::utf8(REGISTRY_COORDINATOR_NAME))
    }

    inline fun registry_coordinator_signer(): &signer acquires RegistryCoordinatorConfigs{
        &account::create_signer_with_capability(&borrow_global<RegistryCoordinatorConfigs>(registry_coordinator_address()).signer_cap)
    }

    public fun operator_set_param(max_operator_count: u32): OperatorSetParam {
        return OperatorSetParam{
            max_operator_count,
        }
    }

    public fun set_bit(number: u256, index: u8): u256 {
        number | (1u256 << index)
    }

    #[test_only]
    friend middleware::service_manager_tests;
    #[test_only]
    friend middleware::registry_coordinator_tests;
}