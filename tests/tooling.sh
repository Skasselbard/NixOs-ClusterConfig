#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
flake="$root/examples/01-simpleCluster"
tool="$(nix build --no-link --print-out-paths --no-write-lock-file "path:$root#clusterConfig")/bin/clusterConfig"
[[ -x "$(dirname "$tool")/clcli" ]] || { echo "clcli symlink is missing" >&2; exit 1; }
tool_root="$(dirname "$(dirname "$tool")")"
[[ -f "$tool_root/share/zsh/site-functions/_clusterConfig" ]] || { echo "packaged zsh completion is missing" >&2; exit 1; }
[[ -f "$tool_root/share/bash-completion/completions/clusterConfig" ]] || { echo "packaged bash completion is missing" >&2; exit 1; }

fail() {
  printf 'tooling test failed: %s\n' "$*" >&2
  exit 1
}

names="$("$tool" --flake "$flake" list --names-only 2>/dev/null)"
grep -qx 'example.vm0.deploy' <<<"$names" || fail "deploy is missing from the names index"

complete="$("$tool" --flake "$flake" complete -- run example vm0 '' 2>/dev/null)"
grep -qx 'deploy' <<<"$complete" || fail "deploy is missing from completion candidates"

complete_top="$("$tool" --flake "$flake" complete --json -- '' 2>/dev/null)"
grep -q '"value":"clusterConfig"' <<<"$complete_top" || fail "tool completion entry is missing"

if hint="$("$tool" --no-color --flake "$flake" show example 2>&1)"; then
  fail "show accepted an incomplete namespace"
fi
grep -q 'hint: "example" is a namespace' <<<"$hint" || fail "namespace hint is missing"
grep -q 'example.vm0' <<<"$hint" || fail "namespace hint does not list child packages"

tree="$("$tool" --no-color --flake "$flake" list 2>/dev/null)"
grep -q '^packages$' <<<"$tree" || fail "list has no root line"
grep -q 'vm0 (machine)' <<<"$tree" || fail "machine group is missing from the tree"
grep -q 'Build the installation ISO' <<<"$tree" || fail "ISO metadata is missing"
grep -q '└──' <<<"$tree" || fail "list has no closing tree branch"
if grep -Eq '│[[:space:]]*$' <<<"$tree"; then
  fail "list has a dangling tree branch"
fi

flat="$("$tool" --flake "$flake" list --flat 2>/dev/null)"
grep -q 'example.vm0.iso' <<<"$flat" || fail "ISO is missing from the flat table"

show_split="$("$tool" --no-color --flake "$flake" show example vm0 iso 2>/dev/null)"
grep -q 'path:.*example.vm0.iso' <<<"$show_split" || fail "split show path failed"

path_split="$("$tool" --flake "$flake" path example vm0 iso 2>/dev/null)"
grep -q 'example.vm0.iso' <<<"$path_split" || fail "split path command failed"

show="$("$tool" --no-color --flake "$flake" show 2>/dev/null)"
grep -q '├── clusters' <<<"$show" || fail "show has no clusters section"
grep -q '├── apps' <<<"$show" || fail "show has no apps section"
grep -q '├── packages' <<<"$show" || fail "show has no package section"
grep -q '└── nixosConfigurations' <<<"$show" || fail "show has no nixosConfigurations section"
grep -q 'cluster: example' <<<"$show" || fail "nixosConfiguration cluster annotation is missing"
grep -q 'targetHost: 192.168.122.200' <<<"$show" || fail "machine targetHost detail is missing"
grep -q 'roles: hosts' <<<"$show" || fail "service role detail is missing"

show07="$("$tool" --no-color --flake "$root/examples/07-kubernetes" show 2>/dev/null)"
grep -q 'kubernetes' <<<"$show07" || fail "show07 has no kubernetes service"
grep -q 'roles: controlPlane, worker, etcd' <<<"$show07" || fail "show07 service roles are missing"
grep -q '└── nixosConfigurations' <<<"$show07" || fail "show07 tree is incomplete"

for shell in bash zsh fish nu; do
  "$tool" completions "$shell" >/dev/null || fail "completion generation failed for $shell"
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
XDG_DATA_HOME="$tmp/data" XDG_CONFIG_HOME="$tmp/config" \
  "$tool" completions install zsh >/dev/null || fail "zsh completion install failed"
[[ -f "$tmp/data/zsh/site-functions/_clusterConfig" ]] || fail "zsh completion file was not created"
XDG_DATA_HOME="$tmp/data" "$tool" completions install --dry-run bash | grep -q "$tmp/data/bash-completion/completions/clusterConfig" \
  || fail "bash completion dry-run path is wrong"
XDG_CONFIG_HOME="$tmp/config" "$tool" completions install nu >/dev/null || fail "nushell completion install failed"
[[ -f "$tmp/config/nushell/clusterConfig.nu" ]] || fail "nushell completion file was not created"

alias_cmd="$("$tool" --flake "$flake" run example.vm0.deploy --dry-run 2>/dev/null)"
grep -q 'nix run' <<<"$alias_cmd" || fail "run is not an alias for nix run"
grep -q '(cd ' <<<"$alias_cmd" || fail "run does not cd into the flake root"

split_run="$("$tool" --flake "$flake" run example vm0 deploy --dry-run 2>/dev/null)"
grep -q 'example.vm0.deploy' <<<"$split_run" || fail "split run path failed"

before="$PWD"
"$tool" --flake "$flake" run example.vm0.deploy --dry-run >/dev/null 2>&1
[[ "$PWD" == "$before" ]] || fail "clusterConfig changed the caller's working directory"

printf 'tooling tests passed\n'
