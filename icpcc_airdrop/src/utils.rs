use candid::{Nat, Principal};
use ic_exports::{ic_cdk::{api::is_controller, call}, ic_kit::CallResult};
use icrc_ledger_types::icrc1::{account::Account, transfer::{TransferArg, TransferError}};

use crate::{state::get_token_pid, types::AirdropError};

/// Returns error if `caller` is not a controller of the canister
pub fn only_controller(caller: Principal) -> Result<(), AirdropError> {
    if !is_controller(&caller) {
        return Err(AirdropError::Unauthorized);
    }
    Ok(())
}

/// Transfers `amount` tokens to `receiver_pid`
pub async fn transfer_tokens(receiver_pid: Principal, amount: Nat) -> Result<(), AirdropError> {
    let token_canister = get_token_pid();
    not_anonymous(&token_canister)?;

    let transfer_args = TransferArg {
        from_subaccount: None,
        to: Account {
            owner: receiver_pid,
            subaccount: None,
        },
        fee: None,
        created_at_time: None,
        memo: None,
        amount,
    };

    let call_response = call(token_canister, "icrc1_transfer", (transfer_args, )).await;

    match handle_intercanister_call::<Result<Nat, TransferError>>(call_response)? {
        Err(err) => Err(AirdropError::TokenCanisterError(format!(
            "Error occured on token transfer: {:#?}",
            err
        ))),
        _ => Ok(()),
    }?;

    Ok(())
}

pub fn not_anonymous(id: &Principal) -> Result<(), AirdropError> {
    if id == &Principal::anonymous() {
        return Err(AirdropError::ConfigurationError);
    }
    Ok(())
}

pub fn handle_intercanister_call<T>(
    canister_response: CallResult<(T,)>,
) -> Result<T, AirdropError> {
    match canister_response {
        Ok((response,)) => Ok(response),
        Err((_code, message)) => Err(AirdropError::Unknown(message)),
    }
}