# Generic Airdrop Canister

## Overview

The Generic Airdrop Canister facilitates token airdrops to a specified dataset of users and their respective shares, as defined in a JSON file. The canister is populated with user data via the `extract_json.sh` script.

## Specification

### Features

- **JSON File Upload**: Use `extract_json.sh` to upload a JSON file containing user data and their respective token shares.
- **Automated Airdrop Execution**: Automatically distributes tokens to users based on the JSON data.
- **Error Handling**: Handles various errors and provides appropriate feedback.

### JSON File Format

The JSON file should have the following structure:

- **Structure**:
  ```json
  [
    {
      "Principal": "user-principal-1",
      "Amount": 100
    },
    {
      "Principal": "user-principal-2",
      "Amount": 200
    }
  ]
  ```

## Deployment

Follow these steps to deploy and configure the canister:

1. Deploy the canister on the IC mainnet:
    ```sh
    dfx deploy --ic
    ```
2. Upload the JSON file containing user data using the `extract_json.sh` script:
    ```sh
    ./extract_json.sh path/to/your/file.json
    ```

## Configuration

### Setting the Token Canister

- Configure the token canister from which tokens will be airdropped:
    ```sh
    dfx canister call --ic airdrop_canister set_token_canister_id '(principal "TOKEN_CANISTER_ID")'
    ```


### Shell Script

- **extract_json.sh**: This script reads the JSON file and populates the canister with the data.
    ```sh
    ./extract_json.sh path/to/your/file.json
    ```

### Distributing Tokens

- Start the airdrop process:
    ```sh
    dfx canister call --ic airdrop_canister distribute
    ```

### Resetting the Airdrop

- Reset the canister for a new airdrop:
    ```sh
    dfx canister call --ic airdrop_canister reset
    ```

## Query Methods

The canister exposes the following query methods:

- Get the amount of shares allocated to a user:
    ```sh
    dfx canister call --ic airdrop_canister get_user_share_allocation '(principal "USER_PRINCIPAL_ID")'
    ```
- Get the amount of tokens allocated to a user:
    ```sh
    dfx canister call --ic airdrop_canister get_user_token_allocation '(principal "USER_PRINCIPAL_ID")'
    ```
- Get the list of users and their respective token shares (paginated):
    ```sh
    dfx canister call --ic airdrop_canister get_tokens_list '(OFFSET)'
    ```
- Get the list of users and their respective share allocations (paginated):
    ```sh
    dfx canister call --ic airdrop_canister get_shares_list '(OFFSET)'
    ```

## Acknowledgments

This canister was developed for the ICP CC DAO to simplify the process of conducting token airdrops to multiple users efficiently and accurately. It can be used by any organization or individual needing to perform airdrops based on a predefined dataset.