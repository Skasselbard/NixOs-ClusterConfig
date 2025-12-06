#!/usr/bin/env bash
set -euo pipefail

# create-sa-keys-env.sh
# Configuration via environment variables:
#
#   SA_KEY           Private key path (default ./sa.key)
#   SA_PUB           Public key path (default ./sa.pub)
#   SA_OWNER         chown owner (optional)
#   SA_GROUP         chown group (optional)
#   SA_ENCRYPT       true|false (default false)
#   SA_PASSPHRASE    passphrase for encryption (optional)
#   SA_ALG           ed25519|rsa-4096|p384 (default ed25519)
#   SA_FORCE         true|false (default false)
#
# Example:
#   SA_KEY=/var/lib/kubernetes/pki/sa.key \
#   SA_PUB=/var/lib/kubernetes/pki/sa.pub \
#   SA_ALG=ed25519 \
#   SA_FORCE=true \
#     ./create-sa-keys-env.sh

show_help() {
  cat <<EOF
Usage: environment variables configure all behavior.

Available variables:

  SA_KEY=/path/to/priv.key         (default: ./sa.key)
  SA_PUB=/path/to/pub.key          (default: ./sa.pub)
  SA_OWNER=user                    (optional)
  SA_GROUP=group                   (optional)
  SA_ENCRYPT=true|false            (default: false)
  SA_PASSPHRASE=secret             (optional)
  SA_ALG=ed25519|rsa-4096|p384     (default: ed25519)
  SA_FORCE=true|false              (default: false)

Run with:
  ./create-sa-keys-env.sh

EOF
}

# If user explicitly asks for help
[[ "${1:-}" == "--help" ]] && { show_help; exit 0; }

# Defaults
SA_KEY="${SA_KEY:-./sa.key}"
SA_PUB="${SA_PUB:-./sa.pub}"
SA_OWNER="${SA_OWNER:-}"
SA_GROUP="${SA_GROUP:-}"
SA_ENCRYPT="${SA_ENCRYPT:-false}"
SA_PASSPHRASE="${SA_PASSPHRASE:-}"
SA_ALG="${SA_ALG:-ed25519}"
SA_FORCE="${SA_FORCE:-false}"

# Normalize booleans
bool() {
  case "$1" in
    true|True|1|yes|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

# Dependencies
for cmd in openssl; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "[ERROR] Missing required command: $cmd" >&2
    exit 1
  fi
done

echo "[INFO] Algorithm: $SA_ALG"
echo "[INFO] Private key: $SA_KEY"
echo "[INFO] Public key : $SA_PUB"
if [[ -n "$SA_OWNER" || -n "$SA_GROUP" ]]; then
  echo "[INFO] Owner/Group target: ${SA_OWNER:-<same>}:${SA_GROUP:-<same>}"
fi

# Existing files
if ! bool "$SA_FORCE"; then
  if [[ -f "$SA_KEY" || -f "$SA_PUB" ]]; then
    echo "[ERROR] Key or pub already exists. Use SA_FORCE=true to overwrite."
    ls -l "$SA_KEY" "$SA_PUB" 2>/dev/null || true
    exit 1
  fi
else
  echo "[WARN] SA_FORCE=true: overwriting existing files"
fi

mkdir -p "$(dirname "$SA_KEY")" "$(dirname "$SA_PUB")"

# temp file for unencrypted private key (when encrypting)
tmp_key="$(mktemp -u)"
trap 'rm -f "$tmp_key" 2>/dev/null || true' EXIT

prompt_passphrase_if_needed() {
  if bool "$SA_ENCRYPT" && [[ -z "$SA_PASSPHRASE" ]]; then
    read -s -p "Enter passphrase: " p1; echo
    read -s -p "Confirm passphrase: " p2; echo
    [[ "$p1" == "$p2" ]] || { echo "[ERROR] Passphrases do not match"; exit 1; }
    SA_PASSPHRASE="$p1"
  fi
}

generate_ed25519() {
  echo "[INFO] Generating Ed25519 keypair"
  if bool "$SA_ENCRYPT"; then
    prompt_passphrase_if_needed
    openssl genpkey -algorithm Ed25519 -out "$tmp_key"
    openssl pkey -in "$tmp_key" -aes-256-cbc -passout pass:"$SA_PASSPHRASE" -out "$SA_KEY"
    openssl pkey -in "$tmp_key" -pubout -out "$SA_PUB"
  else
    openssl genpkey -algorithm Ed25519 -out "$SA_KEY"
    openssl pkey -in "$SA_KEY" -pubout -out "$SA_PUB"
  fi
}

generate_rsa4096() {
  echo "[INFO] Generating RSA-4096 keypair"
  if bool "$SA_ENCRYPT"; then
    prompt_passphrase_if_needed
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out "$tmp_key"
    openssl pkey -in "$tmp_key" -aes-256-cbc -passout pass:"$SA_PASSPHRASE" -out "$SA_KEY"
    openssl pkey -in "$tmp_key" -pubout -out "$SA_PUB"
  else
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out "$SA_KEY"
    openssl pkey -in "$SA_KEY" -pubout -out "$SA_PUB"
  fi
}

generate_p384() {
  echo "[INFO] Generating EC P-384 keypair"
  if bool "$SA_ENCRYPT"; then
    prompt_passphrase_if_needed
    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:secp384r1 -out "$tmp_key"
    openssl pkey -in "$tmp_key" -aes-256-cbc -passout pass:"$SA_PASSPHRASE" -out "$SA_KEY"
    openssl pkey -in "$tmp_key" -pubout -out "$SA_PUB"
  else
    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:secp384r1 -out "$SA_KEY"
    openssl pkey -in "$SA_KEY" -pubout -out "$SA_PUB"
  fi
}

case "$SA_ALG" in
  ed25519) generate_ed25519 ;;
  rsa-4096) generate_rsa4096 ;;
  p384) generate_p384 ;;
  *) echo "[ERROR] Unknown algorithm: $SA_ALG"; exit 2 ;;
esac

chmod 0400 "$SA_KEY"
chmod 0444 "$SA_PUB"

# Optionally chown files
chown_if_exists() {
  local path="$1" u="$2" g="$3"

  if [[ -z "$u" && -z "$g" ]]; then return; fi

  if [[ -n "$u" ]] && ! id -u "$u" &>/dev/null; then
    echo "[WARN] User '$u' not found; skipping chown for $path"
    return
  fi
  if [[ -n "$g" ]] && ! getent group "$g" &>/dev/null; then
    echo "[WARN] Group '$g' not found; skipping chown for $path"
    return
  fi

  echo "[INFO] Setting owner/group for $path -> ${u:-<same>}:${g:-<same>}"
  chown "${u:-}:${g:-}" "$path"
}

chown_if_exists "$SA_KEY" "$SA_OWNER" "$SA_GROUP"
chown_if_exists "$SA_PUB" "$SA_OWNER" "$SA_GROUP"

echo "[OK] Service-account key pair generated."
echo "      Private: $SA_KEY (0400)"
echo "      Public : $SA_PUB (0444)"
if bool "$SA_ENCRYPT"; then
  echo "[NOTE] Private key is encrypted with a passphrase."
fi

rm -f "$tmp_key" 2>/dev/null || true
trap - EXIT
