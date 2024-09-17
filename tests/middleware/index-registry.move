#[test_only]
module middleware::index_registry_tests {

    use std::signer;
    use std::string;
    use std::vector;

    use middleware::index_registry;
    use middleware::middleware_test_helpers;


    #[test(deployer = @0xcafe, staker = @0xab12, middleware=@0xabcfff)]
    public fun test_init_quorum(deployer: &signer, middleware: &signer, staker: &signer) {
        middleware_test_helpers::middleware_set_up(deployer, middleware);

        let next_quorum = 0;
        index_registry::create_index_registry_store();
        index_registry::initialize_quorum(next_quorum);

        assert!(vector::length(&index_registry::count_history(next_quorum)) == 1, 1);
    }

    #[test(deployer = @0xcafe, staker = @0xab12, middleware=@0xabcfff)]
    public fun test_register_operator(deployer: &signer, middleware: &signer, staker: &signer) {
        middleware_test_helpers::middleware_set_up(deployer, middleware);

        let next_quorum = 0;
        index_registry::create_index_registry_store();
        index_registry::initialize_quorum(next_quorum);

        assert!(vector::length(&index_registry::count_history(next_quorum)) == 1, 1);

        index_registry::register_operator(string::utf8(b"operator 1"), vector::singleton(next_quorum));
    }

    #[test(deployer = @0xcafe, staker = @0xab12, middleware=@0xabcfff)]
    public fun test_deregister_operator(deployer: &signer, middleware: &signer, staker: &signer) {
        middleware_test_helpers::middleware_set_up(deployer, middleware);

        let next_quorum = 0;
        index_registry::create_index_registry_store();
        index_registry::initialize_quorum(next_quorum);

        assert!(vector::length(&index_registry::count_history(next_quorum)) == 1, 1);

        index_registry::register_operator(string::utf8(b"operator 1"), vector::singleton(next_quorum));
        index_registry::deregister_operator(string::utf8(b"operator 1"), vector::singleton(next_quorum));
    }
}