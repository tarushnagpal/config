#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf 'Usage: %s <git-url> [container-directory]\n' "${0##*/}" >&2
    printf 'Example: %s git@github.com:Proximal-Labs/example.git\n' "${0##*/}" >&2
    printf 'Example: %s git@github.com:Proximal-Labs/example.git ~/workspace/example\n' "${0##*/}" >&2
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

created_dir=""
clone_complete=0
cleanup_failed_clone() {
    local status=$?

    if [[ "$status" -ne 0 && "$clone_complete" -ne 1 && -n "$created_dir" ]]; then
        printf 'Cleaning up incomplete worktree container: %s\n' "$created_dir" >&2
        rm -rf -- "$created_dir"
    fi
}
trap cleanup_failed_clone EXIT

case "${1:-}" in
    --help|-h)
        usage
        exit 0
        ;;
esac

if [[ $# -lt 1 || $# -gt 2 ]]; then
    usage
    exit 2
fi

url="$1"
if [[ $# -eq 2 ]]; then
    requested_dir="$2"
else
    repo_name="${url%/}"
    repo_name="${repo_name##*/}"
    repo_name="${repo_name##*:}"
    repo_name="${repo_name%.git}"
    [[ -n "$repo_name" ]] || die "could not derive a directory name from URL: $url"
    requested_dir="$repo_name"
fi

[[ ! -e "$requested_dir" && ! -L "$requested_dir" ]] || \
    die "destination already exists: $requested_dir"

mkdir -p -- "$requested_dir"
created_dir="$requested_dir"
container_root="$(cd "$requested_dir" && pwd -P)"
bare_repo="$container_root/.bare"
worktrees_dir="$container_root/worktrees"

printf 'Initializing bare repository at %s...\n' "$bare_repo"
git init --bare "$bare_repo"
git --git-dir="$bare_repo" remote add origin "$url"
git --git-dir="$bare_repo" config remote.origin.fetch \
    '+refs/heads/*:refs/remotes/origin/*'

printf 'Fetching origin...\n'
git --git-dir="$bare_repo" fetch --prune origin
printf 'Detecting the remote default branch...\n'
git --git-dir="$bare_repo" remote set-head origin --auto

remote_head="$(
    git --git-dir="$bare_repo" symbolic-ref --quiet --short refs/remotes/origin/HEAD
)"
[[ "$remote_head" == origin/* ]] || \
    die "origin/HEAD is not a remote branch: $remote_head"
default_branch="${remote_head#origin/}"
remote_ref="refs/remotes/origin/$default_branch"
local_ref="refs/heads/$default_branch"

git --git-dir="$bare_repo" rev-parse --verify "$remote_ref" >/dev/null
git --git-dir="$bare_repo" update-ref "$local_ref" "$remote_ref"
git --git-dir="$bare_repo" symbolic-ref HEAD "$local_ref"
git --git-dir="$bare_repo" config "branch.$default_branch.remote" origin
git --git-dir="$bare_repo" config "branch.$default_branch.merge" \
    "refs/heads/$default_branch"

mkdir -p "$worktrees_dir"
printf 'Creating the %s worktree...\n' "$default_branch"
git --git-dir="$bare_repo" worktree add \
    "$worktrees_dir/$default_branch" "$default_branch"

if [[ "$default_branch" == "main" ]]; then
    ln -s "worktrees/main" "$container_root/main"
fi
clone_complete=1

printf '\nCreated worktree container:\n'
printf '  Root:           %s\n' "$container_root"
printf '  Bare repo:      %s\n' "$bare_repo"
printf '  Default branch: %s\n' "$default_branch"
printf '  Default tree:   %s\n' "$worktrees_dir/$default_branch"
if [[ "$default_branch" == "main" ]]; then
    printf '  Stable path:    %s\n' "$container_root/main"
fi
printf '\nNext steps:\n'
printf '  cd %q\n' "$container_root"
printf '  nwt <new-branch-name>\n'
printf '  owt origin/<existing-branch>\n'
printf 'Optionally add an executable %s/.worktree-setup script.\n' "$container_root"
