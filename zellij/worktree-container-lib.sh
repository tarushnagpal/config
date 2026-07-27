#!/usr/bin/env bash

# Shared discovery helpers for repositories managed as bare-repo worktree
# containers. A container has this shape:
#
#   <root>/.bare/       bare Git repository
#   <root>/worktrees/   linked working trees
#
# PROXIMAL_MONO_ROOT remains the explicit override for backwards compatibility.

WORKTREE_CONTAINER_DEFAULT_ROOT="${WORKTREE_CONTAINER_DEFAULT_ROOT:-$HOME/workspace/proximal/mono}"

worktree_find_container_root() {
    local search_dir="${1:-$PWD}"

    if [[ ! -d "$search_dir" ]]; then
        search_dir="$(dirname "$search_dir")"
    fi
    [[ -d "$search_dir" ]] || return 1
    search_dir="$(cd "$search_dir" && pwd -P)"

    while :; do
        if [[ -d "$search_dir/.bare" ]]; then
            printf '%s\n' "$search_dir"
            return 0
        fi
        [[ "$search_dir" != "/" ]] || break
        search_dir="$(dirname "$search_dir")"
    done

    return 1
}

worktree_resolve_container_root() {
    local start_dir="${1:-$PWD}"
    local root=""

    if [[ -n "${PROXIMAL_MONO_ROOT:-}" ]]; then
        root="$PROXIMAL_MONO_ROOT"
    elif root="$(worktree_find_container_root "$start_dir")"; then
        :
    else
        root="$WORKTREE_CONTAINER_DEFAULT_ROOT"
    fi

    if [[ -d "$root" ]]; then
        (cd "$root" && pwd -P)
    else
        printf '%s\n' "$root"
    fi
}

worktree_container_default_branch() {
    local bare_repo="$1"
    local remote_head=""
    local local_head=""

    remote_head="$(
        git --git-dir="$bare_repo" symbolic-ref --quiet --short \
            refs/remotes/origin/HEAD 2>/dev/null || true
    )"
    if [[ "$remote_head" == origin/* ]]; then
        printf '%s\n' "${remote_head#origin/}"
        return 0
    fi

    # Bare clones record the remote's default branch in their own HEAD even
    # when refs/remotes/origin/HEAD has not been created. Only trust it when
    # the branch exists; a newly initialized bare repo may have an unborn HEAD.
    local_head="$(
        git --git-dir="$bare_repo" symbolic-ref --quiet --short HEAD 2>/dev/null || true
    )"
    if [[ -n "$local_head" ]] && \
        git --git-dir="$bare_repo" show-ref --verify --quiet "refs/heads/$local_head"; then
        printf '%s\n' "$local_head"
        return 0
    fi

    # Backwards-compatible fallback for existing main-based containers.
    printf '%s\n' main
}
