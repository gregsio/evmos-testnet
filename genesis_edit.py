#!/usr/bin/env python3

import ijson
import json
import os
import sys

def process_json(file_path):
    backup_path = f"{file_path}.bak"
    os.rename(file_path, backup_path)

    with open(backup_path, 'rb') as input_file:
        objects = ijson.items(input_file, '')
        for obj in objects:
            obj['app_state']['staking']['params']['bond_denom'] = 'aevmos'
            obj['app_state']['crisis']['constant_fee']['denom'] = 'aevmos'
            obj['app_state']['gov']['deposit_params']['min_deposit'][0]['denom'] = 'aevmos'
            #obj['app_state']['gov']['params']['min_deposit'][0]['denom'] = 'aevmos'
            obj['app_state']['evm']['params']['evm_denom'] = 'aevmos'
            obj['app_state']['inflation']['params']['mint_denom'] = 'aevmos'
            with open(file_path, 'w') as output_file:
                json.dump(obj, output_file, ensure_ascii=False, indent=2)

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_genesis.json>")
        sys.exit(1)
    process_json(sys.argv[1])
