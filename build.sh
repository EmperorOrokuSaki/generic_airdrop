#!/bin/bash
cd icpcc_airdrop
cargo run --features export-api > candid.did
cd ..
cargo build --release --target wasm32-unknown-unknown --features export-api