module aries::reserve_details {
    use aries_config::interest_rate_config::InterestRateConfig;
    use decimal::decimal::Decimal;

    struct ReserveDetails has store, copy, drop {
    }

    public fun interest_rate_config(_reserve_details: &ReserveDetails): InterestRateConfig {
        abort 0
    }

    public fun total_borrow_amount(_reserve_details: &mut ReserveDetails): Decimal {
        abort 0
    }

    public fun reserve_amount(_reserve_details: &mut ReserveDetails): Decimal {
        abort 0
    }

    public fun total_cash_available(_reserve_details: &ReserveDetails): u128 {
        abort 0
    }
}
