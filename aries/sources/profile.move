module aries::profile {
    use std::string::String;
    use aptos_std::type_info::TypeInfo;
    use decimal::decimal::Decimal;

    public fun get_borrowed_amount(_user_addr: address, _profile_name: &String, _reserve_type_info: TypeInfo): Decimal {
        abort 0
    }

    public fun available_borrowing_power(_user_addr: address, _profile_name: &String): Decimal {
        abort 0
    }
}
