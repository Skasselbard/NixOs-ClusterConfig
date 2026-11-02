#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

SSH=(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
VM0=root@192.168.122.200
VM1=root@192.168.122.201
VM2=root@192.168.122.202

fail() {
  echo "TEST FAILED: $*" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local description="$3"
  [ "$expected" = "$actual" ] || fail "$description: expected '$expected', got '$actual'"
  echo "ok: $description"
}

assert_contains() {
  local needle="$1"
  local haystack="$2"
  local description="$3"
  case "$haystack" in
    *"$needle"*) echo "ok: $description" ;;
    *) fail "$description: '$needle' not found" ;;
  esac
}

assert_not_contains() {
  local needle="$1"
  local haystack="$2"
  local description="$3"
  case "$haystack" in
    *"$needle"*) fail "$description: '$needle' unexpectedly found" ;;
    *) echo "ok: $description" ;;
  esac
}

target_key() {
  local host="$1"
  local tmp
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' RETURN
  "${SSH[@]}" "$host" "cat -- /var/lib/sops-nix/key.txt" > "$tmp"
  age-keygen -y "$tmp"
  rm -f "$tmp"
}

check_target_key() {
  local host="$1"
  local expected="$2"
  local name="$3"
  local actual
  actual="$(target_key "$host")"
  assert_eq "$expected" "$actual" "$name target key"
  assert_eq "600 root:root" "$("${SSH[@]}" "$host" "stat -c '%a %U:%G' /var/lib/sops-nix/key.txt")" "$name target key permissions"
}

check_file() {
  local host="$1"
  local path="$2"
  local mode="$3"
  local owner="$4"
  local name="$5"
  local stat
  stat="$("${SSH[@]}" "$host" "stat -Lc '%a %U' '$path'")"
  assert_eq "$mode $owner" "$stat" "$name permissions"
  "${SSH[@]}" "$host" "cat -- '$path' >/dev/null" || fail "$name is not readable by root"
  echo "ok: $name readable by root"
  if "${SSH[@]}" "$host" "su -s /bin/sh nobody -c 'cat -- \"$path\"' >/dev/null 2>&1"; then
    fail "$name is readable by nobody"
  fi
  echo "ok: $name not readable by nobody"
}

check_absent() {
  local host="$1"
  local path="$2"
  local name="$3"
  if "${SSH[@]}" "$host" "test -e '$path'"; then
    fail "$name unexpectedly exists at $path"
  fi
  echo "ok: $name absent"
}

vm0_key="$(age-keygen -y ../00-exampleConfigs/secrets/age/vm0.key)"
vm2_key="$(age-keygen -y ../00-exampleConfigs/secrets/age/vm2.key)"
vm1_key="$(
  printf '%s\n' "$(cat ../00-exampleConfigs/secrets/keepass.pass)" \
    | keepassxc-cli show -q -s -a Password ../00-exampleConfigs/secrets/Passwords.kdbx clusterConfig/example/machines/vm1 \
    | age-keygen -y /dev/stdin
)"

check_target_key "$VM0" "$vm0_key" vm0
check_target_key "$VM1" "$vm1_key" vm1
check_target_key "$VM2" "$vm2_key" vm2

check_file "$VM0" /run/secrets/testService/testSecret 440 testService vm0-testService-secret
check_file "$VM0" /home/admin/secrets/adminSecret 400 admin vm0-admin-secret
check_file "$VM1" /home/admin/secrets/testPassword 440 admin vm1-testPassword
check_file "$VM0" /run/secrets/cluster/clusterPassword 400 root vm0-cluster-secret
check_file "$VM1" /run/secrets/cluster/clusterPassword 400 root vm1-cluster-secret
check_file "$VM2" /run/secrets/cluster/clusterPassword 400 root vm2-cluster-secret
check_file "$VM0" /run/secrets/custom/customPassword 400 root vm0-custom-secret
check_file "$VM1" /run/secrets/custom/customPassword 400 root vm1-custom-secret
check_file "$VM2" /run/secrets/custom/customPassword 400 root vm2-custom-secret
check_file "$VM0" /run/secrets/monitoring/token 400 root vm0-monitoring-secret
check_file "$VM1" /run/secrets/monitoring/token 400 root vm1-monitoring-secret
check_absent "$VM2" /run/secrets/monitoring/token vm2-monitoring-secret

check_file "$VM0" /run/secrets/rendered/monitoring.env 400 root vm0-monitoring-template
check_file "$VM1" /run/secrets/rendered/monitoring.env 400 root vm1-monitoring-template
check_absent "$VM2" /run/secrets/rendered/monitoring.env vm2-monitoring-template

check_file "$VM0" /run/secrets/rendered/cluster.env 400 root vm0-cluster-template
check_file "$VM1" /run/secrets/rendered/cluster.env 400 root vm1-cluster-template
check_file "$VM2" /run/secrets/rendered/cluster.env 400 root vm2-cluster-template

for machine in vm0 vm1 vm2; do
  echo "=== secretsCheck $machine ==="
  nix run ".#example.$machine.secretsCheck"
done
