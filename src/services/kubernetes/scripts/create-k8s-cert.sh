#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:-}"
CONFIG_FILE="${2:-}"

if [[ -z "$ROLE" || ! -f "$CONFIG_FILE" ]]; then
  echo "Usage: $0 <role> <config.json>"
  exit 1
fi

CONFIG_JSON="$(< "$CONFIG_FILE")"

CA_NAME=$(echo "$CONFIG_JSON" | jq -r '.k8s.ca.name')
ORG=$(echo "$CONFIG_JSON" | jq -r '.common.org')
ORG_UNIT=$(echo "$CONFIG_JSON" | jq -r '.common.orgUnit')
COUNTRY=$(echo "$CONFIG_JSON" | jq -r '.common.country')
PROVINCE=$(echo "$CONFIG_JSON" | jq -r '.common.province')
LOCALITY=$(echo "$CONFIG_JSON" | jq -r '.common.locality')

NAME=$(echo "$CONFIG_JSON" | jq -r ".k8s.roles[\"${ROLE}\"].name // empty")
PASSPHRASE=$(echo "$CONFIG_JSON" | jq -r ".k8s.roles[\"${ROLE}\"].passPhrase // empty")

mapfile -t DOMAINS < <(echo "$CONFIG_JSON" | jq -r ".k8s.roles[\"${ROLE}\"].domains[]?")
mapfile -t IPS < <(echo "$CONFIG_JSON" | jq -r ".k8s.roles[\"${ROLE}\"].ips[]?")

CRT="$ROLE.crt"
KEY="$ROLE.key"
CSR="$ROLE.csr"

DOMAIN_ARG=""
[[ ${#DOMAINS[@]} -gt 0 ]] && DOMAIN_ARG="--domain $(IFS=,; echo "${DOMAINS[*]}")"

IP_ARG=""
[[ ${#IPS[@]} -gt 0 ]] && IP_ARG="--ip $(IFS=,; echo "${IPS[*]}")"

if [[ ! -f "$CRT" ]]; then
  if [[ ! -f "$CSR" ]]; then
    echo "[INFO] Creating CSR for $ROLE"
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
      --passphrase "$PASSPHRASE" \
      --csr "$CSR" \
      --key "$KEY"
  fi

  echo "[INFO] Signing certificate for $ROLE"
  certstrap --depot-path "." sign \
    --csr "$CSR" \
    --cert "$CRT" \
    --CA "$CA_NAME" \
    --expires "5 year" \
    "$NAME"

  chmod 0444 "$CRT"
  chmod 0440 "$KEY"
else
  echo "[INFO] Certificate for $ROLE already exists: $CRT"
fi
