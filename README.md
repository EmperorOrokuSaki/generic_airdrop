# Generic Airdrop Canister

## Overview

The Generic Airdrop Canister facilitates token airdrops to a specified dataset of users and their respective shares, as defined in a CSV file. The canister is populated with user data via the `extract_csv.sh` script.

## Specification

### Features

- **CSV File Upload**: Use `extract_csv.sh` to upload a CSV file containing user data and their respective token shares.
- **Automated Airdrop Execution**: Automatically distributes tokens to users based on the CSV data.

### CSV File Format

The CSV file should have the following columns:

- **Columns**: `Principal`, `Amount`
- **Example**:
  ```csv
  Principal,Amount
  user-principal-1,100
  user-principal-2,200
  ```

### Shell Script

- **extract_csv.sh**: This script reads the CSV file and populates the canister with the data.
    ```sh
    ./extract_csv.sh path/to/your/file.csv
    ```

## Deployment

Follow these steps to deploy and configure the canister:

1. Deploy the canister on the IC mainnet:
    ```sh
    dfx deploy --ic
    ```
2. Upload the CSV file containing user data using the `extract_csv.sh` script:
    ```sh
    ./extract_csv.sh path/to/your/file.csv
    ```

## Configuration

### Setting the Token Canister

- Configure the token canister from which tokens will be airdropped:
    ```sh
    dfx canister call --ic airdrop_canister set_token_canister_id '(principal "TOKEN_CANISTER_ID")'
    ```

### Distributing Tokens

- Start the airdrop process by specifying the total amount of tokens to distribute:
    ```sh
    dfx canister call --ic airdrop_canister distribute '(TOTAL_TOKENS_AMOUNT)'
    ```

## Query Methods

The canister exposes the following query methods:

- Get the amount of shares a user has:
    ```sh
    dfx canister call --ic airdrop_canister get_user_allocation '(principal "USER_PRINCIPAL_ID")'
    ```
- Get the list of users and their respective token shares:
    ```sh
    dfx canister call --ic airdrop_canister get_user_list
    ```

## Acknowledgments

This canister was developed to simplify the process of conducting token airdrops to multiple users efficiently and accurately. It can be used by any organization or individual needing to perform airdrops based on a predefined dataset.