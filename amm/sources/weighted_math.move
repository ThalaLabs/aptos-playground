module amm::weighted_math {
    use std::vector;

    // TODO: IMPLEMENT ME
    public fun compute_invariant_weights_u64(_balances: &vector<u64>, _weights: &vector<u64>): u64 {
        0
    }

    // TODO: IMPLEMENT ME
    public fun compute_pool_tokens_issued(
        _deposits: &vector<u64>,
        _balances: &vector<u64>,
        _lp_supply: u64
    ): (u64, vector<u64>) {
        (0, vector::empty())
    }

    // TODO: IMPLEMENT ME
    public fun calc_out_given_in_weights_u64(
        _idx_in: u64,
        _idx_out: u64,
        _aI: u64,
        _balances: &vector<u64>,
        _weights: &vector<u64>
    ): u64 {
        0
    }
}
