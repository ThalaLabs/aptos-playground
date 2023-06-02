/// User can deposit/withdraw multiple fungible assets to/from different markets
module playground::vault {
    use std::signer;
    use std::string;

    use aptos_std::table::{Self, Table};
    use aptos_framework::fungible_asset::{Self, FungibleAsset, Metadata};
    use aptos_framework::object::{Self, Object};

    #[test_only]
    use aptos_framework::account;
    #[test_only]
    use aptos_framework::fungible_asset::{MintRef, TransferRef, BurnRef};
    #[test_only]
    use aptos_framework::primary_fungible_store;
    #[test_only]
    use std::option;

    const ERR_UNAUTHORIZED: u64 = 1;
    const ERR_INSUFFICIENT_FUNDS: u64 = 2;

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct Market has key {}

    /// Balance keeps track of user assets in different markets
    struct User has key {
        markets: Table<Object<Market>, u64>
    }

    public fun init_market(admin: &signer, asset: Object<Metadata>): Object<Market> {
        assert!(signer::address_of(admin) == @playground, ERR_UNAUTHORIZED);

        let asset_name = fungible_asset::name(asset);
        let constructor_ref = &object::create_named_object(admin, *string::bytes(&asset_name));
        fungible_asset::create_store(constructor_ref, asset);

        let obj_signer = object::generate_signer(constructor_ref);
        move_to(&obj_signer, Market {});
        object::address_to_object<Market>(object::address_from_constructor_ref(constructor_ref))
    }

    /// Deposit fungible asset to a market
    public fun deposit(account: &signer, market_obj: Object<Market>, fa: FungibleAsset) acquires User {
        let amount = fungible_asset::amount(&fa);
        fungible_asset::deposit(market_obj, fa);

        if (!exists<User>(signer::address_of(account))) {
            move_to(account, User {
                markets: table::new()
            });
        };
        let user = borrow_global_mut<User>(signer::address_of(account));
        let balance = table::borrow_mut_with_default(&mut user.markets, market_obj, 0);
        *balance = *balance + amount;
    }

    // public fun withdraw(
    //     account: &signer,
    //     market_obj: Object<Market>,
    //     amount: u64
    // ): FungibleAsset acquires User, Market {
    //     let market = borrow_global<Market>(object::object_address(&market_obj));
    //     let fa = fungible_asset::withdraw_with_ref(&market.transfer_ref, market_obj, amount);
    //
    //     let user = borrow_global_mut<User>(signer::address_of(account));
    //     let balance = table::borrow_mut_with_default(&mut user.markets, market_obj, 0);
    //
    //     assert!(amount <= *balance, ERR_INSUFFICIENT_FUNDS);
    //     *balance = *balance - amount;
    //
    //     fa
    // }

    #[view]
    public fun balance(account_addr: address, market_obj: Object<Market>): u64 acquires User {
        let user = borrow_global<User>(account_addr);
        *table::borrow_with_default(&user.markets, market_obj, &0)
    }

    #[test_only]
    fun init_fa(issuer: &signer, fa_name: vector<u8>): (MintRef, TransferRef, BurnRef, Object<Metadata>) {
        let constructor_ref = &object::create_named_object(issuer, fa_name);
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructor_ref,
            option::none(),
            string::utf8(fa_name),
            string::utf8(b"TFA"),
            8,
            string::utf8(b"http://example.com/favicon.ico"),
            string::utf8(b"http://example.com"),
        );
        let mint_ref = fungible_asset::generate_mint_ref(constructor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(constructor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(constructor_ref);
        let metadata = object::address_to_object<Metadata>(object::address_from_constructor_ref(constructor_ref));

        (mint_ref, transfer_ref, burn_ref, metadata)
    }

    #[test(admin = @playground)]
    fun e2e_ok(admin: &signer) acquires User {
        let fa_issuer = account::create_account_for_test(@0xA);
        let (mint_ref, _, _, asset) = init_fa(&fa_issuer, b"Test Fungible Asset");

        let market_obj = init_market(admin, asset);
        assert!(fungible_asset::balance(market_obj) == 0, 0);

        let user = account::create_account_for_test(@0xB);
        deposit(&user, market_obj, fungible_asset::mint(&mint_ref, 100));
        assert!(balance(signer::address_of(&user), market_obj) == 100, 0);
        assert!(fungible_asset::balance(market_obj) == 100, 0);
    }
}
