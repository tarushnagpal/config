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
    printf 'Usage: %s <branch|origin/branch|short-name> [worktree-name]\n' "${0##*/}" >&2
    printf 'Example: %s tarush/ssh-issues\n' "${0##*/}" >&2
    printf 'Example: %s ssh-issues\n' "${0##*/}" >&2
    printf 'Example: %s main\n' "${0##*/}" >&2
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

normalize_name() {
    local branch="$1"
    local name

    if [[ "$branch" == "$BRANCH_PREFIX/"* ]]; then
        name="${branch#"$BRANCH_PREFIX/"}"
    else
        name="$branch"
    fi

    name="${name//\//-}"
    printf '%s\n' "$name"
}

checked_out_worktree_for_branch() {
    local branch="$1"
    local record_worktree=""
    local record_branch=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            worktree\ *)
                record_worktree="${line#worktree }"
                record_branch=""
                ;;
            branch\ refs/heads/*)
                record_branch="${line#branch refs/heads/}"
                ;;
            "")
                if [[ "$record_branch" == "$branch" ]]; then
                    printf '%s\n' "$record_worktree"
                    return 0
                fi
                record_worktree=""
                record_branch=""
                ;;
        esac
    done < <(git --git-dir="$BARE_REPO" worktree list --porcelain)

    if [[ "$record_branch" == "$branch" ]]; then
        printf '%s\n' "$record_worktree"
        return 0
    fi

    return 1
}

open_worktree_tab() {
    local tab_name="$1"
    local branch_name="$2"
    local dir="$3"

    "$HOME/.config/zellij/open-worktree-tab.sh" "$tab_name" "$dir" "$LAYOUT" || {
        printf 'Branch: %s\nWorktree: %s\n' "$branch_name" "$dir"
        exit 1
    }
    printf 'Branch: %s\nWorktree: %s\n' "$branch_name" "$dir"
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
    usage
    exit 2
fi

case "${1:-}" in
    --help|-h)
        usage
        exit 0
        ;;
esac

raw_branch="$1"

[[ -d "$MONO_ROOT" ]] || die "worktree container root does not exist: $MONO_ROOT"
[[ -d "$BARE_REPO" ]] || die "bare repo does not exist: $BARE_REPO"
DEFAULT_BRANCH="$(worktree_container_default_branch "$BARE_REPO")"

if [[ "$raw_branch" == "$DEFAULT_BRANCH" ]]; then
    # The default branch is the one unqualified branch that must not receive
    # the personal branch prefix. For example, `owt main` reopens worktrees/main.
    branch="$DEFAULT_BRANCH"
elif [[ "$raw_branch" == origin/* ]]; then
    branch="${raw_branch#origin/}"
elif [[ "$raw_branch" == */* ]]; then
    branch="$raw_branch"
else
    branch="$BRANCH_PREFIX/$raw_branch"
fi

if [[ $# -eq 2 ]]; then
    name="$2"
else
    name="$(normalize_name "$branch")"
fi

if [[ ! "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    die "worktree name must be flat and contain only letters, numbers, '.', '_' or '-'"
fi

mkdir -p "$WORKTREES_DIR"

if ! git --git-dir="$BARE_REPO" check-ref-format --branch "$branch" >/dev/null; then
    die "invalid branch name: $branch"
fi

remote_ref="refs/remotes/origin/$branch"
local_ref="refs/heads/$branch"
worktree_dir="$WORKTREES_DIR/$name"

if checked_out_path="$(checked_out_worktree_for_branch "$branch")"; then
    printf 'Branch %s is already checked out at %s.\n' "$branch" "$checked_out_path"
    open_worktree_tab "$name" "$branch" "$checked_out_path"
    exit 0
fi

if [[ -e "$worktree_dir" ]]; then
    die "worktree path already exists but is not registered for branch $branch: $worktree_dir"
fi

if [[ -n "${ZELLIJ:-}" ]]; then
    command -v zellij >/dev/null || die "zellij is not on PATH"
    [[ -f "$LAYOUT" ]] || die "zellij layout does not exist: $LAYOUT"
fi

printf 'Fetching origin/%s...\n' "$branch"
git --git-dir="$BARE_REPO" fetch origin "refs/heads/$branch:$remote_ref"

remote_sha="$(git --git-dir="$BARE_REPO" rev-parse "$remote_ref")"

if git --git-dir="$BARE_REPO" show-ref --verify --quiet "$local_ref"; then
    local_sha="$(git --git-dir="$BARE_REPO" rev-parse "$local_ref")"
    if ! merge_base="$(git --git-dir="$BARE_REPO" merge-base "$local_ref" "$remote_ref")"; then
        die "local branch $branch has no common ancestor with origin/$branch; resolve manually before opening a worktree"
    fi

    if [[ "$local_sha" == "$remote_sha" ]]; then
        printf 'Local branch %s already matches origin/%s.\n' "$branch" "$branch"
    elif [[ "$merge_base" == "$local_sha" ]]; then
        printf 'Fast-forwarding local branch %s to origin/%s.\n' "$branch" "$branch"
        git --git-dir="$BARE_REPO" update-ref "$local_ref" "$remote_sha" "$local_sha"
    elif [[ "$merge_base" == "$remote_sha" ]]; then
        printf 'Local branch %s is ahead of origin/%s; using local branch as-is.\n' "$branch" "$branch"
    else
        die "local branch $branch has diverged from origin/$branch; resolve manually before opening a worktree"
    fi

    git --git-dir="$BARE_REPO" config "branch.$branch.remote" .
    git --git-dir="$BARE_REPO" config "branch.$branch.merge" "$remote_ref"
    add_args=(worktree add "$worktree_dir" "$branch")
else
    printf 'Creating local tracking branch %s from origin/%s.\n' "$branch" "$branch"
    git --git-dir="$BARE_REPO" update-ref "$local_ref" "$remote_sha"
    git --git-dir="$BARE_REPO" config "branch.$branch.remote" .
    git --git-dir="$BARE_REPO" config "branch.$branch.merge" "$remote_ref"
    add_args=(worktree add "$worktree_dir" "$branch")
fi

printf 'Opening worktree %s for branch %s...\n' "$worktree_dir" "$branch"
git --git-dir="$BARE_REPO" "${add_args[@]}"

setup_marker="$(git -C "$worktree_dir" rev-parse --absolute-git-dir)/worktree-setup-pending"
: > "$setup_marker"

open_worktree_tab "$name" "$branch" "$worktree_dir"
