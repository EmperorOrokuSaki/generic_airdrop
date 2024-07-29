#!/bin/bash

# Ensure a CSV file is provided as an argument
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <csv_file>"
    exit 1
fi

CSV_FILE=$1

# Read the header and check if it contains "principal" and "amount"
header=$(head -n 1 "$CSV_FILE")
if ! echo "$header" | grep -q "Principal" || ! echo "$header" | grep -q "Amount"; then
    echo "CSV header must contain 'principal' and 'amount'"
    exit 1
fi

# Get the indices of "principal" and "amount" columns
principal_idx=$(echo "$header" | awk -F, '{for(i=1;i<=NF;i++) if($i=="principal") print i}')
amount_idx=$(echo "$header" | awk -F, '{for(i=1;i<=NF;i++) if($i=="amount") print i}')

# Initialize an array to hold the vector elements
vector=()

# Function to make the dfx canister call with the constructed vector
make_call() {
    local vector_data="$1"
    command="dfx canister call --ic airdrop_canister add_allocations '(vec {${vector_data}})'"
    echo "Running: $command"
    eval $command
}

# Read the CSV file and extract the principal and amount columns, skipping the header
tail -n +2 "$CSV_FILE" | while IFS=, read -r line; do
    # Extract principal and amount values using the calculated indices
    principal=$(echo "$line" | cut -d ',' -f $principal_idx)
    amount=$(echo "$line" | cut -d ',' -f $amount_idx)

    # Append the extracted values to the vector data
    vector_data+="(principal \"$principal\", $amount);"

    # Increment the counter and check if it reached the limit of 100 items
    counter=$((counter + 1))
    if [ "$counter" -ge 100 ]; then
        # Make the canister call with the current vector data
        make_call "$vector_data"
        
        # Reset the vector data and counter
        vector_data=""
        counter=0
    fi
done

# Make the final call if there are remaining items
if [ "$counter" -gt 0 ]; then
    make_call "$vector_data"
fi
