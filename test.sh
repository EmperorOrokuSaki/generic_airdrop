#!/bin/bash

# Make sure bc is installed for floating point calculations
if ! command -v bc &> /dev/null; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] The 'bc' command is required for calculations. Installing..."
    sudo apt-get update && sudo apt-get install -y bc || {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: Failed to install bc. Some calculations may not work correctly."
    }
fi

# Exit immediately if a command exits with a non-zero status
set -e

# Configuration
CANISTER_NAME="airdrop_canister"
TOKEN_CANISTER_NAME="icrc1-ledger"
ALLOCATION_FILE="allocations.csv"
IC_VERSION="ledger-suite-icrc-2025-02-27"
TRANSFER_AMOUNT="4_000_000_000_000"  # Amount to mint for testing
AIRDROP_TOTAL="3_370_000_000_000"  # Amount to transfer to airdrop canister
CYCLES="100_000_000_000_000"  # Amount of cycles to deposit
TMP_DIR=""

# Function to log actions with timestamp
log_action() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Cleanup function to be called on exit
cleanup() {
    # Capture the exit code of the last command
    EXIT_CODE=$?
    
    log_action "Running cleanup..."
    
    # Stop dfx if it's running
    dfx stop 2>/dev/null || true
    
    # Remove temporary directory if it was created
    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
        log_action "Removing temporary directory: $TMP_DIR"
        rm -rf "$TMP_DIR"
    fi
    
    # Remove symbolic links if they exist
    if [ -L "ledger/ic-icrc1-ledger.wasm" ]; then
        rm -f "ledger/ic-icrc1-ledger.wasm"
    fi
    if [ -L "ledger/ledger.did" ]; then
        rm -f "ledger/ledger.did"
    fi
    
    log_action "Cleanup completed"
    
    # Exit with the captured exit code
    exit $EXIT_CODE
}

# Enhanced error handling function
handle_error() {
    log_action "ERROR: Command failed with exit code $1 at line $2"
    # Cleanup will be called by the EXIT trap
    exit 1
}

# Set trap for cleanup on exit (normal or error)
trap cleanup EXIT
# Set trap to catch errors
trap 'handle_error $? $LINENO' ERR

# Generate test principals if allocation file doesn't exist or user wants to regenerate
generate_random_principals() {
    local count=$1
    local min_shares=$2
    local max_shares=$3
    local output_file=$4
    local total_shares=0
    
    log_action "Generating $count random test principals with shares between $min_shares and $max_shares..."
    # Clear the file first
    > "$output_file"
    
    # Create a temporary directory for identity files
    local identity_tmp_dir=$(mktemp -d)
    log_action "Created temporary directory for identity files: $identity_tmp_dir"
    
    # Save the current identity
    local current_identity=$(dfx identity whoami)
    log_action "Current identity: $current_identity"
    
    # Add the current user principal first with random shares
    current_shares=$((RANDOM % (max_shares - min_shares + 1) + min_shares))
    total_shares=$((total_shares + current_shares))
    echo "$PRINCIPAL,$current_shares" >> "$output_file"
    log_action "Added current principal with $current_shares shares"
    
    # List of valid identities to use
    local identities=()
    
    # Generate the rest of random principals (count-1 because we already added current principal)
    for ((i=1; i<count; i++)); do
        # Create a unique temporary identity name
        local temp_identity="temp_identity_$i"
        
        # Create a new identity
        log_action "Creating temporary identity: $temp_identity"
        dfx identity new --storage-mode plaintext "$temp_identity" > /dev/null 2>&1
        
        # Use the new identity to get its principal
        dfx identity use "$temp_identity" > /dev/null 2>&1
        local principal_id=$(dfx identity get-principal)
        
        # Add to our list for cleanup later
        identities+=("$temp_identity")
        
        # Generate random share amount
        shares=$((RANDOM % (max_shares - min_shares + 1) + min_shares))
        total_shares=$((total_shares + shares))
        
        echo "$principal_id,$shares" >> "$output_file"
        log_action "Added principal $principal_id with $shares shares"
    done
    
    # Switch back to original identity
    dfx identity use "$current_identity" > /dev/null 2>&1
    log_action "Switched back to original identity: $current_identity"
    
    # Clean up temporary identities
    for identity in "${identities[@]}"; do
        log_action "Removing temporary identity: $identity"
        dfx identity remove "$identity" > /dev/null 2>&1
    done
    
    log_action "Generated $count principals with a total of $total_shares shares"
    # Return only the numeric value, no logging output
    printf "%d" "$total_shares"
}

log_action "===== Airdrop Canister Testing Script ====="

# Check if dfx is installed
if ! command -v dfx &> /dev/null; then
    log_action "Error: dfx command could not be found. Please install the Internet Computer SDK."
    exit 1
fi

# Create a temporary directory for ledger files
TMP_DIR=$(mktemp -d)
log_action "Created temporary directory for ledger files: $TMP_DIR"
mkdir -p "$TMP_DIR/ledger"

# Get the principal of the current identity
PRINCIPAL=$(dfx identity get-principal)
log_action "Using principal: $PRINCIPAL"

# Download or copy ledger files to the temporary location
log_action "Setting up ICRC-1 Ledger files..."

# Try to find ledger files in common locations
LEDGER_WASM_FOUND=false
LEDGER_DID_FOUND=false

# Check common locations for the wasm file
for LOCATION in \
    "./ledger/ic-icrc1-ledger.wasm" \
    "$HOME/Downloads/ic-icrc1-ledger.wasm" \
    "$HOME/Downloads/ic-icrc1-ledger.wasm.gz"; do
    
    if [ -f "$LOCATION" ]; then
        log_action "Found ledger WASM at: $LOCATION"
        
        # Copy or extract the file
        if [[ "$LOCATION" == *.gz ]]; then
            log_action "Extracting gzipped WASM file..."
            gunzip -c "$LOCATION" > "$TMP_DIR/ledger/ic-icrc1-ledger.wasm"
        else
            cp "$LOCATION" "$TMP_DIR/ledger/ic-icrc1-ledger.wasm"
        fi
        
        LEDGER_WASM_FOUND=true
        break
    fi
done

# Check common locations for the did file
for LOCATION in \
    "./ledger/ledger.did" \
    "$HOME/Downloads/ledger.did"; do
    
    if [ -f "$LOCATION" ]; then
        log_action "Found ledger DID at: $LOCATION"
        cp "$LOCATION" "$TMP_DIR/ledger/ledger.did"
        LEDGER_DID_FOUND=true
        break
    fi
done

# If we didn't find the WASM file in any of the expected locations, download it
if [ "$LEDGER_WASM_FOUND" = false ]; then
    log_action "Ledger WASM not found in any of the expected locations. Attempting to download..."
    
    # URL for the latest release of the ICRC-1 Ledger
    ICRC1_LEDGER_URL="https://download.dfinity.systems/ic/${IC_VERSION}/canisters/ic-icrc1-ledger.wasm.gz"
    
    log_action "Downloading from: ${ICRC1_LEDGER_URL}"
    
    if curl -s -L -o "$TMP_DIR/ledger/ic-icrc1-ledger.wasm.gz" "${ICRC1_LEDGER_URL}"; then
        gunzip "$TMP_DIR/ledger/ic-icrc1-ledger.wasm.gz"
        LEDGER_WASM_FOUND=true
        log_action "Successfully downloaded and extracted the ledger WASM"
    else
        log_action "ERROR: Failed to download the ledger WASM"
        exit 1
    fi
fi

# If we didn't find the DID file in any of the expected locations, download it
if [ "$LEDGER_DID_FOUND" = false ]; then
    log_action "Ledger DID not found in any of the expected locations. Attempting to download..."
    
    # URL for the latest DID file
    ICRC1_DID_URL="https://raw.githubusercontent.com/dfinity/ic/${IC_VERSION}/rs/ledger_suite/icrc1/ledger/ledger.did"
    
    log_action "Downloading from: ${ICRC1_DID_URL}"
    
    if curl -s -L -o "$TMP_DIR/ledger/ledger.did" "${ICRC1_DID_URL}"; then
        LEDGER_DID_FOUND=true
        log_action "Successfully downloaded the ledger DID"
    else
        log_action "ERROR: Failed to download the ledger DID"
        exit 1
    fi
fi

# Ensure we have both files
if [ "$LEDGER_WASM_FOUND" = false ] || [ "$LEDGER_DID_FOUND" = false ]; then
    log_action "ERROR: Failed to find or download the required ledger files"
    exit 1
fi

# Create symbolic links to the ledger files in the current directory
mkdir -p ledger
ln -sf "$TMP_DIR/ledger/ic-icrc1-ledger.wasm" "ledger/ic-icrc1-ledger.wasm"
ln -sf "$TMP_DIR/ledger/ledger.did" "ledger/ledger.did"

# Stop any running dfx instance first
log_action "Stopping any running dfx instance..."
dfx stop 2>/dev/null || true

# Start dfx
log_action "Starting dfx in the background..."
dfx start --background --clean

# Wait for dfx to start up
log_action "Waiting for replica to start..."
TRIES=0
MAX_TRIES=150
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

# Build the airdrop canister
log_action "Building the airdrop canister..."
bash ./build.sh

log_action "Deploying the ICRC-1 Ledger canister..."
dfx deploy ${TOKEN_CANISTER_NAME} --argument "(variant { Init = record {
  token_symbol = \"TEST\";
  token_name = \"Test Token\";
  minting_account = record { owner = principal \"${PRINCIPAL}\" };
  transfer_fee = 10_000;
  metadata = vec {};
  initial_balances = vec { record { record { owner = principal \"${PRINCIPAL}\"; subaccount = null }; ${TRANSFER_AMOUNT}} };
  archive_options = record {
    num_blocks_to_archive = 2000;
    trigger_threshold = 1000;
    controller_id = principal \"${PRINCIPAL}\";
  };
}})"

# Get the token canister ID
TOKEN_CANISTER_ID=$(dfx canister id ${TOKEN_CANISTER_NAME})
log_action "Token canister deployed with ID: ${TOKEN_CANISTER_ID}"

# Check our initial balance
log_action "Checking initial token balance..."
INITIAL_BALANCE=$(dfx canister call ${TOKEN_CANISTER_NAME} icrc1_balance_of "(record { owner = principal \"${PRINCIPAL}\" })" --query)
log_action "Initial token balance: ${INITIAL_BALANCE}"

# Deploy the airdrop canister
log_action "Deploying the airdrop canister..."
dfx deploy ${CANISTER_NAME}

log_action "Depositing cycles into canister balances"
dfx ledger fabricate-cycles --all --cycles ${CYCLES}

# Get the airdrop canister ID
AIRDROP_CANISTER_ID=$(dfx canister id ${CANISTER_NAME})
log_action "Airdrop canister deployed with ID: ${AIRDROP_CANISTER_ID}"

# Reset any existing allocations
log_action "Resetting existing allocations..."
dfx canister call ${CANISTER_NAME} reset

# Set the token canister ID in the airdrop canister
log_action "Setting token canister ID in airdrop canister..."
dfx canister call ${CANISTER_NAME} set_token_canister_id "(principal \"${TOKEN_CANISTER_ID}\")"

# Ask user for configuration
read -p "Do you want to generate random principals for testing? (y/n) [default: y]: " generate_random
generate_random=${generate_random:-y}

if [[ "$generate_random" == "y" || "$generate_random" == "Y" ]]; then
    read -p "Enter the number of principals to generate [default: 10]: " principal_count
    principal_count=${principal_count:-10}
    
    read -p "Enter minimum shares per principal [default: 1000]: " min_shares
    min_shares=${min_shares:-1000}
    
    read -p "Enter maximum shares per principal [default: 10000]: " max_shares
    max_shares=${max_shares:-10000}
    
    # Generate the allocation file with random principals
    TOTAL_SHARES=$(generate_random_principals "$principal_count" "$min_shares" "$max_shares" "$ALLOCATION_FILE")
    # Make sure TOTAL_SHARES is a valid number
    if ! [[ "$TOTAL_SHARES" =~ ^[0-9]+$ ]]; then
        log_action "ERROR: Failed to get valid total shares: $TOTAL_SHARES"
        TOTAL_SHARES=$(awk -F, '{sum+=$2} END {print sum}' "$ALLOCATION_FILE")
        log_action "Recalculated total shares from file: $TOTAL_SHARES"
    fi
    log_action "Created test allocation file: ${ALLOCATION_FILE} with total shares: ${TOTAL_SHARES}"
elif [ ! -f "${ALLOCATION_FILE}" ]; then
    log_action "No allocation file found and random generation declined. Creating a minimal test file..."
    # Create a small allocation file with test principals
    cat > "${ALLOCATION_FILE}" << EOF
$(dfx identity get-principal),5000
2vxsx-fae,1000
rrkah-fqaaa-aaaaa-aaaaq-cai,2000
renrk-eyaaa-aaaaa-aaada-cai,3000
EOF
    TOTAL_SHARES=11000
    log_action "Created minimal test allocation file: ${ALLOCATION_FILE} with total shares: ${TOTAL_SHARES}"
else
    log_action "Using existing allocation file: ${ALLOCATION_FILE}"
    # Calculate total shares in the existing file
    TOTAL_SHARES=0
    while IFS=, read -r _ shares; do
        # Skip invalid lines
        if [[ -z "$shares" || ! "$shares" =~ ^[0-9]+$ ]]; then
            continue
        fi
        TOTAL_SHARES=$((TOTAL_SHARES + shares))
    done < "${ALLOCATION_FILE}"
    log_action "Total shares in existing file: ${TOTAL_SHARES}"
fi

# Check share allocations before adding
log_action "Checking share allocations (should be empty)..."
dfx canister call ${CANISTER_NAME} get_shares_list "(0)"

# Add share allocations
log_action "Adding share allocations from file: ${ALLOCATION_FILE}"
if [ -f "${ALLOCATION_FILE}" ]; then
    log_action "Validating and processing allocation file..."
    
    # Create a cleaned and validated temp file
    TEMP_ALLOCATION=$(mktemp)
    
    # Clean up the allocation file to handle various formats
    while IFS= read -r line; do
        # Skip empty lines or comments
        if [[ -z "$line" || "$line" == \#* ]]; then
            continue
        fi
        
        # Split the line by comma
        principal=$(echo "$line" | cut -d, -f1 | xargs)  # Remove whitespace
        shares=$(echo "$line" | cut -d, -f2 | xargs)     # Remove whitespace
        
        # Skip invalid lines
        if [[ -z "$principal" || -z "$shares" ]]; then
            log_action "WARNING: Skipping invalid line: $line"
            continue
        fi
        
        # Validate that shares is a number
        if ! [[ "$shares" =~ ^[0-9]+$ ]]; then
            log_action "WARNING: Skipping line with non-numeric shares: $line"
            continue
        fi
        
        # Write the cleaned principal and shares to the temp file
        echo "$principal,$shares" >> "$TEMP_ALLOCATION"
    done < "${ALLOCATION_FILE}"
    
    # Check if we have any valid allocations
    if [ ! -s "$TEMP_ALLOCATION" ]; then
        log_action "ERROR: No valid allocations found in file!"
        rm -f "$TEMP_ALLOCATION"
        exit 1
    fi
    
    # Build the allocations vector
    ALLOCATIONS=""
    ALLOCATIONS_COUNT=0
    while IFS=, read -r principal shares; do
        if [ -n "${ALLOCATIONS}" ]; then
            ALLOCATIONS="${ALLOCATIONS}; "
        fi
        ALLOCATIONS="${ALLOCATIONS}record { principal \"${principal}\"; ${shares}:nat }"
        ALLOCATIONS_COUNT=$((ALLOCATIONS_COUNT + 1))
    done < "$TEMP_ALLOCATION"
    
    # Clean up temp file
    rm -f "$TEMP_ALLOCATION"
    
    # Execute the call
    log_action "Adding ${ALLOCATIONS_COUNT} share allocations..."
    dfx canister call ${CANISTER_NAME} add_share_allocations "(vec { ${ALLOCATIONS} })"
else
    log_action "WARNING: No allocation file found. Using example allocations..."
    dfx canister call ${CANISTER_NAME} add_share_allocations "(vec { 
        record { principal \"${PRINCIPAL}\"; 5000:nat }; 
        record { principal \"2vxsx-fae\"; 1000:nat }; 
        record { principal \"rrkah-fqaaa-aaaaa-aaaaq-cai\"; 2000:nat }; 
        record { principal \"renrk-eyaaa-aaaaa-aaada-cai\"; 3000:nat } 
    })"
fi

# Check share allocations after adding
log_action "Checking share allocations after adding..."
SHARES_BEFORE=$(dfx canister call ${CANISTER_NAME} get_shares_list "(0)")
echo "Share allocations before distribution:"
echo "${SHARES_BEFORE}"

# Transfer tokens to the airdrop canister
log_action "Transferring tokens to the airdrop canister for distribution..."
dfx canister call ${TOKEN_CANISTER_NAME} icrc1_transfer "(record {
  from_subaccount = null;
  to = record { owner = principal \"${AIRDROP_CANISTER_ID}\"; subaccount = null };
  amount = ${AIRDROP_TOTAL};
  fee = null;
  memo = null;
  created_at_time = null;
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

# Get all token allocations and verify distribution
log_action "Fetching token allocations from airdrop canister and verifying distribution..."

# First check if distribution was successful
if [[ "${DISTRIBUTION_RESULT}" == *"Err"* ]]; then
    log_action "Distribution failed, skipping verification"
    echo "Distribution failed. Cannot verify token allocations."
    exit 1
else
    # Get the total airdrop amount
    TRANSFER_AMOUNT_CLEAN=$(echo "$AIRDROP_TOTAL" | tr -d '_')
    
    # Calculate fee per transaction
    TOKEN_FEE=$(dfx canister call ${TOKEN_CANISTER_NAME} icrc1_fee --query)
    TOKEN_FEE=$(echo "$TOKEN_FEE" | grep -o '[0-9_]*' | tr -d '_')
    log_action "Token fee: ${TOKEN_FEE} per transaction"
    
    # Calculate total fees (assuming one transaction per principal)
    PRINCIPAL_COUNT=$(wc -l < "${ALLOCATION_FILE}")
    TOTAL_FEES=$((TOKEN_FEE * PRINCIPAL_COUNT))
    log_action "Total fees: ${TOTAL_FEES} for ${PRINCIPAL_COUNT} principals"
    
    # Calculate distributable amount
    DISTRIBUTABLE_AMOUNT=$((TRANSFER_AMOUNT_CLEAN - TOTAL_FEES))
    log_action "Distributable amount: ${DISTRIBUTABLE_AMOUNT} (transfer amount minus fees)"
    
    # Double-check that TOTAL_SHARES is a valid number
    if ! [[ "$TOTAL_SHARES" =~ ^[0-9]+$ ]]; then
        log_action "WARNING: TOTAL_SHARES is not a valid number: $TOTAL_SHARES"
        TOTAL_SHARES=$(awk -F, '{sum+=$2} END {print sum}' "$ALLOCATION_FILE")
        log_action "Recalculated total shares from file: $TOTAL_SHARES"
    fi
    
    # Process allocations to build a map of principal to shares
    declare -A SHARES_MAP
    while IFS=, read -r principal shares; do
        # Skip invalid lines
        if [[ -z "$principal" || -z "$shares" || "$principal" == \#* ]]; then
            continue
        fi
        SHARES_MAP["$principal"]="$shares"
    done < "${ALLOCATION_FILE}"
    
    # Fetch all pages of token allocations
    INDEX=0
    RESULTS_DIR=$(mktemp -d)
    
    # Test for pagination by fetching pages until we get an empty result
    log_action "Fetching all token allocation pages..."
    PAGE=0
    TOTAL_RECORDS=0
    
    while true; do
        TEMP_FILE="${RESULTS_DIR}/page_${PAGE}.txt"
        dfx canister call ${CANISTER_NAME} get_tokens_list "(${INDEX})" > "$TEMP_FILE"
        
        # Print the raw output for debugging
        log_action "Page $PAGE response at index $INDEX:"
        cat "$TEMP_FILE" >> "${RESULTS_DIR}/all_responses.txt"
        
        # Count records in this page by counting principal occurrences
        RECORDS_COUNT=$(grep -o "principal" "$TEMP_FILE" | wc -l)
        log_action "Page $PAGE: Found $RECORDS_COUNT records at index $INDEX"
        
        # If empty result (vec {}) or no principal found, break the loop
        if grep -q "vec {}" "$TEMP_FILE" || [ "$RECORDS_COUNT" -eq 0 ]; then
            break
        fi
        
        TOTAL_RECORDS=$((TOTAL_RECORDS + RECORDS_COUNT))
        INDEX=$((INDEX + 100))
        PAGE=$((PAGE + 1))
    done
    
    log_action "Found $TOTAL_RECORDS total token allocations across $PAGE pages"
    
    # Create combined file of all results for processing
    COMBINED_FILE="${RESULTS_DIR}/combined.txt"
    for ((i=0; i<PAGE; i++)); do
        cat "${RESULTS_DIR}/page_${i}.txt" >> "$COMBINED_FILE"
    done
    
    # Create a simplified version for easier parsing
    SIMPLIFIED_FILE="${RESULTS_DIR}/simplified.txt"
    cat "$COMBINED_FILE" | tr '\n' ' ' | sed 's/record {/\nrecord {/g' > "$SIMPLIFIED_FILE"
    
    # Create debug file to see raw output
    DEBUG_FILE="${RESULTS_DIR}/debug_raw_output.txt"
    for ((i=0; i<PAGE; i++)); do
        echo "==== PAGE $i CONTENTS ====" >> "$DEBUG_FILE"
        cat "${RESULTS_DIR}/page_${i}.txt" >> "$DEBUG_FILE"
        echo -e "\n\n" >> "$DEBUG_FILE"
    done
    
    log_action "Saved raw output to $DEBUG_FILE for debugging"
    
    # Extract principal IDs and amounts from the simplified file
    PARSED_ALLOCATIONS="${RESULTS_DIR}/parsed_allocations.txt"
    grep -o 'record {[^}]*}' "$SIMPLIFIED_FILE" | while read -r record; do
        # Extract principal
        if [[ $record =~ principal\ \"([^\"]+)\" ]]; then
            PRINCIPAL="${BASH_REMATCH[1]}"
            
            # Extract amount
            if [[ $record =~ ([0-9_]+)\ :\ nat ]]; then
                AMOUNT=$(echo "${BASH_REMATCH[1]}" | tr -d '_')
                echo "$PRINCIPAL,$AMOUNT" >> "$PARSED_ALLOCATIONS"
            else
                echo "$PRINCIPAL," >> "$PARSED_ALLOCATIONS"
            fi
        fi
    done
    
    # Process all allocations
    log_action "Processing allocation results..."
    
    # Now print the table header after all logging is done
    echo ""
    echo "User Token Allocations After Distribution:"
    echo "---------------------------------------------------------------------------------"
    echo "| Principal ID                                   | Share  | Expected  | Actual   | Match       |"
    echo "---------------------------------------------------------------------------------"
    
    # Read the parsed allocations file and display each entry with verification
    while IFS=, read -r PRINCIPAL AMOUNT; do
        # Find the share for this principal
        SHARE="${SHARES_MAP[$PRINCIPAL]}"
        
        if [[ -n "$SHARE" ]]; then
            # Calculate expected token amount: (share / total_shares) * distributable_amount
            # Using bc for more accurate floating point calculation
            EXPECTED_TOKENS=$(echo "scale=0; ($SHARE * $DISTRIBUTABLE_AMOUNT) / $TOTAL_SHARES" | bc)
            
            # Check if the actual amount is exactly the expected amount or within 0.1%
            if [[ -z "$AMOUNT" ]]; then
                MATCH_ICON="❌ Missing"
            else
                DIFF=$(echo "scale=4; 100 * ($AMOUNT - $EXPECTED_TOKENS) / $EXPECTED_TOKENS" | bc 2>/dev/null || echo "ERROR")
                
                if [[ "$DIFF" == "ERROR" ]]; then
                    MATCH_ICON="❌ ERROR"
                elif (( $(echo "$DIFF == 0" | bc -l) )); then
                    MATCH_ICON="✓ exact"
                elif (( $(echo "$DIFF < 0.1 && $DIFF > -0.1" | bc -l) )); then
                    MATCH_ICON="✓ (${DIFF}%)"
                else
                    MATCH_ICON="❌ (${DIFF}%)"
                fi
            fi
            
            # Format the output with fixed column widths
            printf "| %-45s | %-6s | %-9s | %-9s | %-11s |\n" "$PRINCIPAL" "$SHARE" "$EXPECTED_TOKENS" "${AMOUNT:-N/A}" "$MATCH_ICON"
        else
            printf "| %-45s | %-6s | %-9s | %-9s | %-11s |\n" "$PRINCIPAL" "Unknown" "N/A" "${AMOUNT:-N/A}" "N/A"
        fi
    done < "$PARSED_ALLOCATIONS"
    
    # Clean up
    rm -rf "$RESULTS_DIR"
fi
echo "---------------------------------------------------------------------------------"
log_action "Verification completed."

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
echo "  dfx canister call ${TOKEN_CANISTER_NAME} icrc1_transfer \"(record { from_subaccount = null; to = record { owner = principal \\\"RECIPIENT_ID\\\"; subaccount = null }; amount = AMOUNT; fee = null; memo = null; created_at_time = null })\""

dfx canister status $CANISTER_NAME
dfx canister status $TOKEN_CANISTER_NAME