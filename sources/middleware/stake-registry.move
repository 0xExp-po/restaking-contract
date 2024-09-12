module middleware::stake_registry{
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

    use aptos_std::smart_table::{Self, SmartTable};
    use aptos_std::smart_vector::{Self, SmartVector};
    
    use aptos_std::aptos_hash;
    use aptos_std::comparator;

    use std::string;
    use std::bcs;
    use std::vector;
    use std::signer;

    const WEIGHTING_DIVISOR: u128 = 1_000_000_000_000_000_000; // 1e18

    const MAX_WEIGHING_FUNCTION_LENGTH : u32 = 32;


    const STAKE_REGISTRY_NAME: vector<u8> = b"STAKE_REGISTRY_NAME";
    const STAKE_PREFIX: vector<u8> = b"STAKE_PREFIX";


    const EUNINITIALZED_QUORUM: u64 = 101;
    const EMINUMUM_STAKE_REQUIRED: u64 = 102;
    const ENO_STRATEGY_PROVIED: u64 = 103;
    const ESAME_STRATEGY_PROVIED: u64 = 104;
    const EZERO_MULTIPLIER: u64 = 105;

    struct StakeRegistryConfigs has key {
        signer_cap: SignerCapability,
        total_stake_history: SmartTable<u8, vector<StakeUpdate>>,
        strategy_params: SmartTable<u8, SmartVector<StrategyParams>>,
        minimum_stake_for_quorum: SmartTable<u8, u128>,
        operator_stake_history: SmartTable<vector<u8>, SmartTable<u8, vector<StakeUpdate>>>,
    }

    struct StakeUpdate has copy, drop, store {
        update_timestamp : u64, 
        next_update_timestamp : u64,
        stake: u128,
    }

    struct StrategyParams has copy, drop, store {
        strategy: Object<Metadata>,
        multiplier: u128,
    }

    public entry fun initialize() {
        if (is_initialized()) {
            return
        };

        // derive a resource account from signer to manage User share Account
        let staking_signer = &middleware_manager::get_signer();
        let (stake_registry_signer, signer_cap) = account::create_resource_account(staking_signer, STAKE_REGISTRY_NAME);
        middleware_manager::add_address(string::utf8(STAKE_REGISTRY_NAME), signer::address_of(&stake_registry_signer));
        move_to(&stake_registry_signer, StakeRegistryConfigs {
            signer_cap,
            total_stake_history: smart_table::new(),
            strategy_params: smart_table::new(),
            minimum_stake_for_quorum: smart_table::new(),
            operator_stake_history: smart_table::new(),
        });
    }

    #[view]
    public fun is_initialized(): bool{
        // TODO: use a seperate package manager
        middleware_manager::address_exists(string::utf8(STAKE_REGISTRY_NAME))
    }


    // TODO: only registry cordinator can call
    public fun register_operator(operator: address, operatorId: vector<u8>, quorum_numbers: vector<u8>): (vector<u128>, vector<u128>) acquires StakeRegistryConfigs{
        let current_stakes = vector::empty<u128>();
        let total_stakes = vector::empty<u128>();


        for (i in 0..vector::length(&quorum_numbers)) {
            let quorum_number = vector::borrow(&quorum_numbers, i);
            quorum_exists(*quorum_number);

            let (current_stake, has_minimum_stake) = weight_of_operator_for_quorum(*quorum_number, operator);

            assert!(has_minimum_stake, EMINUMUM_STAKE_REQUIRED);

            let (stake_delta, decrease) = record_operator_stake_update(operatorId, *quorum_number, current_stake);

            vector::push_back(&mut current_stakes, current_stake);
            let new_stake = record_total_stake_update(*quorum_number, stake_delta, decrease);
            vector::push_back(&mut total_stakes, new_stake);
        };


        return (current_stakes, total_stakes)
    }



    // TODO: only registry cordinator can call
    public fun deregister_operator(operatorId: vector<u8>, quorum_numbers: vector<u8>) acquires StakeRegistryConfigs {
        let quorum_numbers_length = vector::length(&quorum_numbers);
        for (i in 0..quorum_numbers_length) {
            let quorum_number = vector::borrow(&quorum_numbers, i);
            quorum_exists(*quorum_number);

            let (stake_delta, decrease) = record_operator_stake_update(operatorId, *quorum_number, 0);

            record_total_stake_update(*quorum_number, stake_delta, decrease);
        }
    }

    public fun update_operator_stake(operator: address, operatorId: vector<u8>, quorum_numbers: vector<u8>) acquires StakeRegistryConfigs {
        let quorums_to_remove: u256;
        let quorum_numbers_length = vector::length(&quorum_numbers);
        for (i in 0..quorum_numbers_length) {
            let quorum_number = vector::borrow(&quorum_numbers, i);
            quorum_exists(*quorum_number);

            let (current_stake, has_minimum_stake) = weight_of_operator_for_quorum(*quorum_number, operator);

            if (!has_minimum_stake) {
                current_stake = 0;
                // TODO: how to set quorums to remove
                quorums_to_remove =1;
            };

            let (stake_delta, decrease) = record_operator_stake_update(operatorId, *quorum_number, current_stake);
            record_total_stake_update(*quorum_number, stake_delta, decrease);
        }
    }


    // TODO: only coordinator
    public fun initialize_quorum(quorum_number: u8, minimum_stake: u128, strategy_params: vector<StrategyParams>) acquires StakeRegistryConfigs {
        quorum_exists(quorum_number);
        set_minimum_stake_for_quorum(quorum_number, minimum_stake);


        let mut_configs = mut_stake_registry_configs();
        let total_stake_history = smart_table::borrow_mut(&mut mut_configs.total_stake_history, quorum_number);
        vector::push_back(total_stake_history, StakeUpdate{
            update_timestamp: timestamp::now_seconds(),
            next_update_timestamp: 0,
            stake: 0,
        });
    }


    // TODO: only coordinator
    public fun add_stategies(quorum_number: u8, strategy_params: vector<StrategyParams>) acquires StakeRegistryConfigs{
        add_strategy_params(quorum_number, strategy_params);
    }

    public fun remove_strategies(quorum_number: u8, indices_to_remove: vector<u64>) acquires StakeRegistryConfigs{
        let indices_to_remove_length = vector::length(&indices_to_remove);
        assert!(indices_to_remove_length > 0, 106);

        let mut_configs = mut_stake_registry_configs();

        let mut_strategy_params = smart_table::borrow_mut(&mut mut_configs.strategy_params, quorum_number);
        for (i in 0..indices_to_remove_length) {
            let indice_to_remove = vector::borrow(&indices_to_remove, i);
            smart_vector::remove(mut_strategy_params, *indice_to_remove);
        }
    }

    fun weight_of_operator_for_quorum(quorum_number: u8, operator: address): (u128, bool) acquires StakeRegistryConfigs{
        let configs = stake_registry_configs();
        let weight: u128 = 0;
        let strategy_param_length = strategy_param_length(quorum_number);
        
        let shares = vector::empty<u128>();
        for (i in 0..strategy_param_length) {
            let token = strategyParamsByIndex(quorum_number, i).strategy;
            vector::push_back(&mut shares, staker_manager::staker_token_shares(operator, token));
            let share = staker_manager::staker_token_shares(operator, token);
            let strategy_params = strategyParamsByIndex(quorum_number, i);

            if (share > 0 ) {
                weight = weight + share*strategy_params.multiplier/WEIGHTING_DIVISOR;
            }
        };

        let has_minimum_stake =  weight > *smart_table::borrow(&configs.minimum_stake_for_quorum, quorum_number);
        return (weight, has_minimum_stake)
    }

    fun record_operator_stake_update(operatorId: vector<u8>, quorum_number: u8, new_stake: u128 ): (u128, bool) acquires StakeRegistryConfigs{
        let history_length = operator_history_length(operatorId, quorum_number);
        let configs = mut_stake_registry_configs();
        let prev_stake: u128 = 0;
        

        if (history_length == 0) {
            let history = smart_table::borrow_mut(smart_table::borrow_mut(&mut configs.operator_stake_history, operatorId), quorum_number);
            vector::push_back(history, StakeUpdate{
                update_timestamp: timestamp::now_seconds(),
                next_update_timestamp: 0,
                stake: new_stake,
            });
        } else {
            let last_update = vector::borrow_mut(smart_table::borrow_mut(smart_table::borrow_mut(&mut configs.operator_stake_history, operatorId), quorum_number), history_length-1);
            prev_stake = last_update.stake;

            if (prev_stake == new_stake) {
                return (0, false)
            };

            if (last_update.update_timestamp == timestamp::now_seconds()){
                last_update.stake = new_stake;
            } else {
                last_update.next_update_timestamp = timestamp::now_seconds();
                let history = smart_table::borrow_mut(smart_table::borrow_mut(&mut configs.operator_stake_history, operatorId), quorum_number);
                vector::push_back(history, StakeUpdate{
                    update_timestamp: timestamp::now_seconds(),
                    next_update_timestamp: 0,
                    stake: new_stake,
                });
            };
        };
        
        if (new_stake > prev_stake) {
            return ((new_stake - prev_stake), false)
        } else {
            return ((prev_stake - new_stake), true)
        }
    }

    fun record_total_stake_update(quorum_number: u8, stake_delta: u128, decrease: bool): u128 acquires StakeRegistryConfigs{
        let history_length = total_history_length(quorum_number);

        let mut_configs = mut_stake_registry_configs();
        let mut_last_stake_update = vector::borrow_mut(smart_table::borrow_mut(&mut mut_configs.total_stake_history, quorum_number), history_length - 1);
        if (stake_delta == 0) {
            return mut_last_stake_update.stake
        };

        let new_stake: u128;
        if (decrease) {
            new_stake = mut_last_stake_update.stake - stake_delta;
        } else {
            new_stake = mut_last_stake_update.stake + stake_delta;
        };

        if (mut_last_stake_update.update_timestamp == timestamp::now_seconds()){
            mut_last_stake_update.stake = new_stake
        } else {
            mut_last_stake_update.next_update_timestamp = timestamp::now_seconds();
            vector::push_back(smart_table::borrow_mut(&mut mut_configs.total_stake_history, quorum_number), StakeUpdate{
                    update_timestamp: timestamp::now_seconds(),
                    next_update_timestamp: 0,
                    stake: new_stake,
                });

        };

        return 0
    }

    fun add_strategy_params(quorum_number: u8, strategy_params: vector<StrategyParams>) acquires StakeRegistryConfigs {
        let new_strategy_params_length = vector::length(&strategy_params);

        assert!(new_strategy_params_length>0, ENO_STRATEGY_PROVIED);

        let existing_strategy_params_length = strategy_param_length(quorum_number);
        let mut_configs = mut_stake_registry_configs();
        let mut_existing_strategy_params = smart_table::borrow_mut(&mut mut_configs.strategy_params, quorum_number);
        // TODO: should we limit strategy_params_length + existing_strategy_params_length
        for (i in 0..new_strategy_params_length) {
            for (j in 0..existing_strategy_params_length){
                assert!(smart_vector::borrow_mut(mut_existing_strategy_params, j) != vector::borrow(&strategy_params, i), ESAME_STRATEGY_PROVIED);
            };
            assert!(vector::borrow(&strategy_params, i).multiplier > 0, EZERO_MULTIPLIER);

            smart_vector::push_back(mut_existing_strategy_params, *vector::borrow(&strategy_params, i));
        };
    }

    fun set_minimum_stake_for_quorum(quorum_number: u8, minimum_stake: u128) acquires StakeRegistryConfigs {
        let mut_configs = mut_stake_registry_configs();
        let minimum_stake_for_quorum = smart_table::borrow_mut(&mut mut_configs.minimum_stake_for_quorum, quorum_number);
        *minimum_stake_for_quorum = minimum_stake;
    }



    inline fun last_stake_update(quorum_number: u8, history_length: u64): StakeUpdate {
        let configs = stake_registry_configs();
        let last_stake_update = vector::borrow(smart_table::borrow(&configs.total_stake_history, quorum_number), history_length-1);
        *last_stake_update
    }

    inline fun total_history_length(quorum_number: u8): u64 {
        let configs = stake_registry_configs();
        let history_length = vector::length(smart_table::borrow(&configs.total_stake_history, quorum_number));
        history_length
    }

    inline fun operator_history_length(operatorId: vector<u8>, quorum_number: u8): u64 {
        let configs = stake_registry_configs();
        let history_length = vector::length(smart_table::borrow(smart_table::borrow(&configs.operator_stake_history, operatorId), quorum_number));
        history_length
    }

    inline fun strategy_param_length(quorum_number: u8): u64 {
        let configs = stake_registry_configs();
        let strategy_param_length = smart_vector::length(smart_table::borrow(&configs.strategy_params, quorum_number));
        strategy_param_length
    }

    inline fun strategyParamsByIndex(quorum_number: u8, index: u64): & StrategyParams{
        let configs = stake_registry_configs();
        let strategy = smart_table::borrow(&configs.strategy_params, quorum_number);
        let strategyParams = smart_vector::borrow(strategy, index);
        strategyParams
    }
    
    inline fun quorum_exists(quorum_number: u8) {
        let configs = stake_registry_configs();
        let stake_updates_length = vector::length(smart_table::borrow(&configs.total_stake_history, quorum_number));
        assert!(stake_updates_length > 0, EUNINITIALZED_QUORUM);
    }

    inline fun stake_registry_configs(): &StakeRegistryConfigs acquires StakeRegistryConfigs{
        borrow_global<StakeRegistryConfigs>(stake_registry_address())
    }

    inline fun mut_stake_registry_configs(): &mut StakeRegistryConfigs acquires StakeRegistryConfigs {
        borrow_global_mut<StakeRegistryConfigs>(stake_registry_address())
    }

    inline fun stake_registry_address(): address {
        middleware_manager::get_address(string::utf8(STAKE_REGISTRY_NAME))
    }
}