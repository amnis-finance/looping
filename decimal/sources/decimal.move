//! Scaled integer for arithmetic calculation, it is a normal integer
//! times 10 * 18 to preserve precision.

module decimal::decimal {
    struct Decimal has copy, drop, store {
        val: u128,
    }

    public fun raw(a: Decimal): u128 {
        a.val
    }

    public fun div(_a: Decimal, _b: Decimal): Decimal {
        abort 0
    }
}
