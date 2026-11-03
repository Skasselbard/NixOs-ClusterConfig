#!/usr/bin/env bash
# Reset the example's tracked secret material and remove generated files.
# This script is example-only; it is not a secret-service package.
set -euo pipefail

cd "$(dirname "$0")"

all=0
case "${1:-}" in
  "")
    ;;
  --all)
    all=1
    ;;
  -h | --help)
    cat <<'EOF'
Usage: cleanupSecrets.sh [--all]

Restore tracked example secrets and test key material from HEAD, then remove
untracked files under the example secret roots.

  --all   also remove ignored build outputs such as result, build and .direnv
EOF
    exit 0
    ;;
  *)
    echo "Unknown argument: $1" >&2
    echo "Usage: $0 [--all]" >&2
    exit 2
    ;;
esac

repo_root="$(git -C "$PWD" rev-parse --show-toplevel)"

restore_paths=(
  examples/04-secretDeployment/secrets
  examples/00-exampleConfigs/secrets
)
ignored_paths=(
  examples/04-secretDeployment/result
  examples/04-secretDeployment/build
  examples/04-secretDeployment/.direnv
)

cat <<'EOF'
This resets the example's tracked sops files, age keys, KeePass database and
test key material from HEAD.

It discards local staged and working-tree changes under:
  examples/04-secretDeployment/secrets
  examples/00-exampleConfigs/secrets
EOF

if [ "$all" -eq 1 ]; then
  echo
  echo "It also removes ignored build outputs under the example directory."
else
  echo
  echo "Use --all to also remove ignored build outputs such as result."
fi

read -r -p "Continue? [y/N] " answer
case "$answer" in
  y | Y) ;;
  *)
    echo "Aborted."
    exit 1
    ;;
esac

git -C "$repo_root" restore --source=HEAD --staged --worktree -- "${restore_paths[@]}"

# Remove generated placeholders and temporary files. This does not touch the
# cleanup script itself, even before it has been committed.
for path in "${restore_paths[@]}"; do
  if [ -e "$repo_root/$path" ] || [ -L "$repo_root/$path" ]; then
    git -C "$repo_root" clean -fd -- "$path"
  fi
done

if [ "$all" -eq 1 ]; then
  # Include ignored outputs such as the result symlink and build directories.
  for path in "${restore_paths[@]}" "${ignored_paths[@]}"; do
    if [ -e "$repo_root/$path" ] || [ -L "$repo_root/$path" ]; then
      git -C "$repo_root" clean -fdx -- "$path"
    fi
  done
fi

echo "Example secrets and tracked key material reset."
