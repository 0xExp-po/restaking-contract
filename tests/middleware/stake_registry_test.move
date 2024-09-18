#[test_only]

module middleware::stake_registry_tests {
  use aptos_framework::coin::{Self, Coin};
  use aptos_framework::fungible_asset::{Self, FungibleAsset, Metadata};
  use aptos_framework::object::{Self, Object};
  use aptos_framework::primary_fungible_store;

  use aptos_std::comparator;
  use aptos_std::debug;

  use std::signer;
  use std::vector;
  use std::string;

  use middleware::middleware_test_helpers;
  use middleware::service_manager;
  use middleware::registry_coordinator;
  use middleware::stake_registry;

  #[test(deployer = @0xcafe, staker = @0xab12, middleware=@0xabcfff)]
  public fun test_init_quorum(deployer: &signer, middleware: &signer, staker: &signer) {
    middleware_test_helpers::middleware_set_up(deployer, middleware);
    assert!(registry_coordinator::is_initialized() == true, 0);

    let staked_amount = 1000;
    
    let fa = middleware_test_helpers::create_fungible_asset_and_mint(deployer, b"Token 1", 1000);
    let token = fungible_asset::asset_metadata(&fa);

    let store = primary_fungible_store::ensure_primary_store_exists(signer::address_of(deployer), token);
    fungible_asset::deposit(store, fa);

    let operator_set_params = registry_coordinator::operator_set_param(100);
    let minimum_stake: u128 = 1;
    let quorum_number = 0;

    let strategy_params = stake_registry::create_strategy_param(token, 1);
    let vec_strategy_params = stake_registry::create_vec_strategy_params(strategy_params);

    stake_registry::initialize_quorum(quorum_number , 1, vec_strategy_params);

    let metadata = stake_registry::strategy_by_index(0, 0);

    assert!(stake_registry::minimum_stake(quorum_number) == 1, 1);
    assert!(stake_registry::strategy_params_length(quorum_number) == 1, 2);
    assert!(stake_registry::total_history_length(quorum_number)== 1, 3);

    debug::print<Object<Metadata>>(&metadata);
  }

    #[test(deployer = @0xcafe, staker = @0xab12, middleware=@0xabcfff)]
    public fun test_add_stategies(deployer: &signer, middleware: &signer, staker: &signer) {
        middleware_test_helpers::middleware_set_up(deployer, middleware);
        assert!(registry_coordinator::is_initialized() == true, 0);

        let staked_amount = 1000;

        let fa = middleware_test_helpers::create_fungible_asset_and_mint(deployer, b"Token 1", 1000);
        let token = fungible_asset::asset_metadata(&fa);

        let store = primary_fungible_store::ensure_primary_store_exists(signer::address_of(deployer), token);
        fungible_asset::deposit(store, fa);

        let operator_set_params = registry_coordinator::operator_set_param(100);
        let minimum_stake: u128 = 1;
        let quorum_number = 0;

        let strategy_params = stake_registry::create_strategy_param(token, 1);
        let vec_strategy_params = stake_registry::create_vec_strategy_params(strategy_params);

        let fa = middleware_test_helpers::create_fungible_asset_and_mint(deployer, b"Token 2", 20000);
        let token = fungible_asset::asset_metadata(&fa);

        let store = primary_fungible_store::ensure_primary_store_exists(signer::address_of(deployer), token);
        fungible_asset::deposit(store, fa);

        let strategy_params2 = stake_registry::create_strategy_param(token, 1);
        let vec_strategy_params2 = stake_registry::create_vec_strategy_params(strategy_params2);

        stake_registry::initialize_quorum(quorum_number , 1, vec_strategy_params);
        stake_registry::add_stategies(quorum_number, vec_strategy_params2);

        let metadata = stake_registry::strategy_by_index(0, 0);

        assert!(stake_registry::minimum_stake(quorum_number) == 1, 1);
        assert!(stake_registry::strategy_params_length(quorum_number) == 2, 2);
        assert!(stake_registry::total_history_length(quorum_number)== 1, 3);
    }

    #[test(deployer = @0xcafe, staker = @0xab12, middleware=@0xabcfff)]
    public fun test_remove_stategies(deployer: &signer, middleware: &signer, staker: &signer) {
        middleware_test_helpers::middleware_set_up(deployer, middleware);
        assert!(registry_coordinator::is_initialized() == true, 0);

        let staked_amount = 1000;

        let fa = middleware_test_helpers::create_fungible_asset_and_mint(deployer, b"Token 1", 1000);
        let token = fungible_asset::asset_metadata(&fa);

        let store = primary_fungible_store::ensure_primary_store_exists(signer::address_of(deployer), token);
        fungible_asset::deposit(store, fa);

        let operator_set_params = registry_coordinator::operator_set_param(100);
        let minimum_stake: u128 = 1;
        let quorum_number = 0;

        let strategy_params = stake_registry::create_strategy_param(token, 1);
        let vec_strategy_params = stake_registry::create_vec_strategy_params(strategy_params);

        let fa = middleware_test_helpers::create_fungible_asset_and_mint(deployer, b"Token 2", 20000);
        let token = fungible_asset::asset_metadata(&fa);

        let store = primary_fungible_store::ensure_primary_store_exists(signer::address_of(deployer), token);
        fungible_asset::deposit(store, fa);

        let strategy_params2 = stake_registry::create_strategy_param(token, 1);
        let vec_strategy_params2 = stake_registry::create_vec_strategy_params(strategy_params2);

        stake_registry::initialize_quorum(quorum_number , 1, vec_strategy_params);
        stake_registry::add_stategies(quorum_number, vec_strategy_params2);

        stake_registry::remove_strategies(quorum_number, vector[0]);

        assert!(stake_registry::minimum_stake(quorum_number) == 1, 1);
        assert!(stake_registry::strategy_params_length(quorum_number) == 1, 2);
        assert!(stake_registry::total_history_length(quorum_number)== 1, 3);
        assert!(fungible_asset::name((stake_registry::strategy_by_index(0, 0))) == string::utf8(b"Token 2"), 4);
    }

    // TODO: register_operator test and deregister_operator test
}