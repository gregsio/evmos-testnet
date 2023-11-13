#!/bin/bash
# used to exit on first error (any non-zero exit code)
set -e
trap 'echo "Error on line $LINENO";' ERR

CHAINID="${CHAIN_ID:-evmos_9000-4}"
MONIKER="testnetvalidator-gregsio"
# Remember to change to other types of keyring like 'file' in-case exposing to outside world,
# otherwise your balance will be wiped quickly
# The keyring test does not require private key to steal tokens from you
KEYRING="test"
KEYALGO="eth_secp256k1"
LOGLEVEL="info"

# Set dedicated home directory for the evmosd instance
HOMEDIR="~/.evmosd"
CONFIGDIR="$HOMEDIR/config"

# Path variables
CONFIG=$CONFIGDIR/config.toml
APP_TOML=$CONFIGDIR/app.toml
GENESIS=$CONFIGDIR/genesis.json

# Parse input flags
install=true
overwrite=""

for cmd in jq curl evmosd; do
    command -v $cmd >/dev/null 2>&1 || { echo >&2 "$cmd is required but it's not installed. Aborting."; exit 1; }
done

while [[ $# -gt 0 ]]; do
	key="$1"
	case $key in
	-y)
		echo "Flag -y passed -> Overwriting the previous chain data."
		overwrite="y"
		shift # Move past the flag
		;;
	-n)
		echo "Flag -n passed -> Not overwriting the previous chain data."
		overwrite="n"
		shift # Move past the argument
		;;
	*)
		echo "Unknown flag passed: $key -> Exiting script!"
		exit 1
		;;
	esac
done

if [[ $overwrite = "" ]]; then
	if [ -d "$HOMEDIR" ]; then
		printf "\nAn existing folder at '%s' was found. You can choose to delete this folder and start a new local node with new keys from genesis. When declined, the existing local node is started. \n" "$HOMEDIR"
		echo "Overwrite the existing configuration and start a new local node? [y/n]"
		read -r overwrite
	else
		overwrite="y"
	fi
fi

if [[ $overwrite == "y" || $overwrite == "Y" ]]; then
	# Remove the previous folder
	rm -rf "$HOMEDIR"

    # Setup client config
    evmosd config chain-id "$CHAINID" --home "$HOMEDIR"
    evmosd config keyring-backend "$KEYRING" --home "$HOMEDIR"

    # Polkachu endpoint - see https://polkachu.com/testnets/evmos/state_sync
    SNAP_RPC="https://evmos-testnet-rpc.polkachu.com:443"
    LATEST_HEIGHT=$(curl -s "$SNAP_RPC/block" | jq -r .result.block.header.height); \
    BLOCK_HEIGHT=$((LATEST_HEIGHT - 2000)); \
    TRUST_HASH=$(curl -s "$SNAP_RPC/block?height=$BLOCK_HEIGHT" | jq -r .result.block_id.hash)

    # Import keys from mnemonics
    # myKey address 0x7cb61d4117ae31a12e393a1cfa3bac666481d02e | evmos10jmp6sgh4cc6zt3e8gw05wavvejgr5pwjnpcky
    VAL_KEY="mykey"
    VAL_MNEMONIC="gesture inject test cycle original hollow east ridge hen combine junk child bacon zero hope comfort vacuum milk pitch cage oppose unhappy lunar seat"
    echo "$VAL_MNEMONIC" | evmosd keys add "$VAL_KEY" --recover --keyring-backend "$KEYRING" --algo "$KEYALGO" --home "$HOMEDIR"

    # Store the validator address in a variable to use it later
    node_address=$(evmosd keys show -a "$VAL_KEY" --keyring-backend "$KEYRING" --home "$HOMEDIR")

    # Set moniker and chain-id for Evmos (Moniker can be anything, chain-id must be an integer)
    echo "init"
    evmosd init $MONIKER --chain-id "$CHAINID" --home "$HOMEDIR"

    # Allocate genesis accounts (cosmos formatted addresses)
    evmosd add-genesis-account "$(evmosd keys show "$VAL_KEY" -a --keyring-backend "$KEYRING" --home "$HOMEDIR")" 100000000000000000000000000aevmos --keyring-backend "$KEYRING" --home "$HOMEDIR"

    # Enable prometheus metrics and all APIs for dev node
    sed -i 's/prometheus = false/prometheus = true/' "$CONFIG"
    sed -i 's/prometheus-retention-time  = "0"/prometheus-retention-time  = "1000000000000"/g' "$APP_TOML"
    sed -i 's/enabled = false/enabled = true/g' "$APP_TOML"
    sed -i 's/enable = false/enable = true/g' "$APP_TOML"
    # Don't enable memiavl by default
    grep -q -F '[memiavl]' "$APP_TOML" && sed -i '/\[memiavl\]/,/^\[/ s/enable = true/enable = false/' "$APP_TOML"

    # Config updates
    echo "config"
    sed -i.bak -E "s|^(enable[[:space:]]+=[[:space:]]+).*$|\1true| ; \
    s|^(rpc_servers[[:space:]]+=[[:space:]]+).*$|\1\"$SNAP_RPC,$SNAP_RPC\"| ; \
    s|^(trust_height[[:space:]]+=[[:space:]]+).*$|\1$BLOCK_HEIGHT| ; \
    s|^(trust_hash[[:space:]]+=[[:space:]]+).*$|\1\"$TRUST_HASH\"|" $CONFIG

    update_or_add() {
        key=$1
        value=$2

        # Check if the instruction exists
        if grep -q "^$key = " $CONFIG; then
            # If the instruction exists, update it using sed
            sed -i -e "s/^$key = .*/$key = $value/" $CONFIG
        else
            # If the instruction doesn't exist, add it using echo
            echo "$key = $value" >> $CONFIG
        fi
    }

    # Update or add the configuration instructions
    update_or_add "pruning" "\"custom\""
    update_or_add "pruning-keep-every" "2000"
    update_or_add "snapshot-interval" "2000"
    update_or_add "snapshot-keep-recent" "5"

    echo "reset"
    evmosd tendermint unsafe-reset-all --home $HOMEDIR --keep-addr-book
fi