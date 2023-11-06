//! Scaled integer for arithmetic calculation, it is a normal integer
//! times 10 * 18 to preserve precision.

module oracle::oracle {
    use aptos_std::type_info::TypeInfo;
    use decimal::decimal::Decimal;

    public fun get_price(_type_info: TypeInfo): Decimal {
        abort 0
    }
}
