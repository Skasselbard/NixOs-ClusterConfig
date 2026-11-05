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

# secretSet must infer group files and reject undeclared keys before setting up
# the key source.
cluster_set="$(nix build --no-link --print-out-paths "$flake_root#example.secrets.secretSet")"
grep -q 'monitoring/token) file=example/cluster/monitoring.yaml' "$cluster_set/bin/secretSet" \
  || fail "cluster secretSet did not map monitoring/token to the group file"
if grep -q 'testService/testSecret) file=' "$cluster_set/bin/secretSet"; then
  fail "cluster secretSet unexpectedly mapped a machine secret"
fi

vm0_set="$(nix build --no-link --print-out-paths "$flake_root#example.vm0.secretSet")"
grep -q 'testService/testSecret) file=example/machines/vm0.yaml' "$vm0_set/bin/secretSet" \
  || fail "machine secretSet did not map its machine secret"

group_set="$(nix build --no-link --print-out-paths "$flake_root#example.secrets.secretsMonitoringSet")"
grep -q 'monitoring/token) file=example/cluster/monitoring.yaml' "$group_set/bin/secretsMonitoringSet" \
  || fail "group secretSet did not map its group secret"

error_line="$(grep -n 'is not declared for this command' "$cluster_set/bin/secretSet" | head -n1 | cut -d: -f1)"
key_source_line="$(grep -n 'export SOPS_AGE_KEY_FILE' "$cluster_set/bin/secretSet" | head -n1 | cut -d: -f1)"
[ -n "$error_line" ] && [ -n "$key_source_line" ] && [ "$error_line" -lt "$key_source_line" ] \
  || fail "secretSet key-source setup is not after undeclared-key validation"

set +e
output="$(
  printf 'x\n' | nix run "$flake_root#example.secrets.secretSet" -- --key testService/testSecret 2>&1
)"
status=$?
set -e
[ "$status" -ne 0 ] || fail "cluster secretSet accepted a machine secret"
case "$output" in
  *"nix run .#example.vm0.secretSet -- --key testService/testSecret"*)
    echo "ok: secretSet hint points to the owning machine command"
    ;;
  *) fail "secretSet hint did not point to the owning machine command" ;;
esac

set +e
output="$(
  printf 'x\n' | nix run "$flake_root#example.secrets.secretsMonitoringSet" -- --key cluster/clusterPassword 2>&1
)"
status=$?
set -e
[ "$status" -ne 0 ] || fail "group secretSet accepted a cluster-wide secret"
case "$output" in
  *"nix run .#example.secrets.secretSet -- --key cluster/clusterPassword"*)
    echo "ok: group secretSet hint points to the cluster command"
    ;;
  *) fail "group secretSet hint did not point to the cluster command" ;;
esac

trap - EXIT
echo "Helper tests passed."
