module aries::controller {
    public entry fun register_user(_account: &signer, _default_profile_name: vector<u8>) {
        abort 0
    }

    public entry fun deposit<Coin0>(_account: &signer, _profile_name: vector<u8>, _amount: u64, _repay_only: bool) {
        abort 0
    }

    public entry fun withdraw<Coin0>(_account: &signer, _profile_name: vector<u8>, _amount: u64, _allow_borrow: bool) {
        abort 0
    }
}
