/// Anyone can call this module to permissionlessly wrap a v1 coin into a v2 coin, and unwrap vice versa.
module fungible_asset_wrapper::fungible_asset_wrapper {
    use std::option;
    use std::signer;
    use std::string;

    use aptos_std::type_info;
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::fungible_asset::{Self, FungibleAsset, MintRef, BurnRef};
    use aptos_framework::object;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::resource_account;

    #[test_only]
    use aptos_framework::coin::{MintCapability, BurnCapability};
    #[test_only]
    use aptos_framework::fungible_asset::Metadata;

    const RESOURCE_ACCOUNT_ADDRESS: address = @fungible_asset_wrapper;
    const DEPLOYER_ADDRESS: address = @deployer;
    const RESOURCE_ACCOUNT_SEED: vector<u8> = b"fungible_asset_wrapper";

    struct SignerCapBox has key {
        signer_cap: SignerCapability
    }

    struct FungibleAssetAdmin has key {
        mint_ref: MintRef,
        burn_ref: BurnRef
    }

    fun init_module(resource_signer: &signer) {
        let signer_cap = resource_account::retrieve_resource_account_cap(resource_signer, DEPLOYER_ADDRESS);
        move_to(resource_signer, SignerCapBox { signer_cap });
    }

    public entry fun register<CoinType>() acquires SignerCapBox {
        let resource_account_signer = resource_account_signer();
        let constructor_ref = object::create_named_object(
            &resource_account_signer,
            *string::bytes(&type_info::type_name<CoinType>())
        );
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &constructor_ref,
            option::none(),
            coin::name<CoinType>(),
            coin::symbol<CoinType>(),
            coin::decimals<CoinType>(),
            string::utf8(b""),
            string::utf8(b""),
        );
        move_to(
            &object::generate_signer(&constructor_ref),
            FungibleAssetAdmin {
                mint_ref: fungible_asset::generate_mint_ref(&constructor_ref),
                burn_ref: fungible_asset::generate_burn_ref(&constructor_ref)
            }
        );
        if (!coin::is_account_registered<CoinType>(signer::address_of(&resource_account_signer))) {
            coin::register<CoinType>(&resource_account_signer);
        }
    }

    public fun wrap<CoinType>(coin: Coin<CoinType>): FungibleAsset acquires FungibleAssetAdmin {
        let amount = coin::value(&coin);
        let coin_address = coin_address<CoinType>();
        let fa_admin = borrow_global<FungibleAssetAdmin>(coin_address);
        coin::deposit(resource_account_address(), coin);
        fungible_asset::mint(&fa_admin.mint_ref, amount)
    }

    public fun unwrap<CoinType>(fa: FungibleAsset): Coin<CoinType> acquires FungibleAssetAdmin, SignerCapBox {
        let amount = fungible_asset::amount(&fa);
        let coin_address = coin_address<CoinType>();
        let fa_admin = borrow_global<FungibleAssetAdmin>(coin_address);
        fungible_asset::burn(&fa_admin.burn_ref, fa);
        coin::withdraw(&resource_account_signer(), amount)
    }

    #[view]
    public fun coin_address<CoinType>(): address {
        let type_name = type_info::type_name<CoinType>();
        object::create_object_address(&resource_account_address(), *string::bytes(&type_name))
    }

    #[view]
    public fun resource_account_address(): address {
        RESOURCE_ACCOUNT_ADDRESS
    }

    fun resource_account_signer(): signer acquires SignerCapBox {
        let signer_cap_box = borrow_global<SignerCapBox>(resource_account_address());
        account::create_signer_with_capability(&signer_cap_box.signer_cap)
    }

    #[test_only]
    struct TestCoin {}

    #[test_only]
    fun test_init_resource_account() {
        // Zero auth key
        let auth_key = x"0000000000000000000000000000000000000000000000000000000000000000";

        // Setup the generated resource account with the SignerCapability ready to be claimed
        let deployer_account = account::create_signer_for_test(DEPLOYER_ADDRESS);
        resource_account::create_resource_account(&deployer_account, RESOURCE_ACCOUNT_SEED, auth_key);

        // Init the module with the expected resource address
        let resource_account = account::create_signer_for_test(RESOURCE_ACCOUNT_ADDRESS);
        init_module(&resource_account);
    }

    #[test_only]
    fun test_init_coin(): (MintCapability<TestCoin>, BurnCapability<TestCoin>) {
        let issuer = account::create_account_for_test(@fungible_asset_wrapper);
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<TestCoin>(
            &issuer,
            string::utf8(b"Test Coin"),
            string::utf8(b"TC"),
            8,
            true
        );
        coin::destroy_freeze_cap(freeze_cap);
        (mint_cap, burn_cap)
    }

    #[test]
    fun test_init_module() {
        test_init_resource_account();
        assert!(exists<SignerCapBox>(resource_account_address()), 0);
    }

    #[test]
    fun test_register() acquires SignerCapBox {
        let (mint_cap, burn_cap) = test_init_coin();
        test_init_resource_account();
        register<TestCoin>();

        let coin_address = coin_address<TestCoin>();
        assert!(exists<FungibleAssetAdmin>(coin_address), 0);

        let asset = object::address_to_object<Metadata>(coin_address);
        assert!(fungible_asset::name(asset) == string::utf8(b"Test Coin"), 0);
        assert!(fungible_asset::symbol(asset) == string::utf8(b"TC"), 0);
        assert!(fungible_asset::decimals(asset) == 8, 0);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test]
    fun test_wrap_unwrap() acquires SignerCapBox, FungibleAssetAdmin {
        let (mint_cap, burn_cap) = test_init_coin();
        test_init_resource_account();
        register<TestCoin>();

        let wrapped = wrap(coin::mint(10000000000, &mint_cap));
        assert!(fungible_asset::amount(&wrapped) == 10000000000, 0);

        let unwrapped = unwrap<TestCoin>(wrapped);
        assert!(coin::value(&unwrapped) == 10000000000, 0);

        coin::burn(unwrapped, &burn_cap);
        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }
}
