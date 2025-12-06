#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="$1"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Config file not found: $CONFIG_FILE" >&2
  exit 1
fi

# We assume our dependencies is in PATH
for dep in certstrap jq; do
  if ! command -v "$dep" &>/dev/null; then
    echo "Missing dependency: $dep must be in PATH"
    exit 3
  fi
done

################################################################################
# Helpers
################################################################################

json() {
  jq -r "$1" "$CONFIG_FILE"
}

ensure_dir() {
  local path="$1"
  mkdir -p "$path"
}

file_exists() {
  [[ -f "$1" ]]
}

opt() {
  # Usage: opt --flag value
  # Only prints the flag if the value is non-empty
  local flag="$1"
  local value="$2"
  if [ -n "$value" ] && [ "$value" != "null" ]; then
    printf '%s %s ' "$flag" "$value"
  fi
}

strip_quotes() { sed 's/^"\(.*\)"$/\1/'; }

################################################################################
# Begin processing all certificate sets
################################################################################

OUTDIR="$(json '.outDir')"

SETS=$(json '.sets | to_entries[] | .key')

for SET in $SETS; do
  ENABLED=$(json ".sets.\"$SET\".enable")
  [[ "$ENABLED" == "true" ]] || continue

  SUBPATH=$(json ".sets.\"$SET\".outSubpath")
  if [[ "$SUBPATH" == "null" ]]; then
    SET_DIR="$OUTDIR/$SET"
  else
    SET_DIR="$OUTDIR/$SUBPATH"
  fi

  CA_DIR="$SET_DIR/ca"
  INT_DIR="$SET_DIR/intermediates"
  CERT_DIR="$SET_DIR/certs"

  echo "=== Processing set: $SET → $SET_DIR ==="

  ensure_dir "$CA_DIR"
  ensure_dir "$INT_DIR"
  ensure_dir "$CERT_DIR"

  ##############################################################################
  # ROOT CA
  ##############################################################################

  ROOT_KEY="$CA_DIR/$SET.key"
  ROOT_CRT="$CA_DIR/$SET.crt"

  COMMON_NAME=$(json ".sets.\"$SET\".ca.commonName")

  if ! file_exists "$ROOT_KEY"; then
    echo "Generating root CA: $SET"

    mapfile -t DOMAINS < <(json ".sets.\"$SET\".ca.permitDomains[]?")

    PERMIT_DOMAIN_ARG=""
    if [[ ${#DOMAINS[@]} -gt 0 ]]; then
      PERMIT_DOMAIN_ARG="--domain $(IFS=,; echo "${DOMAINS[*]}")"
    fi

    certstrap --depot-path "$CA_DIR" init \
      --common-name "$COMMON_NAME" \
      --expires "$(json ".sets.\"$SET\".ca.expires")" \
      --curve "$(json ".sets.\"$SET\".ca.curve")" \
      $(opt --organization "$(json ".sets.\"$SET\".ca.organization")") \
      $(opt --organizational-unit "$(json ".sets.\"$SET\".ca.organizationalUnit")") \
      $(opt --country "$(json ".sets.\"$SET\".ca.country")") \
      $(opt --province "$(json ".sets.\"$SET\".ca.province")") \
      $(opt --locality "$(json ".sets.\"$SET\".ca.locality")") \
      --passphrase "$(json ".sets.\"$SET\".ca.passPhrase")" \
      $PERMIT_DOMAIN_ARG \
      $( [[ $(json ".sets.\"$SET\".ca.pathLength") != "null" ]] && echo --path-length "$(json ".sets.\"$SET\".ca.pathLength")" )

    mv "$CA_DIR/$COMMON_NAME.crt" $ROOT_CRT
    mv "$CA_DIR/$COMMON_NAME.key" $ROOT_KEY
    mv "$CA_DIR/$COMMON_NAME.crl" "$CA_DIR/$SET.crl"
    chmod 0400 "$ROOT_KEY"
    chmod 0444 "$ROOT_CRT"
  else
    echo "Skipping root CA (already exists): $SET"
  fi

  ##############################################################################
  # INTERMEDIATE CAs
  ##############################################################################
  INT_NAMES=$(json ".sets.\"$SET\".intermediates | to_entries[]? | .key")

  for INAME in $INT_NAMES; do
    echo "Processing intermediate CA: $INAME"

    INT_KEY="$INT_DIR/$INAME.key"
    INT_CSR="$INT_DIR/$INAME.csr"
    INT_CRT="$INT_DIR/$INAME.crt"

    mapfile -t DOMAINS < <(json ".sets.\"$SET\".certs.\"$INAME\".domains[]?")
    mapfile -t IPS < <(json ".sets.\"$SET\".certs.\"$INAME\".ips[]?")
    mapfile -t URIS < <(json ".sets.\"$SET\".certs.\"$INAME\".uri[]?")

    DOMAIN_ARG=""
    if [[ ${#DOMAINS[@]} -gt 0 ]]; then
      DOMAIN_ARG="--domain $(IFS=,; echo "${DOMAINS[*]}")"
    fi

    IP_ARG=""
    if [[ ${#IPS[@]} -gt 0 ]]; then
      IP_ARG="--ip $(IFS=,; echo "${IPS[*]}")"
    fi

    URI_ARG=""
    if [[ ${#IPS[@]} -gt 0 ]]; then
      URI_ARG="--ip $(IFS=,; echo "${IPS[*]}")"
    fi

    # Generate intermediate CSR + key if missing
    if ! file_exists "$INT_KEY"; then
      certstrap --depot-path "$INT_DIR" request-cert \
        --common-name "$COMMON_NAME" \
        --csr "$INT_CSR" \
        --curve "$(json ".sets.\"$SET\".intermediates.\"$INAME\".curve")" \
        $(opt --organization "$(json ".sets.\"$SET\".intermediates.\"$INAME\".organization")") \
        $(opt --organizational-unit "$(json ".sets.\"$SET\".intermediates.\"$INAME\".organizationalUnit")") \
        $(opt --country "$(json ".sets.\"$SET\".intermediates.\"$INAME\".country")") \
        $(opt --province "$(json ".sets.\"$SET\".intermediates.\"$INAME\".province")") \
        $(opt --locality "$(json ".sets.\"$SET\".intermediates.\"$INAME\".locality")") \
        --passphrase "$(json ".sets.\"$SET\".intermediates.\"$INAME\".passPhrase")" \
        $DOMAIN_ARG \
        $IP_ARG \
        $URI_ARG

      mv "$INT_DIR/$COMMON_NAME.key" $INT_KEY
      chmod 0400 "$INT_KEY"
    else
      echo "  - CSR/key exist, skipping request step"
    fi

    # Sign with multiple parent CAs
    SIGNERS=$(json ".sets.\"$SET\".intermediates.\"$INAME\".signedBy[]?")
    if [[ -z "$SIGNERS" ]]; then
      echo "ERROR: Intermediate $INAME has no 'signedBy' list" >&2
      exit 1
    fi

    # Only sign once: if CRT already exists skip
    if ! file_exists "$INT_CRT"; then
      for S in $SIGNERS; do
        echo "  - Signing $INAME with parent CA: $S"

        # Determine whether signer is root or intermediate
        if [[ -f "$CA_DIR/$S.crt" ]]; then
          PARENT_DIR="$CA_DIR"
        elif [[ -f "$INT_DIR/$S.crt" ]]; then
          PARENT_DIR="$INT_DIR"
        else
          echo "ERROR: Parent CA '$S' not found for intermediate '$INAME'" >&2
          exit 1
        fi

        certstrap --depot-path "$INT_DIR" sign "$INAME" \
          --intermediate \
          --csr "$INT_CSR" \
          --CA "../../../$PARENT_DIR/$S" \
          --expires "$(json ".sets.\"$SET\".intermediates.\"$INAME\".expires")" \
          --passphrase "$(json ".sets.\"$SET\".intermediates.\"$INAME\".passPhrase")" \
          $( [[ $(json ".sets.\"$SET\".ca.pathLength") != "null" ]] && echo --path-length "$(json ".sets.\"$SET\".intermediates.\"$INAME\".pathLength")" )
      done

      # Move signed certificate where it belongs
      mv "$CA_DIR/$INAME.crt" "$INT_DIR/" 2>/dev/null || true
      mv "$INT_DIR/$INAME.crt" "$INT_DIR/" 2>/dev/null || true

      chmod 0444 "$INT_CRT"
    else
      echo "  - Already signed: $INAME"
    fi
  done

  ##############################################################################
  # LEAF CERTIFICATES
  ##############################################################################
  CERT_NAMES=$(json ".sets.\"$SET\".certs | to_entries[]? | .key")

  for CNAME in $CERT_NAMES; do
    echo "Processing leaf cert: $CNAME"

    KEY="$CERT_DIR/$CNAME.key"
    CSR="$CERT_DIR/$CNAME.csr"
    CRT="$CERT_DIR/$CNAME.crt"

    COMMON_NAME="$(json ".sets.\"$SET\".certs.\"$CNAME\".commonName")"

    mapfile -t DOMAINS < <(json ".sets.\"$SET\".certs.\"$CNAME\".domains[]?")
    mapfile -t IPS < <(json ".sets.\"$SET\".certs.\"$CNAME\".ips[]?")
    mapfile -t URIS < <(json ".sets.\"$SET\".certs.\"$CNAME\".uri[]?")

    DOMAIN_ARG=""
    if [[ ${#DOMAINS[@]} -gt 0 ]]; then
      DOMAIN_ARG="--domain $(IFS=,; echo "${DOMAINS[*]}")"
    fi

    IP_ARG=""
    if [[ ${#IPS[@]} -gt 0 ]]; then
      IP_ARG="--ip $(IFS=,; echo "${IPS[*]}")"
    fi

    URI_ARG=""
    if [[ ${#IPS[@]} -gt 0 ]]; then
      URI_ARG="--ip $(IFS=,; echo "${IPS[*]}")"
    fi


    # Create key+CSR if missing
    if ! file_exists "$KEY"; then
      certstrap --depot-path "$CERT_DIR" request-cert \
        --common-name "$COMMON_NAME" \
        --csr "$CSR" \
        --key "$KEY" \
        --curve "$(json ".sets.\"$SET\".certs.\"$CNAME\".curve")" \
        $(opt --organization "$(json ".sets.\"$SET\".certs.\"$CNAME\".organization")") \
        $(opt --organizational-unit "$(json ".sets.\"$SET\".certs.\"$CNAME\".organizationalUnit")") \
        $(opt --country "$(json ".sets.\"$SET\".certs.\"$CNAME\".country")") \
        $(opt --province "$(json ".sets.\"$SET\".certs.\"$CNAME\".province")") \
        $(opt --locality "$(json ".sets.\"$SET\".certs.\"$CNAME\".locality")") \
        --passphrase "$(json ".sets.\"$SET\".certs.\"$CNAME\".passPhrase")" \
        $DOMAIN_ARG \
        $IP_ARG \
        $URI_ARG

      chmod "$(json ".sets.\"$SET\".certs.\"$CNAME\".keyPerm")" "$KEY"
    else
      echo "  - Key exists, skipping CSR generation"
    fi

    # Sign the cert with each signer
    SIGNERS=$(json ".sets.\"$SET\".certs.\"$CNAME\".signedBy[]?")
    if [[ -z "$SIGNERS" ]]; then
      echo "ERROR: Leaf cert $CNAME has no signers" >&2
      exit 1
    fi

    if ! file_exists "$CRT"; then
      for S in $SIGNERS; do
        echo "  - Signing leaf $CNAME with CA $S"

        # Determine signer location
        if [[ -f "$CA_DIR/$S.crt" ]]; then
          PARENT_DIR="$CA_DIR"
        elif [[ -f "$INT_DIR/$S.crt" ]]; then
          PARENT_DIR="$INT_DIR"
        else
          echo "ERROR: Parent CA '$S' not found for leaf '$CNAME'" >&2
          exit 1
        fi

        certstrap --depot-path "$CERT_DIR" sign "$CNAME" \
          --csr "$CSR" \
          --CA "../../../$PARENT_DIR/$S" \
          --expires "$(json ".sets.\"$SET\".certs.\"$CNAME\".expires")" \
          --passphrase "$(json ".sets.\"$SET\".certs.\"$CNAME\".passPhrase")"
      done

      # Move result into certs folder
      mv "$CA_DIR/$CNAME.crt" "$CERT_DIR/" 2>/dev/null || true
      mv "$INT_DIR/$CNAME.crt" "$CERT_DIR/" 2>/dev/null || true

      chmod "$(json ".sets.\"$SET\".certs.\"$CNAME\".certPerm")" "$CRT"
    else
      echo "  - Cert exists, skipping signing"
    fi

  done

done

echo "All certificate sets processed."
