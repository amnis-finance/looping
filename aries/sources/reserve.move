module aries::reserve {
    use aptos_std::type_info::TypeInfo;
    use aries::reserve_details::ReserveDetails;

    struct Reserves has key {
    }

    public fun reserve_details(_reserve_type_info: TypeInfo): ReserveDetails {
        abort 0
    }
}
