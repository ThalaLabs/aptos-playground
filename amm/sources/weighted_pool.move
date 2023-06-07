module amm::weighted_pool {
    use std::option;
    use std::string::{Self, String};
    use std::vector;

    use aptos_std::string_utils;
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::fungible_asset::{Self, Metadata, MintRef, BurnRef, FungibleAsset, FungibleStore};
    use aptos_framework::object::{Self, Object, ExtendRef};
    use aptos_framework::primary_fungible_store;

    use amm::weighted_math;

    const RESOURCE_ACCOUNT_ADDRESS: address = @amm;
    const DEPLOYER_ADDRESS: address = @deployer;
    const RESOURCE_ACCOUNT_SEED: vector<u8> = b"amm";

    struct SignerCapBox has key {
        signer_cap: SignerCapability
    }

    struct Pool has key {
        stores: vector<Object<FungibleStore>>,
        weights: vector<u64>,

        extend_ref: ExtendRef,
        lp_token_mint_ref: MintRef,
        lp_token_burn_ref: BurnRef
    }

    /// Returns (pool object, lp token)
    public fun create_pool(
        assets: vector<FungibleAsset>,
        weights: vector<u64>
    ): (Object<Pool>, FungibleAsset) acquires SignerCapBox {
        // TODO: check assets order
        let initial_lp_amount = {
            let balances = vector::map_ref<FungibleAsset, u64>(&assets, |fa| fungible_asset::amount(fa));
            weighted_math::compute_invariant_weights_u64(&balances, &weights)
        };

        let constructor_ref = {
            let metadata = vector::map_ref<FungibleAsset, Object<Metadata>>(
                &assets,
                |asset| fungible_asset::metadata_from_asset(asset)
            );
            object::create_named_object(&resource_account_signer(), *string::bytes(&pool_name(&metadata, &weights)))
        };
        let pool_signer = object::generate_signer(&constructor_ref);
        let extend_ref = object::generate_extend_ref(&constructor_ref);

        let stores = {
            let stores = vector::empty<Object<FungibleStore>>();
            let i = 0;
            let n = vector::length(&assets);
            while (i < n) {
                let asset = extract_all_fungible_asset(vector::borrow_mut<FungibleAsset>(&mut assets, i));
                let store = fungible_asset::create_store(&constructor_ref, fungible_asset::metadata_from_asset(&asset));
                fungible_asset::deposit(store, asset);
                i = i + 1;
            };
            stores
        };
        vector::destroy(assets, |asset| fungible_asset::destroy_zero(asset));

        let (lp_token_mint_ref, lp_token_burn_ref) = {
            let constructor_ref = object::create_named_object(&pool_signer, b"lp_token");
            primary_fungible_store::create_primary_store_enabled_fungible_asset(
                &constructor_ref,
                option::none(),
                string::utf8(b"Thala LP Token"),
                string::utf8(b"THALA-LP"),
                8,
                string::utf8(b""),
                string::utf8(b"")
            );
            (
                fungible_asset::generate_mint_ref(&constructor_ref),
                fungible_asset::generate_burn_ref(&constructor_ref)
            )
        };
        let lp_token = fungible_asset::mint(&lp_token_mint_ref, initial_lp_amount);
        move_to(&pool_signer, Pool {
            stores,
            weights,
            extend_ref,
            lp_token_mint_ref,
            lp_token_burn_ref
        });

        let pool_obj = object::object_from_constructor_ref<Pool>(&constructor_ref);
        (pool_obj, lp_token)
    }

    /// Returns (lp token, refunds)
    public fun add_liquidity(
        pool_obj: Object<Pool>,
        assets: vector<FungibleAsset>
    ): (FungibleAsset, vector<FungibleAsset>) acquires Pool {
        // TODO: check pool exists
        // TODO: check assets order
        let pool = borrow_global<Pool>(object::object_address(&pool_obj));

        let (mint_lp_amount, refund_amounts) = {
            let balances = vector::map_ref<Object<FungibleStore>, u64>(
                &pool.stores,
                |store| fungible_asset::balance(*store)
            );
            let deposits = vector::map_ref<FungibleAsset, u64>(&assets, |fa| fungible_asset::amount(fa));
            let lp_supply = {
                let supply = fungible_asset::supply(fungible_asset::mint_ref_metadata(&pool.lp_token_mint_ref));
                (option::extract(&mut supply) as u64)
            };
            weighted_math::compute_pool_tokens_issued(&deposits, &balances, lp_supply)
        };
        let lp_token = fungible_asset::mint(&pool.lp_token_mint_ref, mint_lp_amount);

        let refunds = {
            let a = vector::empty<FungibleAsset>();
            let i = 0;
            let n = vector::length(&assets);
            while (i < n) {
                vector::push_back(
                    &mut a,
                    fungible_asset::extract(vector::borrow_mut(&mut assets, i), *vector::borrow(&refund_amounts, i))
                );
                i = i + 1;
            };
            a
        };

        {
            let i = 0;
            let n = vector::length(&assets);
            while (i < n) {
                let store = *vector::borrow(&pool.stores, i);
                let asset = extract_all_fungible_asset(vector::borrow_mut(&mut assets, i));
                fungible_asset::deposit(store, asset);

                i = i + 1;
            };
        };

        vector::destroy(assets, |asset| fungible_asset::destroy_zero(asset));
        (lp_token, refunds)
    }

    // TODO: remove_liquidity

    // TODO: add swap fee
    public fun swap_exact_in(
        pool_obj: Object<Pool>,
        asset_in: FungibleAsset,
        asset_out: Object<Metadata>
    ): FungibleAsset acquires Pool {
        // TODO: check pool exists
        // TODO: check asset_in and asset_out
        let pool = borrow_global<Pool>(object::object_address(&pool_obj));
        let balances = vector::map_ref<Object<FungibleStore>, u64>(
            &pool.stores,
            |store| fungible_asset::balance(*store)
        );
        let (store_in, idx_in) = {
            let i = 0;
            let store = *vector::borrow(&pool.stores, i);
            let n = vector::length(&pool.stores);
            while (i < n) {
                store = *vector::borrow(&pool.stores, i);
                if (fungible_asset::store_metadata(store) == fungible_asset::metadata_from_asset(&asset_in)) {
                    break
                };
                i = i + 1;
            };
            // TODO: errcode
            assert!(i < n, 0);
            (store, i)
        };
        let (store_out, idx_out) = {
            let i = 0;
            let store = *vector::borrow(&pool.stores, i);
            let n = vector::length(&pool.stores);

            while (i < n) {
                store = *vector::borrow(&pool.stores, i);
                if (fungible_asset::store_metadata(store) == asset_out) {
                    break
                };
                i = i + 1;
            };
            // TODO: errcode
            assert!(i < n, 0);
            (store, i)
        };
        let amount_in = fungible_asset::amount(&asset_in);
        let amount_out = weighted_math::calc_out_given_in_weights_u64(
            idx_in,
            idx_out,
            amount_in,
            &balances,
            &pool.weights
        );

        fungible_asset::deposit(store_in, asset_in);
        fungible_asset::withdraw(&object::generate_signer_for_extending(&pool.extend_ref), store_out, amount_out)
    }

    #[view]
    public fun resource_account_address(): address {
        RESOURCE_ACCOUNT_ADDRESS
    }

    fun resource_account_signer(): signer acquires SignerCapBox {
        let signer_cap_box = borrow_global<SignerCapBox>(resource_account_address());
        account::create_signer_with_capability(&signer_cap_box.signer_cap)
    }

    fun pool_name(assets: &vector<Object<Metadata>>, weights: &vector<u64>): String {
        let name = &mut string::utf8(b"");
        let i = 0;
        let n = vector::length(weights);
        while (i < n) {
            string::append(name, fungible_asset::symbol(*vector::borrow(assets, i)));
            string::append_utf8(name, b"-");
            string::append(name, string_utils::to_string(vector::borrow(weights, i)));
            if (i < n - 1) {
                string::append_utf8(name, b"-");
            };

            i = i + 1;
        };
        *name
    }

    fun extract_all_fungible_asset(fa: &mut FungibleAsset): FungibleAsset {
        let amount = fungible_asset::amount(fa);
        fungible_asset::extract(fa, amount)
    }
}
