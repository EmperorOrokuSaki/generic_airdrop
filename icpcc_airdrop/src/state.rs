use std::cell::RefCell;

use candid::Principal;

thread_local! {
    /// TOKEN CANISTER PRINCIPAL ID
    pub static TOKEN_PID: RefCell<Principal> = RefCell::new(Principal::anonymous());
}

/// Returns the token's principal ID
pub fn get_token_pid() -> Principal {
    TOKEN_PID.with(|pid| pid.borrow().clone())
}



