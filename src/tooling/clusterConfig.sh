# shellcheck shell=bash
# clusterConfig CLI.
#
# Architecture:
# - `packageIndex` is the source of truth for package paths, descriptions, and
#   metadata. Reading it does not force package derivations.
# - `flakeInfo` supplies the cluster/machine/service overview. A best-effort
#   detailed evaluation adds fields such as targetHost when it is safe to force.
# - Flake/system/color state is resolved once in `main`/`prepare_context`; the
#   command functions receive normalized values through that context.
# - Package commands execute `nix run`/`nix build` in a subshell so the caller's
#   working directory is never changed.
# - The script does not keep a cache yet. `--refresh`/`--no-cache` are accepted
#   for forward compatibility.

PROG="clusterConfig"

FLAKE_ARG=""
SYSTEM_ARG=""
FLAKE_REF=""
FLAKE_ROOT=""
SYSTEM=""
COLOR=0

# Print an error in the CLI's stable prefix format and stop.
die() {
  printf '%s: %s\n' "$PROG" "$*" >&2
  exit 1
}

# Print a non-fatal warning.
warn() {
  printf '%s: %s\n' "$PROG" "$*" >&2
}

usage() {
  cat <<'EOF'
Usage: clusterConfig [global options] <command> [options] [-- args...]

Commands:
  init                    Create the XDG config file
  list                    List packages as a tree
  list --flat             List packages as an aligned table
  list --names-only       List package paths without descriptions
  show                    Show the flake overview (clusters, packages, apps)
  show <attr-path>        Show metadata for one package
  path <attr-path>        Print the equivalent nix run command
  run [<attr-path>]       Run a package; without a path opens fzf
  build [<attr-path>]     Build a package (ISO and other build outputs)
  complete [words...]     Completion helper (used by shell completions)
  completions <shell>     Print or install completion (bash|zsh|fish|nu|install)
  index [--names-only]    Print the package index as JSON

Global options:
  --flake <ref>           Flake reference (default: XDG config, then $PWD)
  --system <system>       Package system (default: flake packageSystem)
  --refresh, --no-cache   Accepted for compatibility
  --no-color              Disable ANSI colors
  -h, --help              Show this help

Package options for run/build:
  --dry-run               Print the command instead of executing it
  --keep-cwd              Run from the caller's directory instead of the flake root
  --yes, -y               Skip the destructive-command confirmation

Examples:
  clusterConfig list
  clusterConfig list --flat
  clusterConfig list --names-only
  clusterConfig show
  clusterConfig show example.vm0.iso
  clusterConfig show example vm0 iso
  clusterConfig path example vm0 iso
  clusterConfig run example vm0 deploy
  clusterConfig example vm0 deploy            # shorthand for run
  clusterConfig build example.vm0.iso
  eval "$(clusterConfig completions bash)"
EOF
}

# --- XDG configuration and flake discovery -------------------------------

# Directory of the optional user configuration.
config_dir() {
  printf '%s/cluster-config' "${XDG_CONFIG_HOME:-$HOME/.config}"
}

# Path of the optional JSON configuration file.
config_file() {
  printf '%s/config.json' "$(config_dir)"
}

# Read one top-level configuration value; return non-zero when it is absent.
config_value() {
  local key="$1" file
  file="$(config_file)"
  if [[ ! -f "$file" ]]; then
    return 1
  fi
  jq -er --arg key "$key" 'if has($key) then .[$key] else empty end' "$file" 2>/dev/null || return 1
}

# Walk upwards from a directory until a flake.nix is found.
find_flake_root() {
  local dir="$1"
  while [[ -n "$dir" && "$dir" != "/" ]]; do
    if [[ -f "$dir/flake.nix" ]]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

# Resolve the flake from --flake, the environment, XDG config, or $PWD.
# FLAKE_ROOT is only set for local flakes so run/build can preserve the caller's
# working directory while executing the package from the flake root.
resolve_flake() {
  local ref="${FLAKE_ARG:-${CLUSTER_CONFIG_FLAKE:-}}"
  if [[ -z "$ref" ]]; then
    ref="$(config_value flake || true)"
  fi
  if [[ -z "$ref" ]]; then
    local root
    root="$(find_flake_root "$PWD" || true)"
    if [[ -z "$root" ]]; then
      die "no flake found. Use --flake <ref>, set CLUSTER_CONFIG_FLAKE, or run 'clusterConfig init'."
    fi
    ref="$root"
  fi
  if [[ "$ref" == path:* ]]; then
    local path="${ref#path:}"
    if [[ -d "$path" ]]; then
      ref="$(realpath "$path")"
    fi
  elif [[ -d "$ref" ]]; then
    ref="$(realpath "$ref")"
  fi
  FLAKE_REF="$ref"
  if [[ -d "$ref" ]]; then
    FLAKE_ROOT="$(realpath "$ref")"
  else
    FLAKE_ROOT=""
  fi
}

# Invoke nix with the flake feature enabled, independent of user nix.conf.
nix_cmd() {
  nix --extra-experimental-features 'nix-command flakes' "$@"
}

# --- Package index and flake metadata ------------------------------------

# Fetch the complete index. Keep the system alongside packages so completion and
# command setup can use one evaluation.
index_json() {
  nix_cmd eval --json --no-write-lock-file "$FLAKE_REF#packageIndex" 2>/dev/null || printf '{"packages":[],"system":""}\n'
}

# Package entries only, as a compact JSON array.
packages_json() {
  index_json | jq -c '.packages // []'
}

# --- Attr path normalization and lookup ----------------------------------

# Join positional words with dots. This is shared by show/path/run/build so the
# dotted and shell-word forms behave identically.
join_attr_path() {
  local result="" part
  for part in "$@"; do
    [[ -z "$part" ]] && continue
    result="${result:+$result.}$part"
  done
  printf '%s' "$result"
}

# Return the index entry matching an exact dotted path, or an empty string.
package_entry() {
  local path="$1" data="$2"
  jq -c --arg p "$path" '.[] | select(.attrPath == $p)' <<<"$data"
}

# Explain an incomplete path (a namespace) before exiting. The package index is
# already in memory, so this is a cheap lookup and does not force any derivation.
die_unknown_package() {
  local path="$1" data="$2" children count=0 child
  printf '%s: unknown package: %s\n' "$PROG" "$path" >&2

  children="$(jq -r --arg p "$path" '
    [ .[]
      | select(.attrPath | startswith($p + "."))
      | .attrPath
      | ltrimstr($p + ".")
      | split(".")[0]
    ] | unique | .[]
  ' <<<"$data")"

  if [[ -n "$children" ]]; then
    printf 'hint: "%s" is a namespace. Available packages:\n' "$path" >&2
    while IFS= read -r child; do
      [[ -z "$child" ]] && continue
      if ((count >= 8)); then
        printf '  ...\n' >&2
        break
      fi
      printf '  %s.%s\n' "$path" "$child" >&2
      count=$((count + 1))
    done <<<"$children"
  else
    printf "hint: run '%s list' to see available packages.\n" "$PROG" >&2
  fi
  exit 1
}

# Non-forcing overview data for the show command.
flake_info_json() {
  nix_cmd eval --json --no-write-lock-file "$FLAKE_REF#flakeInfo" 2>/dev/null || printf '{"clusters":{},"nixosConfigurations":[]}\n'
}

# Names of the apps exposed for the selected system.
apps_json() {
  nix_cmd eval --json --no-write-lock-file "$FLAKE_REF#apps.$SYSTEM" --apply 'builtins.attrNames' 2>/dev/null || printf '[]\n'
}

# Optional detailed cluster data. This is deliberately separate and best effort;
# node values can recurse in self-referential machine definitions.
detailed_flake_info() {
  # Best effort: some self-referential machine definitions (for example a
  # targetHost derived from the machine's own nixosConfiguration) cannot be
  # forced here. In that case the basic flakeInfo remains usable.
  nix_cmd eval --json --no-write-lock-file "$FLAKE_REF#domain" --apply '
    d: builtins.mapAttrs (clusterName: cluster: {
      machines = builtins.mapAttrs (nodeName: node: {
        type = "machine";
        targetHost = node.deployment.targetHost or null;
        system = node.system or null;
        tags = node.tags or [ ];
        labels = node.labels or { };
        services = builtins.attrNames (node.services or { });
      }) (cluster.machines or { });
      vms = builtins.mapAttrs (nodeName: node: {
        type = "vm";
        targetHost = node.deployment.targetHost or null;
        system = node.system or null;
        host = node.host or null;
      }) (cluster.vms or { });
      services = builtins.mapAttrs (serviceName: service: {
        roles = builtins.attrNames (service.roles or { });
      }) (cluster.services or { });
    }) d.clusters
  ' 2>/dev/null || true
}

# Resolve all per-command context before dispatching. Flake/system lookups are
# intentionally centralized so commands and completions stay consistent.
prepare_context() {
  resolve_flake
  SYSTEM="${SYSTEM_ARG:-$(index_json | jq -r '.system // empty')}"
  if [[ -z "$SYSTEM" ]]; then
    SYSTEM="$(nix_cmd eval --raw --no-write-lock-file "$FLAKE_REF#packageSystem" 2>/dev/null || true)"
  fi
  if [[ -z "$SYSTEM" ]]; then
    SYSTEM="$(nix_cmd eval --raw --impure --expr 'builtins.currentSystem')"
  fi
  if [[ -z "$SYSTEM" ]]; then
    die "could not determine the package system"
  fi
}

# --- Output rendering ----------------------------------------------------

# Render ordered depth/path/label rows as a tree. Rows are deduplicated by path;
# the renderer calculates the last child at every level so branch endings are
# always └── without dangling vertical lines.
render_tree() {
  local root="$1"
  local color="${2:-0}"
  awk -F '\t' -v root="$root" -v color="$color" '
    function split_path(path, parts) {
      return split(path, parts, "\037");
    }
    function path_prefix(path, depth, parts, count, i, result) {
      count = split_path(path, parts);
      result = "";
      for (i = 1; i <= depth && i <= count; i++) {
        if (i > 1) result = result "\037";
        result = result parts[i];
      }
      return result;
    }
    function path_parent(path, parts, count, i, result) {
      count = split_path(path, parts);
      result = "";
      for (i = 1; i < count; i++) {
        if (i > 1) result = result "\037";
        result = result parts[i];
      }
      return result;
    }
    {
      if (seen[$2]++) next;
      n++;
      depth[n] = $1 + 0;
      path[n] = $2;
      label[n] = $3;
      action[n] = $4;
      flags[n] = $5;
      description[n] = $6;
    }
    END {
      if (color) printf "\033[1m%s\033[0m\n", root;
      else print root;
      for (i = 1; i <= n; i++) {
        d = depth[i];
        prefix = "";
        for (k = 1; k < d; k++) {
          ancestor = path_prefix(path[i], k);
          parent = path_parent(ancestor);
          last_ancestor = 1;
          for (j = i + 1; j <= n; j++) {
            if (depth[j] == k && path_parent(path[j]) == parent) {
              last_ancestor = 0;
              break;
            }
          }
          prefix = prefix (last_ancestor ? "    " : "│   ");
        }
        last = 1;
        current_parent = path_parent(path[i]);
        for (j = i + 1; j <= n; j++) {
          if (depth[j] == d && path_parent(path[j]) == current_parent) {
            last = 0;
            break;
          }
        }
        connector = (last ? "└── " : "├── ");
        if (color) connector = "\033[36m" connector "\033[0m";
        if (action[i] != "") {
          printf "%s%s%-24s %-5s %-12s %s\n", prefix, connector, label[i], action[i], flags[i], description[i];
        } else {
          printf "%s%s%s\n", prefix, connector, label[i];
        }
      }
    }
  '
}

# Convert package index entries into tree rows. A one-segment tool entry is
# grouped under a synthetic "tooling" namespace; cluster packages and nested
# package namespaces become ordinary tree levels.
package_tree_rows() {
  local data="$1"
  local prefix="${2:-}"
  local offset="${3:-0}"
  local all="${4:-0}"
  jq -r --arg prefix "$prefix" --argjson offset "$offset" --argjson all "$all" '
    def us: "\u001f";
    def group_path($cluster; $group):
      if $prefix == "" then $cluster + us + $group
      else $prefix + us + $cluster + us + $group
      end;
    def leaf_path($cluster; $group; $leaf):
      if $group == "" then
        (if $prefix == "" then $cluster + us + $leaf else $prefix + us + $cluster + us + $leaf end)
      else
        group_path($cluster; $group) + us + $leaf
      end;
    def row($depth; $path; $label; $action; $flags; $description):
      [$depth, $path, $label, $action, $flags, $description] | @tsv;
    .[] |
    (if (.segments | length) == 1 then
       { cluster: "tooling", group: "", kind: "tool", leaf: .segments[0] }
     elif (.segments | length) == 2 then
       { cluster: .segments[0], group: "", kind: .kind, leaf: .segments[1] }
     else
       { cluster: .segments[0], group: .segments[1], kind: .kind, leaf: (.segments[2:] | join(".")) }
     end) as $x |
    (.action // "run") as $action |
    (if .destructive == true then "destructive" else "" end) as $flags |
    (if $all == 1 and (.longDescription // null) != null then .longDescription else (.description // "") end) as $description |
    row((1 + $offset); (if $prefix == "" then $x.cluster else $prefix + us + $x.cluster end); $x.cluster; ""; ""; ""),
    (if $x.group == "" then empty else
       row((2 + $offset); group_path($x.cluster; $x.group);
         ($x.group + (if ($x.kind == "machine" or $x.kind == "vm" or $x.kind == "service") then " (" + $x.kind + ")" else "" end));
         ""; ""; "")
     end),
    row((if $x.group == "" then 2 + $offset else 3 + $offset end);
      leaf_path($x.cluster; $x.group; $x.leaf); $x.leaf; $action; $flags; $description)
  ' <<<"$data"
}

# Render the complete package index.
render_package_tree() {
  local data="$1"
  local all="${2:-0}"
  package_tree_rows "$data" "" 0 "$all" | render_tree "packages" "${COLOR:-0}"
}

# Render an aligned table for scripts and wide terminals.
render_flat_table() {
  local data="$1"
  {
    printf 'PATH\tACTION\tFLAGS\tDESCRIPTION\n'
    jq -r '.[] | [.attrPath, (.action // "run"), (if .destructive == true then "destructive" else "" end), (.description // "")] | @tsv' <<<"$data"
  } | column -t -s $'\t'
}

# Print one dotted path per line.
render_names() {
  local data="$1"
  jq -r '.[] | .segments | join(".")' <<<"$data"
}

# Build the cluster/machine/VM/service portion of the show tree.
cluster_overview_rows() {
  local info="$1"
  jq -r '
    def us: "\u001f";
    def row($depth; $path; $label): [$depth, $path, $label, "", "", ""] | @tsv;
    def detail($depth; $path; $label): [$depth, $path, $label, "", "", ""] | @tsv;

    row(1; "clusters"; "clusters"),
    (.clusters // {} | to_entries[] |
      .key as $cluster |
      row(2; "clusters" + us + $cluster; $cluster),

      row(3; "clusters" + us + $cluster + us + "machines"; "machines"),
      (.value.machines // {} | to_entries[] |
        .key as $machine |
        row(4; "clusters" + us + $cluster + us + "machines" + us + $machine; "\($machine) (machine)"),
        (if .value.targetHost != null then detail(5; "clusters" + us + $cluster + us + "machines" + us + $machine + us + "targetHost"; "targetHost: \(.value.targetHost)") else empty end),
        (if .value.system != null then detail(5; "clusters" + us + $cluster + us + "machines" + us + $machine + us + "system"; "system: \(.value.system)") else empty end),
        (if (.value.tags // []) | length > 0 then detail(5; "clusters" + us + $cluster + us + "machines" + us + $machine + us + "tags"; "tags: \(.value.tags | join(", "))") else empty end),
        (if (.value.labels // {}) | length > 0 then detail(5; "clusters" + us + $cluster + us + "machines" + us + $machine + us + "labels"; "labels: \(.value.labels | to_entries | map("\(.key)=\(.value)") | join(", "))") else empty end),
        (if (.value.services // []) | length > 0 then detail(5; "clusters" + us + $cluster + us + "machines" + us + $machine + us + "services"; "services: \(.value.services | join(", "))") else empty end)
      ),

      row(3; "clusters" + us + $cluster + us + "vms"; "vms"),
      (.value.vms // {} | to_entries[] |
        .key as $vm |
        row(4; "clusters" + us + $cluster + us + "vms" + us + $vm; "\($vm) (vm)"),
        (if .value.targetHost != null then detail(5; "clusters" + us + $cluster + us + "vms" + us + $vm + us + "targetHost"; "targetHost: \(.value.targetHost)") else empty end),
        (if .value.host != null then detail(5; "clusters" + us + $cluster + us + "vms" + us + $vm + us + "host"; "host: \(.value.host)") else empty end),
        (if .value.system != null then detail(5; "clusters" + us + $cluster + us + "vms" + us + $vm + us + "system"; "system: \(.value.system)") else empty end)
      ),

      row(3; "clusters" + us + $cluster + us + "services"; "services"),
      (.value.services // {} | to_entries[] |
        .key as $service |
        row(4; "clusters" + us + $cluster + us + "services" + us + $service; $service),
        (if (.value.roles // []) | length > 0 then detail(5; "clusters" + us + $cluster + us + "services" + us + $service + us + "roles"; "roles: \(.value.roles | join(", "))") else empty end)
      )
    )
  ' <<<"$info"
}

# Build the apps portion of the show tree.
apps_rows() {
  local apps="$1"
  jq -r '
    def us: "\u001f";
    def row($depth; $path; $label): [$depth, $path, $label, "", "", ""] | @tsv;
    row(1; "apps"; "apps"),
    (.[] | row(2; "apps" + us + .; .))
  ' <<<"$apps"
}

# Build the nixosConfigurations portion of the show tree.
nixos_rows() {
  local info="$1"
  jq -r '
    def us: "\u001f";
    def row($depth; $path; $label): [$depth, $path, $label, "", "", ""] | @tsv;
    row(1; "nixosConfigurations"; "nixosConfigurations"),
    (.nixosConfigurations // [] | .[] |
      row(2; "nixosConfigurations" + us + .name;
        "\(.name) (cluster: \(.clusterName), type: \(.type))"))
  ' <<<"$info"
}


# --- Shell completion ----------------------------------------------------

# Completion helper called by the generated shell scripts. It receives the words
# after the command, strips run/build/show/path, and returns direct children of
# the current package namespace. The tool package intentionally remains in the
# index and therefore appears as a valid package completion.
complete_cmd() {
  local format="plain"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)
        format="json"
        shift
        ;;
      --format)
        if [[ $# -lt 2 ]]; then
          die "--format needs a value"
        fi
        format="$2"
        shift 2
        ;;
      --)
        shift
        break
        ;;
      -*)
        die "unknown option for complete: $1"
        ;;
      *)
        break
        ;;
    esac
  done

  local -a words=("$@")
  if [[ ${#words[@]} -gt 0 ]]; then
    case "${words[0]}" in
      run|build|show|path)
        words=("${words[@]:1}")
        ;;
    esac
  fi

  local depth=0 prefix="" partial="" json
  if [[ ${#words[@]} -gt 0 ]]; then
    partial="${words[${#words[@]}-1]}"
    depth=$((${#words[@]} - 1))
    if ((depth > 0)); then
      prefix="$(printf '%s.' "${words[@]:0:$depth}")"
      prefix="${prefix%.}"
    fi
  fi

  json="$(packages_json)"
  local filter
  # shellcheck disable=SC2016
  filter='[ .[] | select((.segments[0:$depth] | join(".")) == $prefix) | select(.segments[$depth] != null) | select(.segments[$depth] | startswith($partial)) | { value: .segments[$depth], description: (.description // ""), kind: (.kind // "") } ] | unique_by(.value)'

  case "$format" in
    json)
      jq -c --arg prefix "$prefix" --arg partial "$partial" --argjson depth "$depth" "$filter" <<<"$json"
      ;;
    zsh)
      jq -r --arg prefix "$prefix" --arg partial "$partial" --argjson depth "$depth" "$filter | .[] | \"\\(.value):\\(.description)\"" <<<"$json"
      ;;
    fish)
      jq -r --arg prefix "$prefix" --arg partial "$partial" --argjson depth "$depth" "$filter | .[] | [.value, .description] | @tsv" <<<"$json"
      ;;
    plain)
      jq -r --arg prefix "$prefix" --arg partial "$partial" --argjson depth "$depth" "$filter | .[] | .value" <<<"$json"
      ;;
    *)
      die "unknown completion format: $format"
      ;;
  esac
}

# --- Commands ------------------------------------------------------------

# list renders package metadata in tree/table/name/JSON form without forcing
# package derivations.
list_cmd() {
  local json=0 names_only=0 flat=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)
        json=1
        shift
        ;;
      --names-only)
        names_only=1
        shift
        ;;
      --flat)
        flat=1
        shift
        ;;
      --tree|--refresh|--no-cache)
        shift
        ;;
      -*)
        die "unknown option for list: $1"
        ;;
      *)
        die "unexpected argument for list: $1"
        ;;
    esac
  done

  local data
  data="$(packages_json)"

  if ((json)); then
    jq . <<<"$data"
    return
  fi

  if ((names_only)); then
    render_names "$data"
    return
  fi

  if ((flat)); then
    render_flat_table "$data"
  else
    render_package_tree "$data"
  fi
}

# show prints the flake overview, or one package's metadata when a path is
# supplied. Positional words are joined so split paths work like run/build.
show_cmd() {
  local json=0 all=0 path=""
  local -a positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)
        json=1
        shift
        ;;
      --all)
        all=1
        shift
        ;;
      --refresh|--no-cache)
        shift
        ;;
      -*)
        die "unknown option for show: $1"
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done
  path="$(join_attr_path "${positional[@]}")"

  local data
  data="$(packages_json)"

  if [[ -n "$path" ]]; then
    local entry
    entry="$(package_entry "$path" "$data")"
    if [[ -z "$entry" ]]; then
      die_unknown_package "$path" "$data"
    fi
    if ((json)); then
      jq . <<<"$entry"
    else
      jq -r '
        "path:        \(.attrPath)",
        "kind:        \(.kind // "")",
        "action:      \(.action // "run")",
        "destructive: \(.destructive // false)",
        "description: \(.description // "")",
        (if (.longDescription // null) != null then "long:        \(.longDescription)" else empty end)
      ' <<<"$entry"
    fi
    return
  fi

  local info apps detailed
  info="$(flake_info_json)"
  apps="$(apps_json)"
  detailed="$(detailed_flake_info)"
  if [[ -n "$detailed" ]]; then
    info="$(jq -c -n --argjson base "$info" --argjson details "$detailed" '$base | .clusters = $details')"
  fi
  if ((json)); then
    jq -n --argjson info "$info" --argjson apps "$apps" --argjson packages "$data" \
      '{flakeInfo: $info, apps: $apps, packages: $packages}'
    return
  fi

  local root
  root="ClusterConfig flake: $FLAKE_REF ($(jq -r '.system // empty' <<<"$info"))"
  {
    cluster_overview_rows "$info"
    apps_rows "$apps"
    printf '1\tpackages\tpackages\t\t\t\n'
    package_tree_rows "$data" "packages" 1 "$all"
    nixos_rows "$info"
  } | render_tree "$root" "${COLOR:-0}"
}


# path prints the nix run command for one package.
path_cmd() {
  if [[ $# -eq 0 ]]; then
    die "usage: clusterConfig path <attr-path>"
  fi
  local path data
  path="$(join_attr_path "$@")"
  data="$(packages_json)"
  if [[ -z "$(package_entry "$path" "$data")" ]]; then
    die_unknown_package "$path" "$data"
  fi
  if [[ -n "$FLAKE_ROOT" ]]; then
    printf '(cd %q && nix run %q --)\n' "$FLAKE_ROOT" "$FLAKE_REF#$path"
  else
    printf 'nix run %q --\n' "$FLAKE_REF#$path"
  fi
}

# Shared implementation for run/build. It resolves a package, optionally opens
# fzf, confirms destructive actions, and executes in a subshell rooted at the
# flake so the caller's working directory never changes.
run_or_build() {
  local mode="$1"
  shift
  local dry_run=0 keep_cwd=0 yes=0
  local target=""
  local -a positional=()
  local -a extra=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        dry_run=1
        shift
        ;;
      --keep-cwd)
        keep_cwd=1
        shift
        ;;
      --yes|-y)
        yes=1
        shift
        ;;
      --refresh|--no-cache|--lazy)
        shift
        ;;
      --)
        shift
        extra=("$@")
        break
        ;;
      -*)
        die "unknown option for $mode: $1"
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done

  target="$(join_attr_path "${positional[@]}")"

  local data entry
  data="$(packages_json)"

  if [[ -z "$target" ]]; then
    target="$(
      jq -r '.[] | [.attrPath, (.description // ""), (.action // "run"), (if .destructive == true then "destructive" else "" end)] | @tsv' <<<"$data" |
        fzf --delimiter='\t' --with-nth='1,2' --nth='1,2' --prompt='clusterConfig> ' --height=60% --layout=reverse |
        cut -f1
    )" || true
    if [[ -z "$target" ]]; then
      printf 'cancelled\n' >&2
      exit 130
    fi
  fi

  entry="$(package_entry "$target" "$data")"
  if [[ -z "$entry" ]]; then
    die_unknown_package "$target" "$data"
  fi

  local action destructive
  action="$(jq -r '.action // "run"' <<<"$entry")"
  destructive="$(jq -r '.destructive // false' <<<"$entry")"

  if [[ "$mode" == "run" && "$action" == "build" ]]; then
    mode="build"
  fi

  if [[ "$destructive" == "true" && $yes -eq 0 && $dry_run -eq 0 ]]; then
    local answer
    read -r -p "Run destructive command '$target'? [y/N] " answer || true
    if [[ "$answer" != [yY]* ]]; then
      printf 'cancelled\n' >&2
      exit 130
    fi
  fi

  local -a run_cmd
  if [[ "$mode" == "build" ]]; then
    run_cmd=(nix build "$FLAKE_REF#$target")
  else
    run_cmd=(nix run "$FLAKE_REF#$target" --)
  fi

  if ((dry_run)); then
    if [[ -n "$FLAKE_ROOT" && $keep_cwd -eq 0 ]]; then
      printf '(cd %q && ' "$FLAKE_ROOT"
      printf '%q ' "${run_cmd[@]}" "${extra[@]}"
      printf ')\n'
    else
      printf '%q ' "${run_cmd[@]}" "${extra[@]}"
      printf '\n'
    fi
    return 0
  fi

  if [[ -n "$FLAKE_ROOT" && $keep_cwd -eq 0 ]]; then
    ( cd "$FLAKE_ROOT" && exec "${run_cmd[@]}" "${extra[@]}" )
  else
    exec "${run_cmd[@]}" "${extra[@]}"
  fi
}

# init writes the optional XDG config file used when no flake is passed.
init_cmd() {
  local flake="$FLAKE_ARG" system="$SYSTEM_ARG" force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --flake)
        if [[ $# -lt 2 ]]; then
          die "--flake needs a value"
        fi
        flake="$2"
        shift 2
        ;;
      --system)
        if [[ $# -lt 2 ]]; then
          die "--system needs a value"
        fi
        system="$2"
        shift 2
        ;;
      --force)
        force=1
        shift
        ;;
      *)
        die "unknown option for init: $1"
        ;;
    esac
  done

  if [[ -z "$flake" ]]; then
    flake="$(find_flake_root "$PWD" || true)"
    if [[ -z "$flake" ]]; then
      die "no flake found; pass --flake <ref>"
    fi
  fi
  if [[ -d "$flake" ]]; then
    flake="$(realpath "$flake")"
  fi

  if [[ -z "$system" ]]; then
    system="$(nix_cmd eval --json --no-write-lock-file "$flake#packageIndex" 2>/dev/null | jq -r '.system // empty')"
    if [[ -z "$system" ]]; then
      system="$(nix_cmd eval --raw --no-write-lock-file "$flake#packageSystem" 2>/dev/null || true)"
    fi
    if [[ -z "$system" ]]; then
      system="$(nix_cmd eval --raw --impure --expr 'builtins.currentSystem')"
    fi
  fi

  local dir file
  dir="$(config_dir)"
  file="$(config_file)"
  mkdir -p "$dir"
  if [[ -f "$file" && $force -eq 0 ]]; then
    die "config already exists: $file (use --force)"
  fi
  jq -n --arg flake "$flake" --arg system "$system" \
    '{flake: $flake, system: $system, cacheTtlSeconds: 300}' >"$file"
  printf 'wrote %s\n' "$file"
  printf 'flake: %s\nsystem: %s\n' "$flake" "$system"
  printf 'next: clusterConfig list\n'
}


# Emit the completion script for a normalized shell name.
completion_script() {
  local shell="$1"
  case "$shell" in
    bash)
      cat <<'EOF'
_cluster_config_complete() {
  local IFS=$'\n'
  COMPREPLY=( $(clusterConfig complete -- "${COMP_WORDS[@]:1}") )
}
complete -F _cluster_config_complete clusterConfig clcli
EOF
      ;;
    zsh)
      cat <<'EOF'
#compdef clusterConfig clcli
_cluster_config() {
  local -a candidates
  candidates=(${(f)"$(clusterConfig complete --format zsh -- ${words[2,-1]})"})
  _describe 'clusterConfig' candidates
}
compdef _cluster_config clusterConfig clcli
EOF
      ;;
    fish)
      cat <<'EOF'
complete -c clusterConfig -f -a '(clusterConfig complete --format fish -- (commandline -opc)[2..-1])'
complete -c clcli -f -a '(clusterConfig complete --format fish -- (commandline -opc)[2..-1])'
EOF
      ;;
    nu|nushell)
      cat <<'EOF'
def clusterConfigCompleter [context: list<string>] {
  let cmd = ($context | first)
  if (($cmd == "clusterConfig") or ($cmd == "clcli")) {
    ^clusterConfig complete --json -- ...($context | skip 1) | from json |
      each {|c| { value: $c.value, description: $c.description } }
  } else {
    []
  }
}
$env.config.completions.external = {
  enable: true
  max_results: 100
  completer: {|cmd| clusterConfigCompleter $cmd}
}
EOF
      ;;
    *)
      die "usage: clusterConfig completions <bash|zsh|fish|nu>"
      ;;
  esac
}

# Map accepted shell names to the internal bash/zsh/fish/nu values.
normalize_shell() {
  case "$1" in
    nu|nushell) printf 'nu\n' ;;
    bash|zsh|fish) printf '%s\n' "$1" ;;
    *) return 1 ;;
  esac
}

# Detect the interactive shell from $SHELL, defaulting to bash.
detect_shell() {
  local shell
  shell="$(basename "${SHELL:-bash}")"
  normalize_shell "$shell" || printf 'bash\n'
}

# Compute the per-shell completion destination, honoring XDG overrides and an
# explicit --dir.
completion_target() {
  local shell="$1"
  local dir="${2:-}"
  local file
  case "$shell" in
    bash)
      dir="${dir:-${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions}"
      file="clusterConfig"
      ;;
    zsh)
      dir="${dir:-${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions}"
      file="_clusterConfig"
      ;;
    fish)
      dir="${dir:-${XDG_CONFIG_HOME:-$HOME/.config}/fish/completions}"
      file="clusterConfig.fish"
      ;;
    nu)
      dir="${dir:-${XDG_CONFIG_HOME:-$HOME/.config}/nushell}"
      file="clusterConfig.nu"
      ;;
    *)
      die "unsupported shell: $shell"
      ;;
  esac
  printf '%s/%s\n' "$dir" "$file"
}

# Install completion into the selected shell's standard directory. Existing
# files require --force; --dry-run only prints the destination.
completions_install_cmd() {
  local shell="" dir="" force=0 dry_run=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --shell)
        if [[ $# -lt 2 ]]; then
          die "--shell needs a value"
        fi
        shell="$2"
        shift 2
        ;;
      --dir)
        if [[ $# -lt 2 ]]; then
          die "--dir needs a value"
        fi
        dir="$2"
        shift 2
        ;;
      --force)
        force=1
        shift
        ;;
      --dry-run)
        dry_run=1
        shift
        ;;
      -h|--help)
        cat <<'EOF'
Usage: clusterConfig completions install [shell] [options]

Options:
  --shell <shell>   bash, zsh, fish, or nu
  --dir <dir>       Override the destination directory
  --force           Overwrite an existing completion file
  --dry-run         Print the destination without writing
EOF
        return 0
        ;;
      -*)
        die "unknown option for completions install: $1"
        ;;
      *)
        if [[ -n "$shell" ]]; then
          die "unexpected argument: $1"
        fi
        shell="$1"
        shift
        ;;
    esac
  done

  shell="$(normalize_shell "${shell:-$(detect_shell)}")" || die "unsupported shell: ${shell:-auto}"
  local target
  target="$(completion_target "$shell" "$dir")"
  if ((dry_run)); then
    printf '%s\n' "$target"
    return 0
  fi

  mkdir -p "$(dirname "$target")"
  if [[ -e "$target" && $force -eq 0 ]]; then
    die "completion file already exists: $target (use --force)"
  fi
  completion_script "$shell" >"$target"
  printf 'installed %s completion: %s\n' "$shell" "$target"

  case "$shell" in
    zsh)
      printf 'add this to ~/.zshrc before compinit:\n'
      # shellcheck disable=SC2016
      printf '  fpath=(%s $fpath)\n' "$(dirname "$target")"
      printf '  autoload -Uz compinit && compinit\n'
      ;;
    nu)
      printf 'add this to your Nushell config:\n'
      printf '  source %s\n' "$target"
      ;;
    *)
      printf 'restart your shell to load the completion.\n'
      ;;
  esac
}

# Dispatch completion generation and installation.
completions_cmd() {
  case "${1:-}" in
    install)
      shift
      completions_install_cmd "$@"
      ;;
    bash|zsh|fish|nu|nushell)
      completion_script "$1"
      ;;
    *)
      die "usage: clusterConfig completions <bash|zsh|fish|nu|install>"
      ;;
  esac
}

# Print the raw package index for scripts and completion development.
index_cmd() {
  local names_only=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --names-only)
        names_only=1
        shift
        ;;
      --json|--refresh|--no-cache)
        shift
        ;;
      *)
        die "unknown option for index: $1"
        ;;
    esac
  done

  if ((names_only)); then
    packages_json | jq '[.[] | .segments | join(".")]'
  else
    index_json | jq .
  fi
}

# Parse global options, prepare flake/system context, and dispatch one command.
# Individual commands own their options and positional arguments.
main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --flake)
        if [[ $# -lt 2 ]]; then
          die "--flake needs a value"
        fi
        FLAKE_ARG="$2"
        shift 2
        ;;
      --system)
        if [[ $# -lt 2 ]]; then
          die "--system needs a value"
        fi
        SYSTEM_ARG="$2"
        shift 2
        ;;
      --refresh|--no-cache)
        shift
        ;;
      --no-color)
        COLOR=0
        NO_COLOR=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        die "unknown global option: $1"
        ;;
      *)
        break
        ;;
    esac
  done

  if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    COLOR=1
  fi

  local cmd="${1:-help}"
  shift || true
  case "$cmd" in
    help)
      usage
      ;;
    completions)
      completions_cmd "$@"
      ;;
    init)
      init_cmd "$@"
      ;;
    complete)
      prepare_context
      complete_cmd "$@"
      ;;
    list)
      prepare_context
      list_cmd "$@"
      ;;
    show)
      prepare_context
      show_cmd "$@"
      ;;
    path)
      prepare_context
      path_cmd "$@"
      ;;
    run)
      prepare_context
      run_or_build run "$@"
      ;;
    build)
      prepare_context
      run_or_build build "$@"
      ;;
    index)
      prepare_context
      index_cmd "$@"
      ;;
    *)
      prepare_context
      run_or_build run "$cmd" "$@"
      ;;
  esac
}

main "$@"
