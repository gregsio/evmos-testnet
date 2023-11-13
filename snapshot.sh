#!/bin/bash

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
HOMEDIR="~/.evmosd"
CONFIGDIR="$HOMEDIR/config"
DATADIR="$HOMEDIR/data"

# Fetch current snapshot URL
SNAPSHOTURL=$(curl -s https://polkachu.com/testnets/evmos/snapshots | grep -o 'https[^"]*.lz4' | head -n 1)

echo $SNAPSHOTURL
echo $SNAPSHOTNAME

# Path variables
CONFIG="$CONFIGDIR/config.toml"
APP_TOML="$CONFIGDIR/app.toml"
GENESIS="$CONFIGDIR/genesis.json"

for cmd in curl lz4 evmosd; do
    command -v $cmd >/dev/null 2>&1 || { echo >&2 "$cmd is required but it's not installed. Aborting."; exit 1; }
done

# Stream the snapshot into database location.
curl -o - -L ${SNAPSHOTURL} \
    | lz4 -c -d - \
    | tar -x -C $HOMEDIR \
    || { echo "Failed to download & decompress snapshot ${SNAPSHOTURL}. check https://polkachu.com/testnets/evmos/snapshots"; exit 1; }

cp ${DATADIR}/priv_validator_state.json  ${CONFIGDIR}/priv_validator_state.json

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

# Configuration for snapshot sync
update_or_add "pruning" "\"custom\"" "$APP_TOML"
update_or_add "pruning-keep-recent" "100" "$APP_TOML"
update_or_add "pruning-keep-every" "0" "$APP_TOML"
update_or_add "pruning-interval" "10" "$APP_TOML"
sed -i 's/indexer = kv/indexer = null/g' "$CONFIG"


# Remove all the data and WAL, reset this node's validator to genesis state
#evmosd tendermint unsafe-reset-all --home ${HOMEDIR} --keep-addr-book --keyring-backend ${KEYRING}
