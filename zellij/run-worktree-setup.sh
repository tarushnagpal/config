#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=worktree-container-lib.sh
source "$SCRIPT_DIR/worktree-container-lib.sh"

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

if_pending=0
if [[ "${1:-}" == "--if-pending" ]]; then
    if_pending=1
    shift
fi

worktree_dir="${1:-$PWD}"
[[ -d "$worktree_dir" ]] || die "worktree directory does not exist: $worktree_dir"
worktree_dir="$(cd "$worktree_dir" && pwd -P)"

marker=""
if gitdir="$(git -C "$worktree_dir" rev-parse --absolute-git-dir 2>/dev/null)"; then
    marker="$gitdir/worktree-setup-pending"
fi

if [[ "$if_pending" -eq 1 && ( -z "$marker" || ! -e "$marker" ) ]]; then
    exit 0
fi

container_root="$(worktree_find_container_root "$worktree_dir" || true)"
[[ -n "$container_root" ]] || die "could not find a worktree container root containing .bare above $worktree_dir"

setup_script="$container_root/.worktree-setup"

if [[ ! -e "$setup_script" ]]; then
    printf 'No .worktree-setup at %s; skipping worktree setup.\n' "$container_root"
    [[ -n "$marker" ]] && rm -f "$marker"
    exit 0
fi

[[ -x "$setup_script" ]] || die "setup script exists but is not executable: $setup_script"

printf 'Running %s in %s\n' "$setup_script" "$worktree_dir"
cd "$worktree_dir"
"$setup_script" "$worktree_dir"
if [[ -n "$marker" ]]; then
    rm -f "$marker"
fi
