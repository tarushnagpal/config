#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=worktree-container-lib.sh
source "$SCRIPT_DIR/worktree-container-lib.sh"

MONO_ROOT="$(worktree_resolve_container_root "$PWD")"
BARE_REPO="${PROXIMAL_BARE_REPO:-$MONO_ROOT/.bare}"
BRANCH_PREFIX="${PROXIMAL_BRANCH_PREFIX:-tarush}"
LAYOUT="${PROXIMAL_WORKTREE_LAYOUT:-$HOME/.config/zellij/layouts/worktree.kdl}"
WORKTREES_DIR="${PROXIMAL_WORKTREES_DIR:-$MONO_ROOT/worktrees}"

usage() {
    printf 'Usage: %s <short-branch-name>\n' "${0##*/}" >&2
    printf 'Example: %s ssh-issues\n' "${0##*/}" >&2
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

if [[ $# -ne 1 ]]; then
    usage
    exit 2
fi

name="$1"

if [[ "$name" == "$BRANCH_PREFIX/"* ]]; then
    die "pass the short name only, e.g. '${name#"$BRANCH_PREFIX/"}' instead of '$name'"
fi

if [[ ! "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    die "name must be flat and contain only letters, numbers, '.', '_' or '-'"
fi

branch="$BRANCH_PREFIX/$name"
worktree_dir="$WORKTREES_DIR/$name"

[[ -d "$MONO_ROOT" ]] || die "worktree container root does not exist: $MONO_ROOT"
[[ -d "$BARE_REPO" ]] || die "bare repo does not exist: $BARE_REPO"
DEFAULT_BRANCH="$(worktree_container_default_branch "$BARE_REPO")"
mkdir -p "$WORKTREES_DIR"

if [[ -e "$worktree_dir" ]]; then
    die "worktree path already exists: $worktree_dir"
fi

if ! git --git-dir="$BARE_REPO" check-ref-format --branch "$branch" >/dev/null; then
    die "invalid branch name: $branch"
fi

if git --git-dir="$BARE_REPO" show-ref --verify --quiet "refs/heads/$branch"; then
    die "branch already exists: $branch"
fi

if [[ -n "${ZELLIJ:-}" ]]; then
    command -v zellij >/dev/null || die "zellij is not on PATH"
    [[ -f "$LAYOUT" ]] || die "zellij layout does not exist: $LAYOUT"
fi

printf 'Fetching latest origin/%s...\n' "$DEFAULT_BRANCH"
git --git-dir="$BARE_REPO" fetch origin \
    "refs/heads/$DEFAULT_BRANCH:refs/remotes/origin/$DEFAULT_BRANCH"

base_sha="$(git --git-dir="$BARE_REPO" rev-parse --short "refs/remotes/origin/$DEFAULT_BRANCH")"

printf 'Creating worktree %s from origin/%s (%s)...\n' \
    "$worktree_dir" "$DEFAULT_BRANCH" "$base_sha"
git --git-dir="$BARE_REPO" worktree add -b "$branch" "$worktree_dir" \
    "refs/remotes/origin/$DEFAULT_BRANCH"
setup_marker="$(git -C "$worktree_dir" rev-parse --absolute-git-dir)/worktree-setup-pending"
: > "$setup_marker"

if ! "$HOME/.config/zellij/open-worktree-tab.sh" "$name" "$worktree_dir" "$LAYOUT"; then
    printf 'Created worktree, but failed to open its zellij tab.\n' >&2
    printf 'Branch: %s\nWorktree: %s\n' "$branch" "$worktree_dir"
    exit 1
fi

printf 'Branch: %s\nWorktree: %s\n' "$branch" "$worktree_dir"
