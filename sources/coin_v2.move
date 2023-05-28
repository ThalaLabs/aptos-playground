/// Implement 0x1::coin using 0x1::fungible_asset
module playground::coin_v2 {

    use std::option;
    use std::string::{Self, String};

    use aptos_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, Metadata, FungibleAsset};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;

    #[test_only]
    use aptos_framework::account;
    #[test_only]
    use std::signer;

    public fun initialize(
        account: &signer,
        object_seed: vector<u8>,
        name: String,
        symbol: String,
        decimals: u8
    ): (signer, MintRef, TransferRef, BurnRef, Object<Metadata>) {
        let constructor_ref = &object::create_named_object(account, object_seed);
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructor_ref,
            option::none(),
            name,
            symbol,
            decimals,
            string::utf8(b"http://example.com/favicon.ico"),
            string::utf8(b"http://example.com"),
        );

        let mint_ref = fungible_asset::generate_mint_ref(constructor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(constructor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(constructor_ref);
        let metadata_object_signer = object::generate_signer(constructor_ref);
        let metadata = object::address_to_object<Metadata>(object::address_from_constructor_ref(constructor_ref));
        (metadata_object_signer, mint_ref, transfer_ref, burn_ref, metadata)
    }

    public fun mint(ref: &MintRef, amount: u64): FungibleAsset {
        fungible_asset::mint(ref, amount)
    }

    public fun burn(ref: &BurnRef, fa: FungibleAsset) {
        fungible_asset::burn(ref, fa)
    }

    public fun deposit(ref: &TransferRef, asset: Object<Metadata>, to: address, fa: FungibleAsset) {
        let store = primary_fungible_store::ensure_primary_store_exists(to, asset);
        fungible_asset::deposit_with_ref(ref, store, fa)
    }

    public fun withdraw(ref: &TransferRef, asset: Object<Metadata>, from: address, amount: u64): FungibleAsset {
        let store = primary_fungible_store::ensure_primary_store_exists(from, asset);
        fungible_asset::withdraw_with_ref(ref, store, amount)
    }

    public fun transfer(ref: &TransferRef, asset: Object<Metadata>, from: address, to: address, amount: u64) {
        let fa = withdraw(ref, asset, from, amount);
        deposit(ref, asset, to, fa);
    }

    #[view]
    public fun balance(asset: Object<Metadata>, owner: address): u64 {
        let store = primary_fungible_store::ensure_primary_store_exists(owner, asset);
        fungible_asset::balance(store)
    }

    #[test]
    fun e2e_ok() {
        let issuer = account::create_account_for_test(@0xBEEF);
        let alice = account::create_account_for_test(@0xA);
        let bob = account::create_account_for_test(@0xB);

        let (_, mint_ref, transfer_ref, burn_ref, metadata) = initialize(
            &issuer,
            b"TC",
            string::utf8(b"Test Coin"),
            string::utf8(b"TC"),
            8
        );

        let fa = mint(&mint_ref, 10000);
        deposit(&transfer_ref, metadata, signer::address_of(&alice), fa);
        assert!(balance(metadata, signer::address_of(&alice)) == 10000, 0);

        transfer(&transfer_ref, metadata, signer::address_of(&alice), signer::address_of(&bob), 10000);
        assert!(balance(metadata, signer::address_of(&bob)) == 10000, 0);

        let fa = withdraw(&transfer_ref, metadata, signer::address_of(&bob), 10000);
        assert!(fungible_asset::amount(&fa) == 10000, 0);

        burn(&burn_ref, fa);
    }
}
