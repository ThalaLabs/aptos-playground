module amm::pool {
    use std::option;
    use std::string;
    use std::vector;
    use aptos_std::math64;
    use aptos_framework::fungible_asset::{Self, BurnRef, FungibleAsset, FungibleStore, Metadata, MintRef, TransferRef};
    use aptos_framework::object::{Self, ExtendRef, Object};
    use aptos_framework::primary_fungible_store;

    use amm::package;
    use amm::stable_math;
    use amm::weighted_math;

    const LP_TOKEN_DECIMALS: u8 = 8;

    const ERR_POOL_NOT_FOUND: u64 = 1;

    struct Pool has key {
        stores: vector<Object<FungibleStore>>,

        swap_fee_bps: u64,

        extend_ref: ExtendRef,
        lp_token_mint_ref: MintRef,
        lp_token_transfer_ref: TransferRef,
        lp_token_burn_ref: BurnRef
    }

    struct WeightedPool has key {
        weights: vector<u64>,
    }

    struct StablePool has key {
        amp_factor: u64,
        precision_multipliers: vector<u64>,
    }

    public fun create_pool_weighted(
        assets: vector<FungibleAsset>,
        swap_fee_bps: u64,
        weights: vector<u64>,
    ): (Object<Pool>, FungibleAsset) {
        // TODO: check assets order
        let balances = vector::map_ref<FungibleAsset, u64>(&assets, |fa| fungible_asset::amount(fa));
        let initial_lp_amount = weighted_math::compute_invariant_weights_u64(&balances, &weights);
        let (pool_signer, pool_obj, lp_token) = create_pool(assets, swap_fee_bps, initial_lp_amount);
        move_to(&pool_signer, WeightedPool {
            weights
        });
        (pool_obj, lp_token)
    }

    public fun create_pool_stable(
        assets: vector<FungibleAsset>,
        swap_fee_bps: u64,
        amp_factor: u64,
    ): (Object<Pool>, FungibleAsset) {
        // TODO: check assets order
        let balances = vector::map_ref<FungibleAsset, u64>(&assets, |fa| fungible_asset::amount(fa));
        // TODO: IMPLEMENT ME
        let precision_multipliers = vector<u64>[];
        let initial_lp_amount = (stable_math::compute_invariant(
            stable_math::get_xp(balances, precision_multipliers),
            amp_factor
        ) as u64);
        let (pool_signer, pool_obj, lp_token) = create_pool(assets, swap_fee_bps, initial_lp_amount);
        move_to(&pool_signer, StablePool {
            amp_factor,
            precision_multipliers
        });
        (pool_obj, lp_token)
    }

    public fun add_liquidity_weighted(
        pool_obj: Object<Pool>,
        assets: vector<FungibleAsset>
    ): (FungibleAsset, vector<FungibleAsset>) acquires Pool {
        let pool_addr = object::object_address(&pool_obj);
        assert!(object::object_exists<Pool>(pool_addr), ERR_POOL_NOT_FOUND);

        // TODO: check assets order
        // TODO: check pool matches assets
        let pool = borrow_global<Pool>(pool_addr);

        let (mint_lp_amount, refund_amounts) = {
            let deposits = vector::map_ref<FungibleAsset, u64>(&assets, |asset| fungible_asset::amount(asset));
            weighted_math::compute_pool_tokens_issued(&deposits, &balances(pool), lp_supply(pool))
        };
        let lp_token = fungible_asset::mint(&pool.lp_token_mint_ref, mint_lp_amount);

        let (remains, refunds) = extract_multi(assets, refund_amounts);
        vector::zip(pool.stores, remains, |store, asset| fungible_asset::deposit(store, asset));

        (lp_token, refunds)
    }

    public fun add_liquidity_stable(
        pool_obj: Object<Pool>,
        assets: vector<FungibleAsset>
    ): FungibleAsset acquires Pool, StablePool {
        // TODO: check assets order
        let pool_addr = object::object_address(&pool_obj);
        assert!(object::object_exists<Pool>(pool_addr), ERR_POOL_NOT_FOUND);

        let pool = borrow_global<Pool>(pool_addr);
        let stable_pool = borrow_global<StablePool>(pool_addr);
        let prev_inv = stable_math::compute_invariant(
            stable_math::get_xp(balances(pool), stable_pool.precision_multipliers),
            stable_pool.amp_factor
        );
        vector::zip(pool.stores, assets, |store, asset| fungible_asset::deposit(store, asset));
        let inv = stable_math::compute_invariant(
            stable_math::get_xp(balances(pool), stable_pool.precision_multipliers),
            stable_pool.amp_factor
        );
        // TODO: errcode
        assert!(inv > prev_inv, 0);

        let lp_supply = lp_supply(pool);
        let mint_lp_amount = (((lp_supply as u256) * (inv - prev_inv) / prev_inv) as u64);
        let lp_token = fungible_asset::mint(&pool.lp_token_mint_ref, mint_lp_amount);
        lp_token
    }

    public fun remove_liquidity(
        pool_obj: Object<Pool>,
        lp_token: FungibleAsset,
    ): vector<FungibleAsset> acquires Pool {
        let pool_addr = object::object_address(&pool_obj);
        assert!(object::object_exists<Pool>(pool_addr), ERR_POOL_NOT_FOUND);

        let lp_token_amount = fungible_asset::amount(&lp_token);

        // TODO: check pool matches lp_token
        let pool = borrow_global<Pool>(pool_addr);
        fungible_asset::burn(&pool.lp_token_burn_ref, lp_token);

        let pool_signer = pool_signer(pool);
        let lp_supply = lp_supply(pool);
        let balances = balances(pool);
        let withdraws = vector::map_ref<u64, u64>(
            &balances,
            |balance| math64::mul_div(*balance, lp_token_amount, lp_supply)
        );
        let refunds = vector::zip_map(
            withdraws,
            pool.stores,
            |withdraw, store| fungible_asset::withdraw(&pool_signer, store, withdraw)
        );
        refunds
    }

    // TODO: add swap fee
    public fun swap_exact_in_weighted(
        pool_obj: Object<Pool>,
        asset_in: FungibleAsset,
        asset_metadata_out: Object<Metadata>
    ): FungibleAsset acquires Pool, WeightedPool {
        // TODO: check asset_in and asset_out
        let pool_addr = object::object_address(&pool_obj);
        assert!(object::object_exists<Pool>(pool_addr), ERR_POOL_NOT_FOUND);

        let pool = borrow_global<Pool>(pool_addr);
        let weighted_pool = borrow_global<WeightedPool>(pool_addr);

        let (idx_in, store_in) = store(pool, fungible_asset::metadata_from_asset(&asset_in));
        let (idx_out, store_out) = store(pool, asset_metadata_out);
        let amount_in = fungible_asset::amount(&asset_in);
        let amount_out = weighted_math::calc_out_given_in_weights_u64(
            idx_in,
            idx_out,
            amount_in,
            &balances(pool),
            &weighted_pool.weights
        );

        fungible_asset::deposit(store_in, asset_in);
        fungible_asset::withdraw(&pool_signer(pool), store_out, amount_out)
    }

    public fun swap_exact_in_stable(
        pool_obj: Object<Pool>,
        asset_in: FungibleAsset,
        asset_metadata_out: Object<Metadata>
    ): FungibleAsset acquires Pool, StablePool {
        // TODO: check asset_in and asset_out
        let pool_addr = object::object_address(&pool_obj);
        assert!(object::object_exists<Pool>(pool_addr), ERR_POOL_NOT_FOUND);

        let pool = borrow_global<Pool>(pool_addr);
        let stable_pool = borrow_global<StablePool>(pool_addr);

        let (idx_in, store_in) = store(pool, fungible_asset::metadata_from_asset(&asset_in));
        let (idx_out, store_out) = store(pool, asset_metadata_out);

        let amount_in = fungible_asset::amount(&asset_in);
        let calc_in = amount_in * *vector::borrow(&stable_pool.precision_multipliers, idx_in);
        let calc_out = stable_math::calc_out_given_in(
            stable_pool.amp_factor,
            idx_in,
            idx_out,
            calc_in,
            stable_math::get_xp(balances(pool), stable_pool.precision_multipliers)
        );
        let amount_out = calc_out / *vector::borrow(&stable_pool.precision_multipliers, idx_out);

        fungible_asset::deposit(store_in, asset_in);
        fungible_asset::withdraw(&pool_signer(pool), store_out, amount_out)
    }

    fun create_pool(
        assets: vector<FungibleAsset>,
        swap_fee_bps: u64,
        initial_lp_amount: u64
    ): (signer, Object<Pool>, FungibleAsset) {
        let pool_cref = object::create_sticky_object(package::resource_account_address());
        let pool_signer = object::generate_signer(&pool_cref);
        let extend_ref = object::generate_extend_ref(&pool_cref);

        let stores = vector::map<FungibleAsset, Object<FungibleStore>>(
            assets,
            |asset| {
                let store = fungible_asset::create_store(&pool_cref, fungible_asset::metadata_from_asset(&asset));
                fungible_asset::deposit(store, asset);
                store
            }
        );

        let (lp_token_mint_ref, lp_token_transfer_ref, lp_token_burn_ref) = {
            let constructor_ref = object::create_named_object(&pool_signer, b"lp_token");
            primary_fungible_store::create_primary_store_enabled_fungible_asset(
                &constructor_ref,
                option::none(),
                string::utf8(b"Thala LP Token"),
                string::utf8(b"THALA-LP"),
                LP_TOKEN_DECIMALS,
                string::utf8(b""),
                string::utf8(b"https://app.thala.fi/swap")
            );
            (
                fungible_asset::generate_mint_ref(&constructor_ref),
                fungible_asset::generate_transfer_ref(&constructor_ref),
                fungible_asset::generate_burn_ref(&constructor_ref)
            )
        };
        let lp_token = fungible_asset::mint(&lp_token_mint_ref, initial_lp_amount);
        move_to(&pool_signer, Pool {
            stores,
            swap_fee_bps,
            extend_ref,
            lp_token_mint_ref,
            lp_token_transfer_ref,
            lp_token_burn_ref
        });

        let pool_obj = object::object_from_constructor_ref<Pool>(&pool_cref);
        (pool_signer, pool_obj, lp_token)
    }

    fun extract_multi(
        assets: vector<FungibleAsset>,
        amounts: vector<u64>
    ): (vector<FungibleAsset>, vector<FungibleAsset>) {
        let extracted = vector::empty<FungibleAsset>();
        {
            let i = 0;
            let n = vector::length(&assets);
            while (i < n) {
                vector::push_back(
                    &mut extracted,
                    fungible_asset::extract(vector::borrow_mut(&mut assets, i), *vector::borrow(&amounts, i))
                );
                i = i + 1;
            };
        };
        (assets, extracted)
    }

    inline fun pool_signer(pool: &Pool): signer {
        object::generate_signer_for_extending(&pool.extend_ref)
    }

    inline fun lp_supply(pool: &Pool): u64 {
        let supply = fungible_asset::supply(fungible_asset::mint_ref_metadata(&pool.lp_token_mint_ref));
        (option::extract(&mut supply) as u64)
    }

    inline fun balances(pool: &Pool): vector<u64> {
        vector::map_ref<Object<FungibleStore>, u64>(
            &pool.stores,
            |store| fungible_asset::balance(*store)
        )
    }

    fun store(pool: &Pool, asset_metadata: Object<Metadata>): (u64, Object<FungibleStore>) {
        let (exists, idx) = vector::index_of(&vector::map<Object<FungibleStore>, Object<Metadata>>(
            pool.stores,
            |store| fungible_asset::store_metadata(store)
        ), &asset_metadata);
        // TODO: errcode
        assert!(exists, 0);
        (idx, *vector::borrow(&pool.stores, idx))
    }
}
