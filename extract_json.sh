#!/bin/bash

# Ensure a JSON file is provided as an argument
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <json_file>"
    exit 1
fi

JSON_FILE=$1

# Initialize variables to hold the vector elements and the counter
vector_data=""
counter=0
total_entries=$(jq '. | length' "$JSON_FILE")
current_entry=0

# Function to make the dfx canister call with the constructed vector
make_call() {
    local vector_data="$1"
    command="dfx canister call --ic airdrop_canister add_share_allocations '(vec {${vector_data}})'"
    echo "Running: $command"
    echo "$command"
    eval "$command"
}

# Read the JSON file and process the Principal and Amount fields
jq -c '.[]' "$JSON_FILE" | while read -r line; do
    principal=$(echo "$line" | jq -r '.Principal')
    amount=$(echo "$line" | jq -r '.Amount')

    # Skip if the amount is 0 or empty
    if [ -z "$amount" ] || [ "$amount" -eq 0 ]; then
        continue
    fi

    # Append the extracted values to the vector data
    vector_data+="record {principal \"$principal\"; $amount};"

    # Increment the counter and check if it reached the limit of 100 items
    counter=$((counter + 1))
    current_entry=$((current_entry + 1))

    if [ "$counter" -ge 100 ]; then
        # Make the canister call with the current vector data
        make_call "$vector_data"
        
        # Reset the vector data and counter
        vector_data=""
        counter=0
    fi

    # Check if this is the last entry
    if [ "$current_entry" -eq "$total_entries" ]; then
        # Make the final call with any remaining data
        if [ -n "$vector_data" ]; then
            make_call "$vector_data"
        fi
    fi
done
