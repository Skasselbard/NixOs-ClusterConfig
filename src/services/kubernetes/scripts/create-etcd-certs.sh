#!/usr/bin/env bash
set -euo pipefail

# Usage: ./create-etcd-certs.sh ./etcd-cert-config.json

CONFIG_FILE="${1:-}"
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Usage: $0 <config.json>"
  exit 1
fi

# Requirements: jq, certstrap
if ! command -v jq &>/dev/null || ! command -v certstrap &>/dev/null; then
  echo "Missing dependencies: install jq and certstrap"
  exit 1
fi

CONFIG_JSON="$(< "$CONFIG_FILE")"
# CERT_PATH=$(echo "$CONFIG_JSON" | jq -r '.certPath')
CA_NAME=$(echo "$CONFIG_JSON" | jq -r '.ca.name')
CA_PASSPHRASE=$(echo "$CONFIG_JSON" | jq -r '.ca.passPhrase')
SERVER_NAME=$(echo "$CONFIG_JSON" | jq -r '.server.name')
SERVER_PASSPHRASE=$(echo "$CONFIG_JSON" | jq -r '.server.passPhrase')
ORG=$(echo "$CONFIG_JSON" | jq -r '.certData.org')
ORG_UNIT=$(echo "$CONFIG_JSON" | jq -r '.certData.orgUnit')
COUNTRY=$(echo "$CONFIG_JSON" | jq -r '.certData.country')
PROVINCE=$(echo "$CONFIG_JSON" | jq -r '.certData.province')
LOCALITY=$(echo "$CONFIG_JSON" | jq -r '.certData.locality')

# Prepare DNS and IP arrays
mapfile -t SERVER_DOMAIN_LIST < <(echo "$CONFIG_JSON" | jq -r '.server.domains[]')
mapfile -t SERVER_IPS_LIST < <(echo "$CONFIG_JSON" | jq -r '.server.ips[]')

if [[ ${#SERVER_DOMAIN_LIST[@]} -eq 0 && ${#SERVER_IP_LIST[@]} -eq 0 ]]; then
  echo "[ERROR] At least one --domain or --ip is required for certstrap"
  exit 1
fi

CA_CRT="$CA_NAME.crt"
SERVER_CRT="$SERVER_NAME.crt"

# Step 1: Create CA certificate if it doesn't exist
if [[ ! -f "$CA_CRT" ]]; then
  echo "[INFO] Creating etcd CA certificate"
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
  echo "[WARN] CA certificate already exists: $CA_CRT — skipping"
fi

# Step 2: Create server certificate request and sign
if [[ ! -f "$SERVER_CRT" ]]; then
  echo "[INFO] Creating etcd server certificate request"

# Build domain and IP arguments
DOMAIN_ARG=""
if [ ${#SERVER_DOMAIN_LIST[@]} -gt 0 ]; then
  DOMAIN_ARG="--domain $(IFS=,; echo "${SERVER_DOMAIN_LIST[*]}")"
fi

# Join IP list into comma-separated string
IP_ARG=""
if [ ${#SERVER_IPS_LIST[@]} -gt 0 ]; then
  IP_ARG="--ip $(IFS=,; echo "${SERVER_IPS_LIST[*]}")"
fi

# set -x
  certstrap --depot-path "." request-cert \
    --curve P-256 \
    --common-name "$SERVER_NAME" \
    $DOMAIN_ARG \
    $IP_ARG \
    --organization "$ORG" \
    --organizational-unit "$ORG_UNIT" \
    --country "$COUNTRY" \
    --province "$PROVINCE" \
    --locality "$LOCALITY" \
    --passphrase "$SERVER_PASSPHRASE"

  echo "[INFO] Signing etcd server certificate"
  certstrap --depot-path "." sign \
    --csr "$SERVER_NAME.csr" \
    --cert "$SERVER_NAME.crt" \
    --CA "$CA_NAME" \
    --expires "5 year" \
    $SERVER_NAME

  chmod 0444 "$SERVER_NAME.crt"
  chmod 0440 "$SERVER_NAME.key"
else
  echo "[WARN] Server certificate already exists: $SERVER_CRT — skipping"
fi