use crate::{
    state::{add_share_allocation, add_token_allocation, clear_all, get_all_share_allocations, get_all_token_allocations, get_user_shares, get_user_tokens, SHARE_ALLOCATIONS, TOKEN_PID},
    types::AirdropError,
    utils::{only_controller, token_balance, token_fee, transfer_tokens},
};

use ic_canister::{generate_idl, query, update, Canister, Idl, PreUpdate};
use ic_exports::{
    candid::{Nat, Principal},
    ic_cdk::{caller, id},
};

#[derive(Canister)]
pub struct Airdrop {
    #[id]
    id: Principal,
}

impl PreUpdate for Airdrop {}

impl Airdrop {
    #[update]
    pub fn set_token_canister_id(&self, id: Principal) -> Result<(), AirdropError> {
        only_controller(caller())?;

        TOKEN_PID.with(|pid| *pid.borrow_mut() = id);

        Ok(())
    }

    #[update]
    pub fn add_share_allocations(&self, allocations: Vec<(Principal, Nat)>) -> Result<(), AirdropError> {
        only_controller(caller())?;

        allocations.iter().for_each(|allocation| {
            add_share_allocation(allocation.0, allocation.1.clone());
        });

        Ok(())
    }

    #[update]
    pub fn reset(&self,) -> Result<(), AirdropError> {
        only_controller(caller())?;

        clear_all();

        Ok(())
    }

    #[update]
    pub async fn distribute(&self) -> Result<(), AirdropError> {
        only_controller(caller())?;

        let total_tokens = token_balance(id()).await?;

        let share_allocations = get_all_share_allocations();

        if share_allocations.len() < 1 {
            return Err(AirdropError::EmptyAllocationList);
        }

        let mut shares_sum: Nat = Nat::from(0 as u32);

        share_allocations
            .iter()
            .for_each(|(_, share)| shares_sum += share.clone());

        let fee = token_fee().await?;
        let total_fee = share_allocations.len() * fee;
        let token_per_share = (total_tokens - total_fee) / shares_sum;

        for (user, share) in share_allocations {
            let tokens = token_per_share.clone() * share;
            let mut tries = 0;
            loop {
                let transfer_result = transfer_tokens(user, tokens.clone()).await;

                if transfer_result.is_ok() {
                    SHARE_ALLOCATIONS.with(|allocations| allocations.borrow_mut().remove(&user));
                    add_token_allocation(user, tokens);
                    break;
                } else if tries > 2 {
                    return transfer_result;
                }

                tries += 1;
            }
        }

        Ok(())
    }

    #[query]
    pub fn get_user_share_allocation(&self, user: Principal) -> Option<Nat> {
        get_user_shares(user)
    }

    #[query]
    pub fn get_user_token_allocation(&self, user: Principal) -> Option<Nat> {
        get_user_tokens(user)
    }

    #[query]
    pub fn get_shares_list(&self, start_index: u64) -> Vec<(Principal, Nat)> {
        let allocations = get_all_share_allocations();
        let start_index = start_index as usize;
        let end_index = usize::min(start_index + 100, allocations.len());

        if start_index >= allocations.len() {
            return vec![];
        }

        allocations[start_index..end_index].to_vec()
    }

    #[query]
    pub fn get_tokens_list(&self, start_index: u64) -> Vec<(Principal, Nat)> {
        let allocations = get_all_token_allocations();
        let start_index = start_index as usize;
        let end_index = usize::min(start_index + 100, allocations.len());

        if start_index >= allocations.len() {
            return vec![];
        }

        allocations[start_index..end_index].to_vec()
    }

    pub fn idl() -> Idl {
        generate_idl!()
    }
}
