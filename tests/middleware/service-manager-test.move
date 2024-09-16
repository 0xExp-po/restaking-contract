#[test_only]

module middleware::service_manager_tests {
  use aptos_framework::coin::{Self, Coin};
  use aptos_framework::fungible_asset::{Self, FungibleAsset, Metadata};
  use aptos_framework::object;
  use aptos_framework::primary_fungible_store;

  use aptos_std::comparator;

  use std::signer;
  use std::vector;

  use middleware::middleware_test_helpers;
  use middleware::service_manager;
  use middleware::registry_coordinator;
  use middleware::stake_registry;

  #[test(deployer = @0xcafe, staker = @0x53af, avs = @0xab12, ra=@0xabcfff)]
  public fun test_avs_get_restakeable_strategies(deployer: &signer, ra: &signer, avs: &signer, staker: &signer){
    middleware_test_helpers::middleware_set_up(deployer, ra);
    
    let avs_addr = signer::address_of(avs);
    let staked_amount = 1000;
    
    let fa = middleware_test_helpers::create_fungible_asset_and_mint(deployer, b"Token 1", 1000);
    let token = fungible_asset::asset_metadata(&fa);

    let store = primary_fungible_store::ensure_primary_store_exists(signer::address_of(deployer), token);
    fungible_asset::deposit(store, fa);

    let operator_set_params = registry_coordinator::operator_set_param(100);
    let minimum_stake: u128 = 1;


    let strategy_params = stake_registry::create_strategy_param(token, 1);
    let vec_strategy_params = stake_registry::create_vec_strategy_params(strategy_params);

    registry_coordinator::create_quorum(operator_set_params, minimum_stake, vec_strategy_params);
  }
}