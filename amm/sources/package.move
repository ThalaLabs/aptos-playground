module amm::package {

    use std::signer;
    use aptos_framework::account;
    use aptos_framework::code;
    use aptos_framework::resource_account;

    // *************************************************************************
    // IMPORTANT                                                              //
    //                                                                        //
    // The resource address is derived from a combination of these two        //
    // constants. The combination must be unique and CANNOT be shared         //
    // across different projects. At least the seed must be changed           //
    //                                                                        //
    const DEPLOYER_ADDRESS: address = @amm_deployer;
    //
    const RESOURCE_ACCOUNT_SEED: vector<u8> = b"amm";
    //
    const RESOURCE_ACCOUNT_ADDRESS: address = @amm;                           //
    //                                                                        //
    //                                                                        //
    // *************************************************************************

    friend amm::pool;

    struct ResourceSignerCapability has key {
        signer_cap: account::SignerCapability,
    }

    ///
    /// Error Codes
    ///

    // Authorization
    const ERR_PACKAGE_UNAUTHORIZED: u64 = 0;

    // Initialization
    const ERR_PACKAGE_INITIALIZED: u64 = 1;
    const ERR_PACKAGE_UNINITIALIZED: u64 = 2;

    const ERR_PACKAGE_ADDRESS_MISMATCH: u64 = 3;

    ///
    /// Initialization
    ///

    // Invoked when package is published. We bootstrap the signer packer and claim ownership
    // of the SignerCapability right away
    fun init_module(resource_signer: &signer) {
        let resource_account_address = signer::address_of(resource_signer);
        assert!(!exists<ResourceSignerCapability>(resource_account_address), ERR_PACKAGE_INITIALIZED);

        // ensure the right templated variables are used. This also implicity ensures that `RESOURCE_ACCOUNT_ADDRESS != DEPLOYER_ADDRESS`
        // since there's no seed where `dervied_resource_account_address() == DEPLOYER_ADDRESS`.
        assert!(resource_account_address == derived_resource_account_address(), ERR_PACKAGE_ADDRESS_MISMATCH);
        assert!(resource_account_address == resource_account_address(), ERR_PACKAGE_ADDRESS_MISMATCH);

        let signer_cap = resource_account::retrieve_resource_account_cap(resource_signer, DEPLOYER_ADDRESS);
        move_to(resource_signer, ResourceSignerCapability { signer_cap });
    }

    ///
    /// Functions
    ///

    public(friend) fun resource_account_signer(): signer acquires ResourceSignerCapability {
        assert!(initialized(), ERR_PACKAGE_UNINITIALIZED);

        let resource_account_address = resource_account_address();
        let ResourceSignerCapability { signer_cap } = borrow_global<ResourceSignerCapability>(resource_account_address);
        account::create_signer_with_capability(signer_cap)
    }

    /// Entry point to publishing new or upgrading modules AFTER initialization, gated by the ThalaManager
    public entry fun publish_package(
        _account: &signer,
        metadata_serialized: vector<u8>,
        code: vector<vector<u8>>
    ) acquires ResourceSignerCapability {
        // TODO: gate this with manager access
        // assert!(manager::is_manager(account), ERR_PACKAGE_UNAUTHORIZED);

        let resource_account_signer = resource_account_signer();
        code::publish_package_txn(&resource_account_signer, metadata_serialized, code);
    }

    // Public Getters

    public fun initialized(): bool {
        exists<ResourceSignerCapability>(resource_account_address())
    }

    public fun resource_account_deployer_address(): address {
        DEPLOYER_ADDRESS
    }

    public fun resource_account_address(): address {
        // We don't call `derived_resource_account_address` to save on the sha3 call. `init_module` that's called on deployment
        // already ensures that `RESOURCE_ACCOUNT_ADDRESS == derived_resource_account_address()`.
        RESOURCE_ACCOUNT_ADDRESS
    }

    // Internal Helpers

    fun derived_resource_account_address(): address {
        account::create_resource_address(&DEPLOYER_ADDRESS, RESOURCE_ACCOUNT_SEED)
    }
}
