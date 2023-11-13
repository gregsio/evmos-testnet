#!/bin/bash

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

# to trace evm
#TRACE="--trace"
TRACE=""

# Path variables
CONFIG=$HOMEDIR/config/config.toml
APP_TOML=$HOMEDIR/config/app.toml
GENESIS=$HOMEDIR/config/genesis.json
TMP_GENESIS=$HOMEDIR/config/tmp_genesis.json

# validate dependencies are installed
command -v jq >/dev/null 2>&1 || {
	echo >&2 "jq not installed. More info: https://stedolan.github.io/jq/download/"
	exit 1
}

command -v wget >/dev/null 2>&1 || {
	echo >&2 "wget not installed."
	exit 1
}

# used to exit on first error (any non-zero exit code)
set -e

# Parse input flags
overwrite=""
snapshotsync=0

while [[ $# -gt 0 ]]; do
	key="$1"
	case $key in
	-y)
		echo "Flag -y passed -> Overwriting the previous chain data."
		overwrite="y"
		shift # Move past the flag
		;;
	-n)
		echo "Flag -n passed -> Not overwriting the previous config "
		overwrite="n"
		shift # Move past the argument
		;;
	-s)
		echo "Flag -s passed -> Overwriting data with latest testnet snapshot"
		snapshotsync=1
		shift # Move past the argument
		;;
	*)
		echo "Unknown flag passed: $key -> Exiting script!"
		exit 1
		;;
	esac
done

# User prompt if neither -y nor -n was passed as a flag
# and an existing local node configuration is found.
if [[ $overwrite = "" ]]; then
	if [ -d "$HOMEDIR" ]; then
		printf "\nAn existing folder at '%s' was found. You can choose to delete this folder and start a new local node with new keys from genesis. When declined, the existing local node is started. \n" "$HOMEDIR"
		echo "Overwrite the existing configuration and start a new local node? [y/n]"
		read -r overwrite
	else
		overwrite="y"
	fi
fi

# Setup local node if overwrite is set to Yes, otherwise skip setup
if [[ $overwrite == "y" || $overwrite == "Y" ]]; then
	# Remove the previous folder
	rm -rf "$HOMEDIR/*"
	evmosd init $MONIKER --chain-id "$CHAINID" --home "$HOMEDIR"
	evmosd config keyring-backend "$KEYRING" --home "$HOMEDIR"

	# Set client config
	echo "client config"
	evmosd config chain-id "$CHAINID" --home "$HOMEDIR"

	# myKey address 0x7cb61d4117ae31a12e393a1cfa3bac666481d02e | evmos10jmp6sgh4cc6zt3e8gw05wavvejgr5pwjnpcky
	VAL_KEY="mykey"
	VAL_MNEMONIC="gesture inject test cycle original hollow east ridge hen combine junk child bacon zero hope comfort vacuum milk pitch cage oppose unhappy lunar seat"

	echo "VAL_KEY $VAL_KEY"
	# Import keys from mnemonics
	echo "$VAL_MNEMONIC" | evmosd keys add "$VAL_KEY" --recover --keyring-backend "$KEYRING" --algo "$KEYALGO" --home "$HOMEDIR"

	# Store the validator address in a variable to use it later
	node_address=$(evmosd keys show -a "$VAL_KEY" --keyring-backend "$KEYRING" --home "$HOMEDIR")

	# Set moniker and chain-id for Evmos (Moniker can be anything, chain-id must be an integer)
	#evmosd tendermint unsafe-reset-all --home "$HOMEDIR"

	# Download Genesis file for testnet evmos_9000-4, not needed with snapshot sync
	if [ "$snapshotsync" -eq 0 ]; then
		if [ -f ${GENESIS}] ; then
			rm -f ${GENESIS}
		fi
	# wget -O ${GENESIS} https://archive.evmos.dev/evmos_9000-4/genesis.json
	# wget -O ${GENESIS} https://snapshots.polkachu.com/testnet-genesis/evmos/genesis.json
	  wget -O ${GENESIS} https://qubelabs.io/evmos/genesis.json
	fi

	# Update persistent_peers and seeds for testnet setup
	# https://github.com/evmos/testnets/issues/2862
	# PEERS=`curl -sL https://raw.githubusercontent.com/evmos/testnets/main/evmos_9000-4/peers.txt | sort -r | head -n 10 | awk '{print $1}' | paste -s -d, -`
	# sed -i.bak -e "s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" ${CONFIG}

	PEERS="182be4eedbc3a3b6d3174f39c18a23ccc86b04ca@142.132.130.222:26661,81d580f9d75f5bb224d262f3d2960fb3a74d1f58@65.109.39.50:33656,940a407248badb7c77397f22e48fb31c690184d0@27.75.78.95:16758,2dd78738cf0cb2779d6dfa79236c0236f1d58248@65.109.24.78:15656,7797a37a0b3f0296949c3a537dcc151b4ce86e84@78.46.107.187:17056"
	sed -i.bak -e "s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" ${CONFIG}

	SEEDS="ade4d8bc8cbe014af6ebdf3cb7b1e9ad36f412c0@testnet-seeds.polkachu.com:13456"
	sed -i '/^seeds =/s/^/#/; /^#seeds =/a seeds = "'"$SEEDS"'"' ${CONFIG}

	# enable prometheus metrics and all APIs for dev node

	sed -i 's/prometheus = false/prometheus = true/' "$CONFIG"
	sed -i 's/prometheus-retention-time  = "0"/prometheus-retention-time  = "1000000000000"/g' "$APP_TOML"
	sed -i 's/enabled = false/enabled = true/g' "$APP_TOML"
	sed -i 's/enable = false/enable = true/g' "$APP_TOML"
	# Don't enable memiavl by default
	grep -q -F '[memiavl]' "$APP_TOML" && sed -i '/\[memiavl\]/,/^\[/ s/enable = true/enable = false/' "$APP_TOML"


	# Edit genesys file in python to parse the JSON file in a streaming manner
	# Less memory intensive
	# echo "editing genesis"
	# /usr/bin/genesis_edit.py $GENESIS

	# Run this to ensure everything worked and that the genesis file is setup correctly
	# echo "validating genesis"
	# evmosd validate-genesis --home "$HOMEDIR"
fi

# Download Snapshot
if [ "$snapshotsync" -eq 1 ]; then
	echo "Fetching snapshot and overwriting ${HOMEDIR}/data"
	(/usr/bin/snapshot.sh)
fi

	# echo "evmosd tx staking create-validator ..."
	# evmosd tx staking create-validator \
	# --amount=1000000atevmos \
	# --pubkey=$(evmosd tendermint show-validator) \
	# --moniker="${MONIKER}" \
	# --chain-id='evmos_9000-4' \
	# --commission-rate="0.05" \
	# --commission-max-rate="0.10" \
	# --commission-max-change-rate="0.01" \
	# --min-self-delegation="1000000" \
	# --gas="auto" \
	# --gas-prices="0.025atevmos" \
	# --from='mykey' \
	# --home="${HOMEDIR}"

# evmosd tx staking create-validator \
#   --amount=1000000000atevmos \
#   --pubkey=$(evmosd tendermint show-validator) \
#   --moniker="EvmosWhale" \
#   --chain-id=evmos_9000-4 \
#   --commission-rate="0.10" \
#   --commission-max-rate="0.20" \
#   --commission-max-change-rate="0.01" \
#   --min-self-delegation="1000000" \
#   --gas="auto" \
#   --gas-prices="0.025atevmos" \
#   --from='mykey'



# Start the node
evmosd start \
	--metrics "$TRACE" \
	--log_level $LOGLEVEL \
	--json-rpc.api eth,txpool,personal,net,debug,web3 \
	--home "$HOMEDIR"


# evmosd start \
	# --metrics "" \
	# --log_level info \
	# --json-rpc.api eth,txpool,personal,net,debug,web3 \
	# --home "/evmos/evmosd"
