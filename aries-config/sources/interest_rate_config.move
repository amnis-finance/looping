module aries_config::interest_rate_config {
    use decimal::decimal::Decimal;

    struct InterestRateConfig has store, drop, copy {
        min_borrow_rate: u64,
        optimal_borrow_rate: u64,
        max_borrow_rate: u64,
        optimal_utilization: u64
    }

    public fun get_borrow_rate(
        _config: &InterestRateConfig,
        _total_borrowed: Decimal,
        _total_cash: u128,
        _reserve_amount: Decimal,
    ): Decimal {
        abort 0
    }
}
