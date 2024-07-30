use candid::CandidType;
use serde::{Deserialize, Serialize};

#[derive(CandidType, Deserialize, Serialize)]
pub enum AirdropError {
    Unknown(String),
    TokenCanisterError(String),
    Unauthorized,
    EmptyAllocationList,
    ConfigurationError
}