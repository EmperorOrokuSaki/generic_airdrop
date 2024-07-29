use std::{cell::RefCell, collections::HashMap};

use candid::{Nat, Principal};

thread_local! {
    /// Token canister's principal ID
    pub static TOKEN_PID: RefCell<Principal> = RefCell::new(Principal::anonymous());
    /// HashMap of all participants and their receiving amount
    pub static ALLOCATIONS: RefCell<HashMap<Principal, Nat>> = RefCell::new(HashMap::new());
}

/// Returns the token's principal ID
pub fn get_token_pid() -> Principal {
    TOKEN_PID.with(|pid| pid.borrow().clone())
}

/// Returns the amount of tokens allocated to `user`
pub fn get_user_reward(user: Principal) -> Option<Nat> {
    ALLOCATIONS.with(|allocations| allocations.borrow().get(&user).cloned())
}

/// Returns the vector of all users and their allocations
pub fn get_all_allocations() -> Vec<(Principal, Nat)> {
    ALLOCATIONS.with(|allocations| allocations.borrow().clone().into_iter().collect())
}

/// Add an allocation
pub fn add_allocation(user: Principal, amount: Nat) {
    ALLOCATIONS.with(|allocations| allocations.borrow_mut().insert(user, amount));
}
