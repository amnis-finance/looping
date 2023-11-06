module strategy::loop_apt {
    use aptos_framework::aptos_account;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin::{Self, Coin};
    use amnis::router;
    use amnis::stapt_token::{Self, StakedApt};
    use aptos_std::math64;
    use aptos_std::type_info::{Self, TypeInfo};
    use aries::controller;
    use aries::profile;
    use aries::reserve;
    use aries::reserve_details;
    use aries_config::interest_rate_config;
    use decimal::decimal;
    use liquidswap::scripts_v3;
    use liquidswap::curves::Stable;
    use oracle::oracle;
    use std::signer;
    use std::string;
    use amnis::amapt_token::AmnisApt;

    /// Leverage desired cannot exceed 2x.
    const ELEVERAGE_TOO_HIGH: u64 = 0;
    /// Leverage desired must be higher than 1x.
    const ELEVERAGE_TOO_LOW: u64 = 1;

    const PROFILE_NAME: vector<u8> = b"aries::loop_apt";
    const LEVERAGE_SCALING_FACTOR: u64 = 100;
    const MIN_LEVERAGE: u64 = 100;
    const MAX_LEVERAGE: u64 = 200;
    const MAX_LOOPS: u64 = 10; // Up to roughly 2.48x
    const DECIMAL_SCALING_FACTOR: u128 = 1000000000000000000;
    const MIN_APT_BORROWED: u64 = 10000000; // 0.1 APT

    struct Position has key {
        principal_stapt: u64,
    }

    #[view]
    public fun position(user: address): (u64, u64) acquires Position {
        let principal_stapt = if (exists<Position>(user)) {
            borrow_global<Position>(user).principal_stapt
        } else {
            0
        };
        let total_borrowed = profile::get_borrowed_amount(
            user,
            &string::utf8(PROFILE_NAME),
            apt_type_info(),
        );
        let total_borrowed = ((decimal::raw(total_borrowed) / DECIMAL_SCALING_FACTOR) as u64);
        (principal_stapt, total_borrowed)
    }

    #[view]
    public fun apt_rate(): u128 {
        let reserve_details = reserve::reserve_details(apt_type_info());
        let borrow_rate = interest_rate_config::get_borrow_rate(
            &reserve_details::interest_rate_config(&reserve_details),
            reserve_details::total_borrow_amount(&mut reserve_details),
            reserve_details::total_cash_available(&reserve_details),
            reserve_details::reserve_amount(&mut reserve_details),
        );
        decimal::raw(borrow_rate)
    }

    public entry fun initialize(user: &signer) {
        controller::register_user(user, PROFILE_NAME);
        move_to(user, Position {
            principal_stapt: 0,
        });
    }

    /// Borrow APT with stAPT as collateral. This will loop borrow until the desired leverage is reached.
    /// Leverage is specified as [0..200] where 200 is 2x.
    public entry fun borrow(user: &signer, amount: u64, leverage: u64) acquires Position {
        assert!(leverage > MIN_LEVERAGE, ELEVERAGE_TOO_LOW);
        assert!(leverage <= MAX_LEVERAGE, ELEVERAGE_TOO_HIGH);
        let user_addr = signer::address_of(user);
        if (!exists<Position>(user_addr)) {
            initialize(user);
        };

        let amount_stapt = stake(user, coin::withdraw<AptosCoin>(user, amount));
        let position = borrow_global_mut<Position>(user_addr);
        position.principal_stapt = position.principal_stapt + amount_stapt;

        let desired_borrowed_amount = math64::mul_div(amount, leverage, LEVERAGE_SCALING_FACTOR);
        loop_borrow(user, amount_stapt, desired_borrowed_amount);
    }

    /// Increase leverage of current position to the new desired value.
    public entry fun increase_leverage(user: &signer, new_leverage: u64) acquires Position {
        let user_addr = signer::address_of(user);
        let desired_borrowed_amount = desired_borrowed_amount(user_addr, new_leverage);
        let (_, total_borrowed) = position(user_addr);
        let amount_to_borrow = desired_borrowed_amount - total_borrowed;
        loop_borrow(user, 0, amount_to_borrow);
    }

    public entry fun unwind(user: &signer, new_leverage: u64) acquires Position {
        let user_addr = signer::address_of(user);
        // Calculate the amount of APT to repay to unwind to the new desired leverage.
        let desired_borrowed_amount = desired_borrowed_amount(user_addr, new_leverage);
        let (_, total_borrowed) = position(user_addr);
        let amount_to_unwind = total_borrowed - desired_borrowed_amount;

        // Withdraw the corresponding amount of stAPT from Aries.
        // Note that this can fail if the position is too close to the maximum LTV (60%).
        // In that case, users would need to repay with their own APT.
        let amount_stapt = math64::mul_div(amount_to_unwind, stapt_token::precision_u64(), stapt_token::stapt_price());
        controller::withdraw<StakedApt>(user, PROFILE_NAME, amount_stapt, false);

        // Unstake stAPT into amAPT with Amnis.
        let stapt = coin::withdraw<StakedApt>(user, amount_stapt);
        let amapt = router::unstake(stapt);
        let amount_amapt = coin::value(&amapt);
        aptos_account::deposit_coins(user_addr, amapt);

        // Swap amAPT for APT with Liquidswap.
        // Consider allowing user to specify minimum amount in the future.
        let bal_apt_before = coin::balance<AptosCoin>(user_addr);
        scripts_v3::swap<AmnisApt, AptosCoin, Stable>(user, amount_amapt, 0);
        let apt_received = coin::balance<AptosCoin>(user_addr) - bal_apt_before;

        // Repay APT to Aries.
        controller::deposit<AptosCoin>(user, PROFILE_NAME, apt_received, true);
    }

    fun desired_borrowed_amount(user: address, leverage: u64): u64 acquires Position {
        let amount_stapt = borrow_global<Position>(user).principal_stapt;
        let amount_apt = math64::mul_div(amount_stapt, stapt_token::stapt_price(), stapt_token::precision_u64());
        math64::mul_div(amount_apt, leverage, LEVERAGE_SCALING_FACTOR)
    }

    fun stake(user: &signer, apt: Coin<AptosCoin>): u64 {
        let stapt = router::deposit_and_stake(apt);
        let amount_stapt = coin::value(&stapt);
        aptos_account::deposit_coins(signer::address_of(user), stapt);
        amount_stapt
    }

    fun apt_type_info(): TypeInfo {
        type_info::type_of<AptosCoin>()
    }

    fun loop_borrow(user: &signer, amount_stapt: u64, desired_borrowed_amount: u64) {
        let user_addr = signer::address_of(user);
        // Max 10 loops. This should get to the max leverage allowed.
        let i = 10;
        while (i > 0) {
            // Deposit stAPT into Aries as collateral.
            if (amount_stapt > 0) {
                controller::deposit<StakedApt>(user, PROFILE_NAME, amount_stapt, false);
            };

            let max_remaining_borrowable = profile::available_borrowing_power(
                user_addr,
                &string::utf8(PROFILE_NAME),
            );

            // Check how much APT can be borrowed with current collateral.
            let apt_price = oracle::get_price(apt_type_info());
            let max_borrowable_apt = decimal::div(max_remaining_borrowable, apt_price);
            let max_borrowable_apt = ((decimal::raw(max_borrowable_apt) / DECIMAL_SCALING_FACTOR) as u64);
            let borrow_amount = math64::min(max_borrowable_apt, desired_borrowed_amount);

            // Borrow APT from Aries.
            let apt_bal_before = coin::balance<AptosCoin>(user_addr);
            controller::withdraw<AptosCoin>(user, PROFILE_NAME, borrow_amount, true);
            let apt_borrowed = coin::balance<AptosCoin>(user_addr) - apt_bal_before;

            // Stake APT with Amnis to generate stAPT. This stAPT is deposited into the user's account.
            amount_stapt = stake(user, coin::withdraw<AptosCoin>(user, apt_borrowed));
            desired_borrowed_amount = desired_borrowed_amount - borrow_amount;
            if (desired_borrowed_amount < MIN_APT_BORROWED) {
                // Deposit the last stAPT generated into Aries as collateral.
                if (amount_stapt > 0) {
                    controller::deposit<StakedApt>(user, PROFILE_NAME, amount_stapt, false);
                };
                break
            };
        };
    }
}
