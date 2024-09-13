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

    use aptos_std::smart_table::{Self, SmartTable};
    use aptos_std::smart_vector::{Self, SmartVector};
    use aptos_std::bn254_algebra::{G1, G2};
    
    use aptos_std::aptos_hash;
    use aptos_std::comparator;

    use std::string;
    use std::bcs;
    use std::vector;
    use std::signer;

    const REGISTRY_COORDINATOR_NAME: vector<u8> = b"STAKE_REGISTRY_NAME";
    const REGISTRY_COORDINATOR_PREFIX: vector<u8> = b"STAKE_PREFIX";

    struct RegistryCoordinatorConfigs has key {
        signer_cap: SignerCapability,
        quorum_count: u8,
        operator_infos: SmartTable<address, OperatorInfo>,
        operator_bitmap: SmartTable<vector<u8>, u256>,
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

    public entry fun initialize() {
        if (is_initialized()) {
            return
        };

        // derive a resource account from signer to manage User share Account
        let staking_signer = &middleware_manager::get_signer();
        let (stake_registry_signer, signer_cap) = account::create_resource_account(staking_signer, REGISTRY_COORDINATOR_NAME);
        middleware_manager::add_address(string::utf8(REGISTRY_COORDINATOR_NAME), signer::address_of(&stake_registry_signer));
        move_to(&stake_registry_signer, RegistryCoordinatorConfigs {
            signer_cap,
            quorum_count: 0,
            operator_infos: smart_table::new(),
            operator_bitmap: smart_table::new(),
        });
    }

    #[view]
    public fun is_initialized(): bool{
        // TODO: use a seperate package manager
        middleware_manager::address_exists(string::utf8(REGISTRY_COORDINATOR_NAME))
    }

    // TODO: not done
    public fun registor_operator(quorum_numbers: vector<u8> ) {
        return
    }

    fun get_or_create_operator_id(operator: address, params: PubkeyRegistrationParams): vector<u8>{
        let operator_id = vector::empty<u8>();
        // operatorId = blsApkRegistry.getOperatorId(operator);
        if (vector::is_empty(&operator_id)) {
            // operatorId = blsApkRegistry.registerBLSPublicKey(operator, params, pubkeyRegistrationMessageHash(operator));
        };
        return operator_id
    }

    #[view]
    public fun get_operator_id(operator: address): vector<u8> acquires RegistryCoordinatorConfigs {
        let configs = registry_coordinator_configs();
        smart_table::borrow(&configs.operator_infos, operator).operator_id
    }

    #[view]
    public fun get_current_quorum_bitmap(operator_id: vector<u8>): u256 acquires RegistryCoordinatorConfigs {
        let configs = registry_coordinator_configs();
        *smart_table::borrow(&configs.operator_bitmap, operator_id)
    }

    #[view]
    public fun quorum_count(): u8 acquires RegistryCoordinatorConfigs {
        let configs = registry_coordinator_configs();
        configs.quorum_count
    }

    inline fun registry_coordinator_configs(): &RegistryCoordinatorConfigs acquires RegistryCoordinatorConfigs{
        borrow_global<RegistryCoordinatorConfigs>(registry_coordinator_address())
    }

    inline fun mut_registry_coordinator_configs(): &mut RegistryCoordinatorConfigs acquires RegistryCoordinatorConfigs {
        borrow_global_mut<RegistryCoordinatorConfigs>(registry_coordinator_address())
    }

    inline fun registry_coordinator_address(): address {
        middleware_manager::get_address(string::utf8(REGISTRY_COORDINATOR_NAME))
    }

    public fun set_bit(number: u256, index: u8): u256 {
        number | (1u256 << index)
    }
}