#[test_only]
module middleware::test_helpers {
  use aptos_framework::coin::{Self, Coin};
  use aptos_framework::fungible_asset::{Self, FungibleAsset};
  use aptos_framework::object;
  use aptos_framework::primary_fungible_store;
  use std::option;
  use std::string;

  use middleware::middleware_manager;
  use middleware::index_registry;
  use middleware::bls_apk_registry;
  use middleware::registry_coordinator;
  use middleware::service_manager;
  use middleware::stake_registry;
  
  public fun set_up(deployer: &signer, ra: &signer){
    middleware_manager::initialize_for_test(deployer, ra);
    bls_apk_registry::initialize();
    index_registry::initialize();
    service_manager::initialize();
    stake_registry::initialize();
    registry_coordinator::initialize();

    assert!(stake_registry::is_initialized(), 0);
    assert!(bls_apk_registry::is_initialized(), 0);
    assert!(index_registry::is_initialized(), 0);
    assert!(service_manager::is_initialized(), 0);
    assert!(registry_coordinator::is_initialized(), 0);
  }
}