pub enum AirdropError {
    Unknown(String),
    TokenCanisterError(String),
    Unauthorized,
    ConfigurationError
}