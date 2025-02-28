#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Configuration
CANISTER_NAME="airdrop_canister"
TOKEN_CANISTER_NAME="icrc1-ledger"
ALLOCATION_FILE="allocations.csv"
IC_VERSION="ledger-suite-icrc-2025-02-27"
TRANSFER_AMOUNT="10_000_000_000"  # Amount to mint for testing

echo "===== Airdrop Canister Management Script ====="

# Check if dfx is installed
if ! command -v dfx &> /dev/null; then
    echo "Error: dfx command could not be found. Please install the Internet Computer SDK."
    exit 1
fi

# Function to log actions with timestamp
log_action() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Enhanced error handling function
handle_error() {
    log_action "ERROR: Command failed with exit code $1 at line $2"
    log_action "Exiting script"
    exit 1
}

# Set up trap to catch errors
trap 'handle_error $? $LINENO' ERR

# Create a project directory if not already in one
if [ ! -f "dfx.json" ]; then
    log_action "Creating project directory structure..."
    mkdir -p src
fi

# Get the principal of the current identity
PRINCIPAL=$(dfx identity get-principal)
log_action "Using principal: $PRINCIPAL"

# Download the ledger wasm and DID files
log_action "Downloading ICRC-1 Ledger files..."

# Copy files from Downloads folder
log_action "Copying ledger files from Downloads folder..."
cp ~/Downloads/ic-icrc1-ledger.wasm.gz ./
cp ~/Downloads/ledger.did ./

# Extract the wasm file
log_action "Extracting wasm file from gz archive..."
gunzip -f ic-icrc1-ledger.wasm.gz

log_action "Files copied and extracted successfully."

if [ -f ~/Downloads/ledger.did ]; then
    cp ~/Downloads/ledger.did ./
    log_action "Copied ledger.did from Downloads"
else
    log_action "WARNING: Could not find ledger.did in Downloads directory"
    
    # Fall back to downloading if file doesn't exist in Downloads
    log_action "Falling back to downloading did file..."
    curl -o ledger.did https://raw.githubusercontent.com/dfinity/ic/${IC_VERSION}/rs/ledger_suite/icrc1/ledger/ledger.did || {
        log_action "ERROR: Could not download the did file."
        exit 1
    }
fi

# Verify files exist
if [ ! -f "ic-icrc1-ledger.wasm" ] || [ ! -s "ic-icrc1-ledger.wasm" ]; then
    log_action "ERROR: ic-icrc1-ledger.wasm file not found or empty."
    exit 1
fi

if [ ! -f "ledger.did" ] || [ ! -s "ledger.did" ]; then
    log_action "ERROR: ledger.did file not found or empty."
    exit 1
fi

log_action "ICRC-1 Ledger files prepared"

# Clone the airdrop repository if needed
if [ ! -d "tmp_airdrop" ]; then
    log_action "Cloning the airdrop repository..."
    git clone git@github.com:EmperorOrokuSaki/generic_airdrop.git tmp_airdrop || {
        log_action "Failed to clone from git@github.com, trying HTTPS..."
        git clone https://github.com/EmperorOrokuSaki/generic_airdrop.git tmp_airdrop
    }
fi

# Copy the necessary files from the repo structure
log_action "Setting up project structure based on the repo..."
mkdir -p src
cp -r tmp_airdrop/airdrop_canister/src/* src/
cp tmp_airdrop/airdrop_canister/Cargo.toml ./Cargo.toml
cp tmp_airdrop/airdrop_canister/candid.did ./candid.did

# Create dfx.json for the canisters
cat > dfx.json << EOF
{
  "canisters": {
    "${TOKEN_CANISTER_NAME}": {
      "type": "custom",
      "wasm": "ic-icrc1-ledger.wasm",
      "candid": "ledger.did"
    },
    "${CANISTER_NAME}": {
      "type": "rust",
      "package": "airdrop_canister",
      "candid": "candid.did"
    }
  },
  "defaults": {
    "build": {
      "packtool": "",
      "args": ""
    }
  },
  "networks": {
    "local": {
      "bind": "127.0.0.1:8003"
    }
  },
  "version": 1
}
EOF

# Stop any running dfx instance first
dfx stop 2>/dev/null || true

# Start dfx
log_action "Starting dfx in the background..."
dfx start --background --clean

# Wait for dfx to start up
log_action "Waiting for replica to start..."
TRIES=0
MAX_TRIES=30
while ! dfx ping &>/dev/null && [ $TRIES -lt $MAX_TRIES ]; do
    sleep 1
    TRIES=$((TRIES+1))
    echo -n "."
done
echo ""

if ! dfx ping &>/dev/null; then
    log_action "ERROR: Failed to start the replica after waiting"
    exit 1
fi
log_action "Replica is ready"

# Deploy the token canister
log_action "Deploying the ICRC-1 Ledger canister..."
dfx deploy ${TOKEN_CANISTER_NAME} --argument "(record {
  token_symbol = \"TEST\";
  token_name = \"Test Token\";
  minting_account = record { owner = principal \"${PRINCIPAL}\" };
  transfer_fee = 10_000;
  metadata = vec {};
  initial_balances = vec {};
  archive_options = record {
    num_blocks_to_archive = 2000;
    trigger_threshold = 1000;
    controller_id = principal \"${PRINCIPAL}\";
  };
})"

# Get the token canister ID
TOKEN_CANISTER_ID=$(dfx canister id ${TOKEN_CANISTER_NAME})
log_action "Token canister deployed with ID: ${TOKEN_CANISTER_ID}"

# Check our initial balance
log_action "Checking initial token balance..."
INITIAL_BALANCE=$(dfx canister call ${TOKEN_CANISTER_NAME} icrc1_balance_of "(record { owner = principal \"${PRINCIPAL}\" })" --query)
log_action "Initial token balance: ${INITIAL_BALANCE}"

# Mint initial tokens to our own account
log_action "Minting initial tokens to our account..."
dfx canister call ${TOKEN_CANISTER_NAME} icrc1_transfer "(record {
  to = record { owner = principal \"${PRINCIPAL}\" };
  amount = ${TRANSFER_AMOUNT};
})"

# Check updated balance after minting
log_action "Checking updated token balance after minting..."
UPDATED_BALANCE=$(dfx canister call ${TOKEN_CANISTER_NAME} icrc1_balance_of "(record { owner = principal \"${PRINCIPAL}\" })" --query)
log_action "Updated token balance: ${UPDATED_BALANCE}"

# Deploy the airdrop canister
log_action "Deploying the airdrop canister..."
dfx deploy ${CANISTER_NAME}

# Get the airdrop canister ID
AIRDROP_CANISTER_ID=$(dfx canister id ${CANISTER_NAME})
log_action "Airdrop canister deployed with ID: ${AIRDROP_CANISTER_ID}"

# Set the token canister ID in the airdrop canister
log_action "Setting token canister ID in airdrop canister..."
dfx canister call ${CANISTER_NAME} set_token_canister_id "(principal \"${TOKEN_CANISTER_ID}\")"

# Reset any existing allocations
log_action "Resetting existing allocations..."
dfx canister call ${CANISTER_NAME} reset

# Generate test principals if allocation file doesn't exist
if [ ! -f "${ALLOCATION_FILE}" ]; then
    log_action "Creating test allocation data..."
    # Create a small allocation file with test principals
    cat > "${ALLOCATION_FILE}" << EOF
$(dfx identity get-principal),5000
aaaaa-aa,1000
bbbbb-bb,2000
ccccc-cc,3000
EOF
    log_action "Created test allocation file: ${ALLOCATION_FILE}"
fi

# Check share allocations before adding
log_action "Checking share allocations (should be empty)..."
dfx canister call ${CANISTER_NAME} get_shares_list "(0)"

# Add share allocations
log_action "Adding share allocations from file: ${ALLOCATION_FILE}"
if [ -f "${ALLOCATION_FILE}" ]; then
    # Read from allocation file
    ALLOCATIONS=""
    while IFS=, read -r principal shares; do
        # Skip empty lines or comments
        if [[ -z "$principal" || "$principal" == \#* ]]; then
            continue
        fi
        
        if [ -n "${ALLOCATIONS}" ]; then
            ALLOCATIONS="${ALLOCATIONS}, "
        fi
        ALLOCATIONS="${ALLOCATIONS}(principal \"${principal}\", ${shares})"
    done < "${ALLOCATION_FILE}"
    
    dfx canister call ${CANISTER_NAME} add_share_allocations "(vec { ${ALLOCATIONS} })"
else
    log_action "WARNING: No allocation file found. Using example allocations..."
    dfx canister call ${CANISTER_NAME} add_share_allocations "(vec { 
        (principal \"${PRINCIPAL}\", 5000), 
        (principal \"aaaaa-aa\", 1000), 
        (principal \"bbbbb-bb\", 2000), 
        (principal \"ccccc-cc\", 3000) 
    })"
fi

# Check share allocations after adding
log_action "Checking share allocations after adding..."
SHARES_BEFORE=$(dfx canister call ${CANISTER_NAME} get_shares_list "(0)")
echo "Share allocations before distribution:"
echo "${SHARES_BEFORE}"

# Transfer tokens to the airdrop canister
log_action "Transferring tokens to the airdrop canister for distribution..."
TRANSFER_TO_AIRDROP_AMOUNT=5000000000  # Adjust as needed
dfx canister call ${TOKEN_CANISTER_NAME} icrc1_transfer "(record {
  to = record { owner = principal \"${AIRDROP_CANISTER_ID}\" };
  amount = ${TRANSFER_TO_AIRDROP_AMOUNT};
})"

# Check airdrop canister balance
AIRDROP_BALANCE_BEFORE=$(dfx canister call ${TOKEN_CANISTER_NAME} icrc1_balance_of "(record { owner = principal \"${AIRDROP_CANISTER_ID}\" })" --query)
log_action "Airdrop canister balance before distribution: ${AIRDROP_BALANCE_BEFORE}"

# Distribute rewards
log_action "Distributing rewards..."
DISTRIBUTION_RESULT=$(dfx canister call ${CANISTER_NAME} distribute)
echo "Distribution result: ${DISTRIBUTION_RESULT}"

# Check airdrop canister balance after distribution
AIRDROP_BALANCE_AFTER=$(dfx canister call ${TOKEN_CANISTER_NAME} icrc1_balance_of "(record { owner = principal \"${AIRDROP_CANISTER_ID}\" })" --query)
log_action "Airdrop canister balance after distribution: ${AIRDROP_BALANCE_AFTER}"

# Check if the distribution was successful
if [[ "${AIRDROP_BALANCE_AFTER}" == "${AIRDROP_BALANCE_BEFORE}" ]]; then
    log_action "WARNING: Airdrop canister balance didn't change after distribution!"
else
    log_action "Tokens distributed successfully. Balance changed from ${AIRDROP_BALANCE_BEFORE} to ${AIRDROP_BALANCE_AFTER}"
fi

# Check share allocations after distribution (should be empty)
SHARES_AFTER=$(dfx canister call ${CANISTER_NAME} get_shares_list "(0)")
log_action "Share allocations after distribution:"
echo "${SHARES_AFTER}"

# Get all token allocations
log_action "Fetching token allocations from airdrop canister..."
INDEX=0
CONTINUE=true

echo ""
echo "User Token Allocations After Distribution:"
echo "-------------------------------------------------------"
echo "Principal ID | Token Amount | Actual Balance"
echo "-------------------------------------------------------"

while ${CONTINUE}; do
    RESULT=$(dfx canister call ${CANISTER_NAME} get_tokens_list "(${INDEX})")
    
    # If empty result, we're done
    if [[ "${RESULT}" == "vec {}" ]]; then
        CONTINUE=false
    else
        # Process the results line by line to handle the format correctly
        echo "${RESULT}" | grep -A 1 "principal" | paste -d "#" - - | while read -r line; do
            # Extract principal and amount from the combined line
            PRINCIPAL=$(echo "${line}" | grep -o 'principal "[^"]*"' | cut -d '"' -f 2)
            AMOUNT=$(echo "${line}" | grep -o '[0-9_]*;$' | tr -d ';')
            
            if [ -n "${PRINCIPAL}" ] && [ -n "${AMOUNT}" ]; then
                # Check actual token balance for this principal
                if [[ "${PRINCIPAL}" == "aaaaa-aa" ]] || [[ "${PRINCIPAL}" == "bbbbb-bb" ]] || [[ "${PRINCIPAL}" == "ccccc-cc" ]]; then
                    TOKEN_BALANCE="Cannot check for IC defaults"
                else
                    TOKEN_BALANCE=$(dfx canister call ${TOKEN_CANISTER_NAME} icrc1_balance_of "(record { owner = principal \"${PRINCIPAL}\" })" --query 2>/dev/null || echo "Error")
                fi
                
                echo "${PRINCIPAL} | ${AMOUNT} | ${TOKEN_BALANCE}"
            fi
        done
        
        # Move to next page
        INDEX=$((INDEX + 100))
    fi
done

log_action "===== Airdrop testing process completed successfully ====="
echo ""
echo "Summary:"
echo "- Token canister ID: ${TOKEN_CANISTER_ID}"
echo "- Airdrop canister ID: ${AIRDROP_CANISTER_ID}"
echo ""
echo "To check balances manually:"
echo "  dfx canister call ${TOKEN_CANISTER_NAME} icrc1_balance_of \"(record { owner = principal \\\"PRINCIPAL_ID\\\" })\" --query"
echo ""
echo "To check token allocations manually:"
echo "  dfx canister call ${CANISTER_NAME} get_user_token_allocation \"(principal \\\"PRINCIPAL_ID\\\")\" --query"
echo ""
echo "To check share allocations manually:"
echo "  dfx canister call ${CANISTER_NAME} get_user_share_allocation \"(principal \\\"PRINCIPAL_ID\\\")\" --query"
echo ""
echo "To mint more tokens (as the minting account):"
echo "  dfx canister call ${TOKEN_CANISTER_NAME} icrc1_transfer \"(record { to = record { owner = principal \\\"RECIPIENT_ID\\\" }; amount = AMOUNT })\" "