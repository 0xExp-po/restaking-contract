#[test_only]

module middleware::service_manager_tests {
  use aptos_framework::coin::{Self, Coin};
  use aptos_framework::fungible_asset::{Self, FungibleAsset};
  use aptos_framework::object;
  use aptos_framework::primary_fungible_store;

  use aptos_std::comparator;

  use std::signer;
  use std::vector;

  use middleware::middleware_test_helpers;
  use middleware::service_manager;
  use middleware::registry_coordinator;

  #[test(deployer = @0xcafe, staker = @0x53af, avs = @0xab12, ra=@0xabcfff)]
  public fun test_avs_get_restakeable_strategies(deployer: &signer, ra: &signer, avs: &signer, staker: &signer){
    middleware_test_helpers::middleware_set_up(deployer, ra);
    
    let avs_addr = signer::address_of(avs);
    let staked_amount = 1000;
    

  }
}