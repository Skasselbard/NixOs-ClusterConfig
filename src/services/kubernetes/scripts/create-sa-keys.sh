#!/usr/bin/env bash
set -euo pipefail

# create-sa-keys.sh
# Usage:
#   ./create-sa-keys.sh [--config config.json] [--alg ed25519|rsa-4096|p384] [--force]
#
# Generates service-account signing keypair (private + public).
# Default algorithm: ed25519 (modern, compact, secure).
#
# Optional JSON config (keys under top-level "sa"):
# {
#   "sa": {
#     "key": "/var/lib/kubernetes/pki/sa.key",
#     "pub": "/var/lib/kubernetes/pki/sa.pub",
#     "owner": "root",
#     "group": "root",
#     "encrypt": false,
#     "passphrase": ""        # optional, or will be read interactively if encrypt=true and passphrase omitted
#   }
# }

show_help() {
  cat <<'EOF'
create-sa-keys.sh

Generates Kubernetes service-account signing keypair.

Options:
  --config FILE        JSON config file (optional)
  --alg ALG            Algorithm: ed25519 (default) | rsa-4096 | p384
  --force              Overwrite existing files
  --help               Show this help
EOF
}

# defaults
ALG="ed25519"
CONFIG_FILE=""
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG_FILE="$2"; shift 2;;
    --alg) ALG="$2"; shift 2;;
    --force) FORCE=1; shift;;
    --help) show_help; exit 0;;
    *) echo "Unknown arg: $1"; show_help; exit 2;;
  esac
done

# dependencies
for cmd in openssl jq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "[ERROR] Required command not found: $cmd" >&2
    exit 1
  fi
done

# Load values from config if provided
SA_KEY="./sa.key"
SA_PUB="./sa.pub"
SA_OWNER=""
SA_GROUP=""
SA_ENCRYPT=false
SA_PASSPHRASE=""

if [[ -n "$CONFIG_FILE" ]]; then
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "[ERROR] Config file not found: $CONFIG_FILE" >&2
    exit 1
  fi

  # helper: read jq value safely
  jq_str() {
    local path="$1"
    jq -r "try .${path} // empty" "$CONFIG_FILE"
  }

  keypath=$(jq_str 'sa.key')
  pubpath=$(jq_str 'sa.pub')
  owner=$(jq_str 'sa.owner') # file system owner for chown
  group=$(jq_str 'sa.group') # file group owner for chown
  encrypt=$(jq_str 'sa.encrypt')
  passphrase=$(jq_str 'sa.passphrase')

  [[ -n "$keypath" ]] && SA_KEY="$keypath"
  [[ -n "$pubpath" ]] && SA_PUB="$pubpath"
  [[ -n "$owner" ]] && SA_OWNER="$owner"
  [[ -n "$group" ]] && SA_GROUP="$group"
  if [[ "$encrypt" == "true" || "$encrypt" == "True" || "$encrypt" == "1" ]]; then
    SA_ENCRYPT=true
  fi
  [[ -n "$passphrase" ]] && SA_PASSPHRASE="$passphrase"
fi

echo "[INFO] Algorithm: $ALG"
echo "[INFO] Private key: $SA_KEY"
echo "[INFO] Public key : $SA_PUB"
if [[ -n "$SA_OWNER" || -n "$SA_GROUP" ]]; then
  echo "[INFO] Owner/Group will be set: ${SA_OWNER:-<unchanged>}:${SA_GROUP:-<unchanged>}"
fi

if [[ $FORCE -ne 1 ]]; then
  if [[ -f "$SA_KEY" || -f "$SA_PUB" ]]; then
    echo "[ERROR] Key or pub already exists. Use --force to overwrite."
    ls -l "${SA_KEY}" "${SA_PUB}" 2>/dev/null || true
    exit 1
  fi
else
  echo "[WARN] --force specified: existing files will be overwritten"
fi

# Ensure parent directories exist and are not in Nix store
mkdir -p "$(dirname "$SA_KEY")"
mkdir -p "$(dirname "$SA_PUB")"

# Generate keys
tmp_key="$(mktemp -u)"
trap 'rm -f "$tmp_key" 2>/dev/null || true' EXIT

generate_ed25519() {
  echo "[INFO] Generating Ed25519 keypair"
  # OpenSSL modern supports Ed25519
  if [[ -n "$SA_PASSPHRASE" || "$SA_ENCRYPT" == true ]]; then
    # If encrypt and no passphrase provided, prompt
    if [[ -z "$SA_PASSPHRASE" && "$SA_ENCRYPT" == true ]]; then
      read -s -p "Enter passphrase to encrypt private key: " p1; echo
      read -s -p "Confirm passphrase: " p2; echo
      if [[ "$p1" != "$p2" ]]; then
        echo "[ERROR] Passphrases do not match" >&2
        exit 1
      fi
      SA_PASSPHRASE="$p1"
    fi

    # Generate and encrypt using OpenSSL
    openssl genpkey -algorithm Ed25519 -out "$tmp_key"
    # Encrypt PEM with AES-256, using provided passphrase
    openssl pkey -in "$tmp_key" -aes-256-cbc -passout pass:"$SA_PASSPHRASE" -out "$SA_KEY"
    # Extract public
    openssl pkey -in "$tmp_key" -pubout -out "$SA_PUB"
    # Remove tmp_key later via trap
  else
    openssl genpkey -algorithm Ed25519 -out "$SA_KEY"
    openssl pkey -in "$SA_KEY" -pubout -out "$SA_PUB"
  fi
}

generate_rsa4096() {
  echo "[INFO] Generating RSA-4096 keypair"
  if [[ -n "$SA_PASSPHRASE" || "$SA_ENCRYPT" == true ]]; then
    if [[ -z "$SA_PASSPHRASE" && "$SA_ENCRYPT" == true ]]; then
      read -s -p "Enter passphrase to encrypt private key: " p1; echo
      read -s -p "Confirm passphrase: " p2; echo
      if [[ "$p1" != "$p2" ]]; then
        echo "[ERROR] Passphrases do not match" >&2
        exit 1
      fi
      SA_PASSPHRASE="$p1"
    fi

    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out "$tmp_key"
    openssl pkey -in "$tmp_key" -aes-256-cbc -passout pass:"$SA_PASSPHRASE" -out "$SA_KEY"
    openssl pkey -in "$tmp_key" -pubout -out "$SA_PUB"
  else
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out "$SA_KEY"
    openssl pkey -in "$SA_KEY" -pubout -out "$SA_PUB"
  fi
}

generate_p384() {
  echo "[INFO] Generating ECDSA P-384 keypair"
  if [[ -n "$SA_PASSPHRASE" || "$SA_ENCRYPT" == true ]]; then
    if [[ -z "$SA_PASSPHRASE" && "$SA_ENCRYPT" == true ]]; then
      read -s -p "Enter passphrase to encrypt private key: " p1; echo
      read -s -p "Confirm passphrase: " p2; echo
      if [[ "$p1" != "$p2" ]]; then
        echo "[ERROR] Passphrases do not match" >&2
        exit 1
      fi
      SA_PASSPHRASE="$p1"
    fi

    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:secp384r1 -out "$tmp_key"
    openssl pkey -in "$tmp_key" -aes-256-cbc -passout pass:"$SA_PASSPHRASE" -out "$SA_KEY"
    openssl pkey -in "$tmp_key" -pubout -out "$SA_PUB"
  else
    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:secp384r1 -out "$SA_KEY"
    openssl pkey -in "$SA_KEY" -pubout -out "$SA_PUB"
  fi
}

case "$ALG" in
  ed25519) generate_ed25519 ;;
  rsa-4096) generate_rsa4096 ;;
  p384) generate_p384 ;;
  *) echo "[ERROR] Unknown algorithm: $ALG" >&2; exit 2 ;;
esac

# Set strict permissions: private 0400, public 0444
chmod 0400 "$SA_KEY"
chmod 0444 "$SA_PUB"

# Optionally set owner/group if provided and user/group exists
chown_if_exists() {
  local path="$1" user="$2" group="$3"
  if [[ -n "$user" || -n "$group" ]]; then
    # If user or group missing, skip with message
    if [[ -n "$user" && ! id -u "$user" &>/dev/null ]]; then
      echo "[WARN] User '$user' not found; skipping chown for $path"
      return
    fi
    if [[ -n "$group" && ! getent group "$group" &>/dev/null ]]; then
      echo "[WARN] Group '$group' not found; skipping chown for $path"
      return
    fi
    if [[ -z "$user" ]]; then user=""; fi
    if [[ -z "$group" ]]; then group=""; fi
    echo "[INFO] Setting owner/group on $path -> ${user:-}<same>:${group:-}<same>"
    chown "${user}:${group}" "$path"
  fi
}

chown_if_exists "$SA_KEY" "$SA_OWNER" "$SA_GROUP"
chown_if_exists "$SA_PUB" "$SA_OWNER" "$SA_GROUP"

echo "[OK] Service-account key pair generated."
echo "      Private: $SA_KEY (mode 0400)"
echo "      Public : $SA_PUB (mode 0444)"
if [[ "$SA_ENCRYPT" == true ]]; then
  echo "[NOTE] Private key is encrypted with a passphrase. Make sure the API server is configured to read an encrypted PEM if you use this."
fi

# remove tmp file explicitly (trap will also try)
rm -f "$tmp_key" 2>/dev/null || true
trap - EXIT
