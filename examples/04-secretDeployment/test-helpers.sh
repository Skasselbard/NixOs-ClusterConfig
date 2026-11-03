#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
flake_root="$PWD"
marker="secrets/.secret-service-root"
marker_backup="secrets/.secret-service-root.test-backup"

fail() {
  echo "HELPER TEST FAILED: $*" >&2
  exit 1
}

restore_marker() {
  if [ -f "$marker_backup" ]; then
    mv -f "$marker_backup" "$marker"
  fi
}

cleanup() {
  restore_marker
}

trap cleanup EXIT

# Run a helper from a nested directory. This verifies that the helper finds the
# flake root before resolving relative key and sops paths.
(
  cd secrets/example
  nix run "$flake_root#example.secrets.secretsSyncKeyHolders"
)
echo "ok: helper runs from a nested directory"

# Mutating helpers must reject a missing marker. The exact command in the hint
# is optional, but the error must point at secretsInitRoot.
mv "$marker" "$marker_backup"
set +e
output="$(
  cd secrets/example
  nix run "$flake_root#example.secrets.secretsSyncKeyHolders" 2>&1
)"
status=$?
set -e
restore_marker
[ "$status" -ne 0 ] || fail "secretsSyncKeyHolders succeeded without a marker"
case "$output" in
  *secretsInitRoot*) echo "ok: missing marker error mentions secretsInitRoot" ;;
  *) fail "missing marker error did not mention secretsInitRoot" ;;
esac

trap - EXIT
echo "Helper tests passed."
