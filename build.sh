#!/bin/bash
cd airdrop_canister
cargo run --features export-api > candid.did
cd ..
cargo build --release --target wasm32-unknown-unknown --features export-api