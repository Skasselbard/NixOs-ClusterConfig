#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${1:-}"
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Usage: $0 <config.json>"
  exit 1
fi

if ! command -v jq &>/dev/null || ! command -v certstrap &>/dev/null; then
  echo "Missing dependencies: install jq and certstrap"
  exit 1
fi

CONFIG_JSON="$(< "$CONFIG_FILE")"

CA_NAME=$(echo "$CONFIG_JSON" | jq -r '.k8s.ca.name')
CA_PASSPHRASE=$(echo "$CONFIG_JSON" | jq -r '.k8s.ca.passPhrase')
ORG=$(echo "$CONFIG_JSON" | jq -r '.common.org')
ORG_UNIT=$(echo "$CONFIG_JSON" | jq -r '.common.orgUnit')
COUNTRY=$(echo "$CONFIG_JSON" | jq -r '.common.country')
PROVINCE=$(echo "$CONFIG_JSON" | jq -r '.common.province')
LOCALITY=$(echo "$CONFIG_JSON" | jq -r '.common.locality')

if [[ ! -f "$CA_NAME.crt" ]]; then
  echo "[INFO] Creating Kubernetes CA: $CA_NAME"
  certstrap --depot-path "." init \
    --curve P-256 \
    --organization "$ORG" \
    --organizational-unit "$ORG_UNIT" \
    --country "$COUNTRY" \
    --province "$PROVINCE" \
    --locality "$LOCALITY" \
    --common-name "$CA_NAME" \
    --expires "10 year" \
    --passphrase "$CA_PASSPHRASE"
else
  echo "[INFO] CA already exists: $CA_NAME.crt"
fi
