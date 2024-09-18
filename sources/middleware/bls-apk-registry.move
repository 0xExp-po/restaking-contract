module middleware::bls_apk_registry{
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::event;
    use aptos_framework::timestamp;

    use aptos_std::crypto_algebra;
    use aptos_std::bls12381::{AggrPublicKeysWithPoP, Signature, PublicKeyWithPoP, aggregate_pubkeys, public_key_with_pop_to_bytes};
    use aptos_std::bls12381_algebra::{G1, FormatG1Uncompr};
    use aptos_std::smart_table::{Self, SmartTable};
    use aptos_std::option;
    use aptos_std::option::{Option};

    use std::string::{Self, String};
    use std::vector;
    use std::signer;
    
    use middleware::middleware_manager; 
    use middleware::registry_coordinator;

    friend middleware::registry_coordinator;

    const ZERO_PK_HASH: vector<u8> = x"ad3228b676f7d3cd4284a5443f17f1962b36e491b30a40b2405849e597ba5fb5";
    
    const BLS_APK_REGISTRY_NAME: vector<u8> = b"BLS_APK_REGISTRY_NAME";

    const EQUORUM_ALREADY_EXIST: u64 = 1101;
    const EQUORUM_DOES_NOT_EXIST: u64 = 1102;
    const EZERO_PUBKEY: u64 = 1103;
    const EINVALID_PUBKEY_G1: u64 = 1104;
    const EINVALID_PUBKEY_G2: u64 = 1105;
    const EOPERATOR_ALREADY_EXIST: u64 = 1106;
    const EPUBKEY_ALREADY_EXIST: u64 = 1107;
    const EPUBKEY_NOT_EXIST: u64 = 1108;

    struct BLSApkRegistryStore has key {
        operator_to_pk_hash: SmartTable<address, vector<u8>>,
        pk_hash_to_operator: SmartTable<vector<u8>, address>,
        operator_to_pk: SmartTable<address, PublicKeyWithPoP>,
        apk_history: SmartTable<u8, vector<ApkUpdate>>,
        current_apk: SmartTable<u8, vector<PublicKeyWithPoP>>
    }

    struct ApkUpdate has store, drop {
        aggregate_pubkeys: Option<AggrPublicKeysWithPoP>,
        update_timestamp: u64,
        next_update_timestamp: u64
    }

    struct PubkeyRegistrationParams has copy, drop {
        signature: Signature,
        pubkey_g1: PublicKeyWithPoP,
        pubkey_g2: PublicKeyWithPoP
    }

    struct BLSApkRegistryConfigs has key {
        signer_cap: SignerCapability,
    }

    public entry fun initialize() {
        if (is_initialized()) {
            return
        };

        // derive a resource account from signer to manage User share Account
        let operator_signer = &middleware_manager::get_signer();
        let (bls_apk_registry_signer, signer_cap) = account::create_resource_account(operator_signer, BLS_APK_REGISTRY_NAME);
        middleware_manager::add_address(string::utf8(BLS_APK_REGISTRY_NAME), signer::address_of(&bls_apk_registry_signer));
        move_to(&bls_apk_registry_signer, BLSApkRegistryConfigs {
            signer_cap,
        });
    }

    #[view]
    public fun is_initialized(): bool{
        middleware_manager::address_exists(string::utf8(BLS_APK_REGISTRY_NAME))
    }

    #[view]
    /// Return the address of the resource account that stores pool manager configs.
    public fun bls_apk_registry_address(): address {
      middleware_manager::get_address(string::utf8(BLS_APK_REGISTRY_NAME))
    }

    fun ensure_bls_apk_registry_store() acquires BLSApkRegistryConfigs{
        if(!exists<BLSApkRegistryStore>(bls_apk_registry_address())){
            create_bls_apk_registry_store();
        }
    }

    public fun create_bls_apk_registry_store() acquires BLSApkRegistryConfigs{
        let bls_apk_registry = bls_apk_registry_address();
        let bls_apk_registry_signer = bls_apk_registry_signer();
        move_to(bls_apk_registry_signer, BLSApkRegistryStore{
            operator_to_pk_hash: smart_table::new(),
            pk_hash_to_operator: smart_table::new(),
            operator_to_pk: smart_table::new(),
            apk_history: smart_table::new(),
            current_apk: smart_table::new()
        })
    }


    public(friend) fun initialize_quorum(quorum_number: u8) acquires BLSApkRegistryStore, BLSApkRegistryConfigs{
        ensure_bls_apk_registry_store();
        let store = bls_apk_registry_store_mut();
        assert!(!smart_table::contains(&store.apk_history, quorum_number), EQUORUM_ALREADY_EXIST);
        let apk_history: vector<ApkUpdate> = vector::empty();
        let now = timestamp::now_seconds();
        vector::push_back(&mut apk_history, ApkUpdate{
            aggregate_pubkeys: option::none(),
            update_timestamp: now,
            next_update_timestamp: 0,
        });
        smart_table::add(&mut store.apk_history, quorum_number, apk_history);
        smart_table::add(&mut store.current_apk, quorum_number, vector::empty());
    }

    public(friend) fun register_operator(operator: &signer, quorum_numbers: vector<u8>) acquires BLSApkRegistryStore {
        let operator_address = signer::address_of(operator);
        let store = bls_apk_registry_store();
        let pubkey = smart_table::borrow(&store.operator_to_pk, operator_address);

        update_quorum_apk(quorum_numbers, *pubkey, true)
    }

    public(friend) fun deregister_operator(operator: &signer, quorum_numbers: vector<u8>) acquires BLSApkRegistryStore {
        let operator_address = signer::address_of(operator);
        let store = bls_apk_registry_store();
        let pubkey = smart_table::borrow(&store.operator_to_pk, operator_address);

        update_quorum_apk(quorum_numbers, *pubkey, false)
    }

    public(friend) fun register_bls_pubkey(operator: &signer, params: PubkeyRegistrationParams, msg: vector<u8>): vector<u8> acquires BLSApkRegistryStore {
        let g1_bytes = public_key_with_pop_to_bytes(&params.pubkey_g1);
        assert!(vector::length(&g1_bytes) == 96, EINVALID_PUBKEY_G1);
        assert!(vector::length(&public_key_with_pop_to_bytes(&params.pubkey_g2)) == 96, EINVALID_PUBKEY_G2);
        let g1 = option::borrow(&crypto_algebra::deserialize<G1, FormatG1Uncompr>(&public_key_with_pop_to_bytes(&params.pubkey_g1)));
        let zero_g1 = crypto_algebra::zero<G1>();
        assert!(!crypto_algebra::eq(g1, &zero_g1), EZERO_PUBKEY);

        let store = bls_apk_registry_store();
        let operator_address = signer::address_of(operator);
        assert!(!smart_table::contains(&store.operator_to_pk_hash, operator_address), EOPERATOR_ALREADY_EXIST);
        assert!(!smart_table::contains(&store.pk_hash_to_operator, g1_bytes), EPUBKEY_ALREADY_EXIST);

        // TODO gamma and pairing

        let store_mut = bls_apk_registry_store_mut();
        smart_table::upsert(&mut store_mut.operator_to_pk, operator_address, params.pubkey_g1);
        smart_table::upsert(&mut store_mut.operator_to_pk_hash, operator_address, g1_bytes);
        smart_table::upsert(&mut store_mut.pk_hash_to_operator, g1_bytes, operator_address);
        
        // TODO emit event
        return g1_bytes
    }

    fun update_quorum_apk(quorum_numbers: vector<u8>, pubkey: PublicKeyWithPoP, register: bool) acquires BLSApkRegistryStore {
        let i = 0;
        while (i < vector::length(&quorum_numbers)) {
            let quorum_number = *vector::borrow(&quorum_numbers, i);
            let apk_history_length = vector::length(smart_table::borrow(&bls_apk_registry_store().apk_history, quorum_number));
            assert!(apk_history_length > 0, EQUORUM_DOES_NOT_EXIST);

            // Update pubkey
            let current_apk = current_apk_mut(quorum_number);
            if (register) {
                vector::push_back(current_apk, pubkey);
            } else {
                assert!(vector::contains(current_apk, &pubkey), EPUBKEY_NOT_EXIST);
                vector::remove_value(current_apk, &pubkey);
            };

            let borrow_new_apk = *current_apk;
            let new_aggr_pubkeys =  aggregate_pubkeys(borrow_new_apk);
            
            let latest_update = latest_apk_update_mut(quorum_number);
            let now = timestamp::now_seconds();
            if (latest_update.update_timestamp == now) {
                latest_update.aggregate_pubkeys = option::some(new_aggr_pubkeys);
            } else {
                latest_update.next_update_timestamp = now;
                let store_mut = bls_apk_registry_store_mut();
                let apk_history_mut = smart_table::borrow_mut(&mut store_mut.apk_history, quorum_number);
                vector::push_back(apk_history_mut, ApkUpdate{
                    aggregate_pubkeys: option::some(new_aggr_pubkeys),
                    update_timestamp: now,
                    next_update_timestamp: 0
                })
            };
            i = i + 1;
        }
    }

    #[view]
    public fun get_operator_id(operator: address): vector<u8> acquires BLSApkRegistryStore{
        let store = bls_apk_registry_store();
        let operator_id = smart_table::borrow(&store.operator_to_pk_hash, operator);
        return *operator_id
    }
    
    inline fun latest_apk_update_mut(quorum_number: u8): &mut ApkUpdate acquires BLSApkRegistryStore {
        let store_mut = bls_apk_registry_store_mut();
        let apk_history_length = vector::length(smart_table::borrow(&store_mut.apk_history, quorum_number));
        let apk_history = vector::borrow_mut(smart_table::borrow_mut(&mut store_mut.apk_history, quorum_number), apk_history_length - 1);
        apk_history
    }
    inline fun current_apk_mut(quorum_number: u8): &mut vector<PublicKeyWithPoP> acquires BLSApkRegistryStore {
        let store_mut = bls_apk_registry_store_mut();
        let current_apk_mut = smart_table::borrow_mut(&mut store_mut.current_apk, quorum_number);
        current_apk_mut
    }

    inline fun bls_apk_registry_store(): &BLSApkRegistryStore  acquires BLSApkRegistryStore {
        borrow_global<BLSApkRegistryStore>(bls_apk_registry_address())
    }

    inline fun bls_apk_registry_store_mut(): &mut BLSApkRegistryStore  acquires BLSApkRegistryStore {
        borrow_global_mut<BLSApkRegistryStore>(bls_apk_registry_address())
    }

    inline fun bls_apk_registry_signer(): &signer acquires BLSApkRegistryConfigs{
        &account::create_signer_with_capability(&borrow_global<BLSApkRegistryConfigs>(bls_apk_registry_address()).signer_cap)
    }
}