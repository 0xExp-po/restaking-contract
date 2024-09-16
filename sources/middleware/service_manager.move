module middleware::service_manager{
    use aptos_framework::event;
    use aptos_framework::fungible_asset::{
    Self, Metadata,
    };
    use aptos_framework::object::{Self, Object};
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::timestamp;
    use aptos_framework::primary_fungible_store;

    use middleware::middleware_manager;
    use middleware::registry_coordinator;
    use middleware::stake_registry;

    use aptos_std::smart_table::{Self, SmartTable};
    use aptos_std::aptos_hash;
    use aptos_std::comparator;
    use aptos_std::smart_vector::{Self, SmartVector};

    use restaking::math_utils;

    use std::string;
    use std::bcs;
    use std::vector;
    use std::signer;

    const SERVICE_MANAGER_NAME: vector<u8> = b"SERVICE_MANAGER_NAME";
    const SERVICE_PREFIX: vector<u8> = b"SERVICE_PREFIX";

    struct ServiceManagerConfigs has key {
        signer_cap: SignerCapability,
        strategy_params: SmartTable<u8, vector<StrategyParams>>,
        quorum_count: u8,
    }

    struct StrategyParams has copy, drop, store {
        strategy: address,
        multiplier: u128,
    }

    struct SignatureWithSaltAndExpiry has copy, drop, store {
        signature: vector<u8>,
        salt: vector<u8>,
        expiry: u128,
    }

    public entry fun initialize() {
        if (is_initialized()) {
            return
        };

        // derive a resource account from signer to manage User share Account
        let middleware_signer = &middleware_manager::get_signer();
        let (service_manager_signer, signer_cap) = account::create_resource_account(middleware_signer, SERVICE_MANAGER_NAME);
        middleware_manager::add_address(string::utf8(SERVICE_MANAGER_NAME), signer::address_of(&service_manager_signer));
        move_to(&service_manager_signer, ServiceManagerConfigs {
            signer_cap,
            strategy_params: smart_table::new(),
            quorum_count: 0,
        });
    }

    #[view]
    public fun is_initialized(): bool{
        // TODO: use a seperate package manager
        middleware_manager::address_exists(string::utf8(SERVICE_MANAGER_NAME))
    }

    #[view]
    public fun get_restakeable_strategies(operator: address): vector<address> acquires ServiceManagerConfigs {
        let quorum_count = registry_coordinator::quorum_count();
        let configs = rewards_configs();
        if (quorum_count == 0){
            return vector::empty<address>()
        };

        
        let strategy_count: u64 = 0;
        for (i in 0..configs.quorum_count) {
            strategy_count = strategy_count + vector::length(smart_table::borrow(&configs.strategy_params, i));
        };

        let restaked_strategies = vector::empty<address>() ;

        for (i in 0..configs.quorum_count) {
            let strategyParamsLength = vector::length(smart_table::borrow(&configs.strategy_params, i));
            for (j in 0..strategyParamsLength){
                vector::push_back(&mut restaked_strategies, strategy_params_by_index(i,j).strategy);
            };
        };

        restaked_strategies
    }

    public fun get_operator_restaked_strategies(operator: address): vector<Object<Metadata>>{
        let operator_id = registry_coordinator::get_operator_id(operator);
        let operator_bitmap = registry_coordinator::get_current_quorum_bitmap(operator_id);
        if (operator_bitmap == 0 || registry_coordinator::quorum_count() == 0) {

            // TODO: return vector address
            return vector::empty<Object<Metadata>>()
        };

        let operator_restaked_quorums = math_utils::u256_to_bytes32(operator_bitmap);
        let strategy_count: u64 = 0;

        for (i in 0..vector::length(&operator_restaked_quorums)) {
            let operator_restaked_quorum = vector::borrow(&operator_restaked_quorums , i);
            strategy_count = strategy_count + stake_registry::strategy_params_length(*operator_restaked_quorum);
        };

        let restaked_strategies = vector::empty<Object<Metadata>>();
        let index: u256;

        for (i in 0..vector::length(&operator_restaked_quorums)) {
            let operator_restaked_quorum = vector::borrow(&operator_restaked_quorums , i);
            let strategy_params_length = stake_registry::strategy_params_length(*operator_restaked_quorum);
            for (j in 0..strategy_params_length) {
                vector::push_back(&mut restaked_strategies, stake_registry::strategy_by_index(*operator_restaked_quorum, j));
            };
        };
        return restaked_strategies
    }



    inline fun strategy_params_by_index(quorum_number: u8, index: u64): & StrategyParams{
        let configs = rewards_configs();
        let strategy = smart_table::borrow(&configs.strategy_params, quorum_number);
        let strategyParams = vector::borrow(strategy, index);
        strategyParams
    }

    inline fun rewards_configs(): &ServiceManagerConfigs acquires ServiceManagerConfigs{
        borrow_global<ServiceManagerConfigs>(rewards_coordinator_address())
    }

    inline fun mut_rewards_configs(): &mut ServiceManagerConfigs acquires ServiceManagerConfigs {
        borrow_global_mut<ServiceManagerConfigs>(rewards_coordinator_address())
    }

    inline fun rewards_coordinator_address(): address {
        middleware_manager::get_address(string::utf8(SERVICE_MANAGER_NAME))
    }
}