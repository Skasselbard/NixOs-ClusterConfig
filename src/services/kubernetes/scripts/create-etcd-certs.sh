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
CA_NAME=$(echo "$CONFIG_JSON" | jq -r '.etcd.ca.name')
CA_PASSPHRASE=$(echo "$CONFIG_JSON" | jq -r '.etcd.ca.passPhrase')
ORG=$(echo "$CONFIG_JSON" | jq -r '.common.org')
ORG_UNIT=$(echo "$CONFIG_JSON" | jq -r '.common.orgUnit')
COUNTRY=$(echo "$CONFIG_JSON" | jq -r '.common.country')
PROVINCE=$(echo "$CONFIG_JSON" | jq -r '.common.province')
LOCALITY=$(echo "$CONFIG_JSON" | jq -r '.common.locality')

# Create CA certificate if not exists
if [[ ! -f "$CA_NAME.crt" ]]; then
  echo "[INFO] Creating CA certificate: $CA_NAME"
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
  echo "[INFO] CA certificate already exists: $CA_NAME.crt"
fi

create_and_sign_cert() {
  local ROLE=$1
  
  if [[ -z $(echo "$CONFIG_JSON" | jq -r ".etcd.${ROLE} // empty") ]]; then
    echo "[INFO] Skipping role '$ROLE': undefined in config"
    return 0
  fi

  local NAME=$(echo "$CONFIG_JSON" | jq -r ".etcd.${ROLE}.name // empty")
  local PASSPHRASE=$(echo "$CONFIG_JSON" | jq -r ".etcd.${ROLE}.passPhrase // empty")
  local CRT="$NAME.crt"
  local KEY="$NAME.key"
  local CSR="$NAME.csr"

  mapfile -t DOMAINS < <(echo "$CONFIG_JSON" | jq -r ".etcd.${ROLE}.domains[]?")
  mapfile -t IPS < <(echo "$CONFIG_JSON" | jq -r ".etcd.${ROLE}.ips[]?")

  local DOMAIN_ARG=""
  if [[ ${#DOMAINS[@]} -gt 0 ]]; then
    DOMAIN_ARG="--domain $(IFS=,; echo "${DOMAINS[*]}")"
  fi

  local IP_ARG=""
  if [[ ${#IPS[@]} -gt 0 ]]; then
    IP_ARG="--ip $(IFS=,; echo "${IPS[*]}")"
  fi

  if [[ ! -f "$CRT" ]]; then
    if [[ ! -f "$CSR" ]]; then
      echo "[INFO] Creating $ROLE certificate request: $CSR"
      certstrap --depot-path "." request-cert \
        --curve P-256 \
        --common-name "$NAME" \
        $DOMAIN_ARG \
        $IP_ARG \
        --organization "$ORG" \
        --organizational-unit "$ORG_UNIT" \
        --country "$COUNTRY" \
        --province "$PROVINCE" \
        --locality "$LOCALITY" \
        --passphrase "$PASSPHRASE"
    else
      echo "[INFO] CSR already exists: $CSR"
    fi

    # Wait until CSR exists and is non-zero
    for i in {1..10}; do
      [[ -s "$CSR" ]] && break
      echo "[WAIT] Waiting for CSR $CSR..."
      sleep 0.1
    done

    echo "[INFO] Signing $ROLE certificate"
    certstrap --depot-path "." sign \
      --csr "$CSR" \
      --cert "$CRT" \
      --CA "$CA_NAME" \
      --expires "5 year" \
      "$NAME"

    chmod 0444 "$CRT"
    chmod 0440 "$KEY"
  else
    echo "[INFO] $ROLE certificate already exists: $CRT"
  fi
}

# Generate both server and peer certs
create_and_sign_cert "server"
create_and_sign_cert "peer"
