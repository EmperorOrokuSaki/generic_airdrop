use std::time::Duration;

use ic_canister::{generate_idl, query, update, Canister, Idl, PreUpdate};
use ic_exports::{
    candid::{Nat, Principal},
    ic_cdk::{call, caller, id, print, spawn},
    ic_cdk_timers::{clear_timer, set_timer, set_timer_interval},
};
use icrc_ledger_types::icrc1::{
    account::Account,
    transfer::{Memo, TransferArg, TransferError},
};

#[derive(Canister)]
pub struct Airdrop {
    #[id]
    id: Principal,
}

impl PreUpdate for Airdrop {}

impl Airdrop {

    pub fn idl() -> Idl {
        generate_idl!()
    }
}
