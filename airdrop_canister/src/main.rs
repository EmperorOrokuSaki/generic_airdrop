mod canister;
mod state;
mod utils;
mod types;

use crate::canister::Airdrop;

fn main() {
    let canister_e_idl = Airdrop::idl();
    let idl = ic_exports::candid::pretty::candid::compile(
        &canister_e_idl.env.env,
        &Some(canister_e_idl.actor),
    );

    println!("{}", idl);
}
