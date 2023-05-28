module playground::ctoken {
    use std::signer;
    use std::string::String;

    use aptos_framework::fungible_asset::{FungibleAsset, Metadata, MintRef, TransferRef, BurnRef};
    use aptos_framework::object::{Self, Object};

    use playground::coin_v2;

    #[test_only]
    use aptos_framework::account;
    #[test_only]
    use aptos_framework::fungible_asset;
    #[test_only]
    use std::string;

    const ERR_CTOKEN_UNAUTHORIZED: u64 = 1;

    struct AdminRefs has key {
        mint_ref: MintRef,
        transfer_ref: TransferRef,
        burn_ref: BurnRef
    }

    public fun initialize(
        account: &signer,
        object_seed: vector<u8>,
        name: String,
        symbol: String,
        decimals: u8
    ): Object<Metadata> {
        let (metadata_object_signer, mint_ref, transfer_ref, burn_ref, metadata) = coin_v2::initialize(
            account,
            object_seed,
            name,
            symbol,
            decimals
        );
        move_to(&metadata_object_signer, AdminRefs {
            mint_ref,
            transfer_ref,
            burn_ref
        });
        metadata
    }

    // admin functions

    public fun mint(admin: &signer, asset: Object<Metadata>, amount: u64): FungibleAsset acquires AdminRefs {
        let mint_ref = &borrow_admin_refs(admin, asset).mint_ref;
        coin_v2::mint(mint_ref, amount)
    }

    public fun burn(admin: &signer, asset: Object<Metadata>, fa: FungibleAsset) acquires AdminRefs {
        let burn_ref = &borrow_admin_refs(admin, asset).burn_ref;
        coin_v2::burn(burn_ref, fa)
    }

    public fun admin_deposit(
        admin: &signer,
        asset: Object<Metadata>,
        to: address,
        fa: FungibleAsset
    ) acquires AdminRefs {
        let transfer_ref = &borrow_admin_refs(admin, asset).transfer_ref;
        coin_v2::deposit(transfer_ref, asset, to, fa)
    }

    public fun admin_withdraw(
        admin: &signer,
        asset: Object<Metadata>,
        from: address,
        amount: u64
    ): FungibleAsset acquires AdminRefs {
        let transfer_ref = &borrow_admin_refs(admin, asset).transfer_ref;
        coin_v2::withdraw(transfer_ref, asset, from, amount)
    }

    public fun admin_transfer(
        admin: &signer,
        asset: Object<Metadata>,
        from: address,
        to: address,
        amount: u64
    ) acquires AdminRefs {
        let fa = admin_withdraw(admin, asset, from, amount);
        admin_deposit(admin, asset, to, fa)
    }

    // should also allow non-admin users to deposit/withdraw/transfer with their own accounts

    public fun deposit(asset: Object<Metadata>, to: address, fa: FungibleAsset) acquires AdminRefs {
        let transfer_ref = borrow_transfer_ref(asset);
        coin_v2::deposit(transfer_ref, asset, to, fa)
    }

    public fun withdraw(
        asset: Object<Metadata>,
        from: address,
        amount: u64
    ): FungibleAsset acquires AdminRefs {
        let transfer_ref = borrow_transfer_ref(asset);
        coin_v2::withdraw(transfer_ref, asset, from, amount)
    }

    public fun transfer(account: &signer, asset: Object<Metadata>, to: address, amount: u64) acquires AdminRefs {
        let transfer_ref = borrow_transfer_ref(asset);
        coin_v2::transfer(transfer_ref, asset, signer::address_of(account), to, amount)
    }

    // helpers

    inline fun borrow_admin_refs(
        owner: &signer,
        asset: Object<Metadata>,
    ): &AdminRefs acquires AdminRefs {
        assert!(object::is_owner(asset, signer::address_of(owner)), ERR_CTOKEN_UNAUTHORIZED);
        borrow_global<AdminRefs>(object::object_address(&asset))
    }

    inline fun borrow_transfer_ref(asset: Object<Metadata>): &TransferRef {
        &borrow_global<AdminRefs>(object::object_address(&asset)).transfer_ref
    }

    #[test]
    fun non_admin_e2e_ok() acquires AdminRefs {
        let issuer = account::create_account_for_test(@0xBEEF);
        let alice = account::create_account_for_test(@0xA);
        let bob = account::create_account_for_test(@0xB);

        let metadata = initialize(
            &issuer,
            b"TC",
            string::utf8(b"Test Coin"),
            string::utf8(b"TC"),
            8
        );

        let fa = mint(&issuer, metadata, 10000);
        deposit(metadata, signer::address_of(&alice), fa);
        assert!(coin_v2::balance(metadata, signer::address_of(&alice)) == 10000, 0);

        transfer(&alice, metadata, signer::address_of(&bob), 10000);
        assert!(coin_v2::balance(metadata, signer::address_of(&bob)) == 10000, 0);

        let fa = withdraw(metadata, signer::address_of(&bob), 10000);
        assert!(fungible_asset::amount(&fa) == 10000, 0);

        burn(&issuer, metadata, fa);
    }

    #[test]
    fun admin_e2e_ok() acquires AdminRefs {
        let issuer = account::create_account_for_test(@0xBEEF);
        let alice = account::create_account_for_test(@0xA);
        let bob = account::create_account_for_test(@0xB);

        let metadata = initialize(
            &issuer,
            b"TC",
            string::utf8(b"Test Coin"),
            string::utf8(b"TC"),
            8
        );

        let fa = mint(&issuer, metadata, 10000);
        admin_deposit(&issuer, metadata, signer::address_of(&alice), fa);
        assert!(coin_v2::balance(metadata, signer::address_of(&alice)) == 10000, 0);

        // transfer funds from alice to bob without alice's signature!
        admin_transfer(&issuer, metadata, signer::address_of(&alice), signer::address_of(&bob), 10000);
        assert!(coin_v2::balance(metadata, signer::address_of(&bob)) == 10000, 0);

        let fa = admin_withdraw(&issuer, metadata, signer::address_of(&bob), 10000);
        assert!(fungible_asset::amount(&fa) == 10000, 0);

        burn(&issuer, metadata, fa);
    }
}
