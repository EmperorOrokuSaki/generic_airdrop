use crate::{
    state::{add_allocation, get_all_allocations, ALLOCATIONS},
    types::AirdropError,
    utils::{only_controller, transfer_tokens},
};

use ic_canister::{generate_idl, query, update, Canister, Idl, PreUpdate};
use ic_exports::{
    candid::{Nat, Principal},
    ic_cdk::caller,
};

#[derive(Canister)]
pub struct Airdrop {
    #[id]
    id: Principal,
}

impl PreUpdate for Airdrop {}

impl Airdrop {
    #[update]
    pub fn add_allocations(&self, allocations: Vec<(Principal, Nat)>) -> Result<(), AirdropError> {
        only_controller(caller())?;

        allocations.iter().for_each(|allocation| {
            add_allocation(allocation.0, allocation.1.clone());
        });

        Ok(())
    }

    #[update]
    pub async fn distribute(&self, total_tokens: Nat) -> Result<(), AirdropError> {
        only_controller(caller())?;

        let allocations = get_all_allocations();
        let mut shares_sum: Nat = Nat::from(0 as u32);
        allocations
            .iter()
            .for_each(|(_, share)| shares_sum += share.clone());

        let token_per_share = total_tokens / shares_sum;

        for (user, share) in allocations {
            let tokens = token_per_share.clone() * share;
            let mut tries = 0;
            loop {
                let transfer_result = transfer_tokens(user, tokens.clone()).await;

                if transfer_result.is_ok() {
                    ALLOCATIONS.with(|allocations| allocations.borrow_mut().remove(&user));
                    break;
                } else if tries > 2 {
                    return transfer_result;
                }

                tries += 1;
            }
        }

        Ok(())
    }

    pub fn idl() -> Idl {
        generate_idl!()
    }
}
