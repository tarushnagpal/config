#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=worktree-container-lib.sh
source "$SCRIPT_DIR/worktree-container-lib.sh"

MONO_ROOT="$(worktree_resolve_container_root "$PWD")"
BARE_REPO="${PROXIMAL_BARE_REPO:-$MONO_ROOT/.bare}"
WORKTREES_DIR="${PROXIMAL_WORKTREES_DIR:-$MONO_ROOT/worktrees}"

usage() {
    printf 'Usage: %s [--force] [--keep-branch] <worktree-name>\n' "${0##*/}" >&2
    printf 'Example: %s ssh-issues\n' "${0##*/}" >&2
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

record_matches_target() {
    [[ "$1" == "$preferred_dir" || "$1" == "$legacy_dir" ]]
}

store_record_if_target() {
    [[ -n "$record_worktree" ]] || return 0
    record_matches_target "$record_worktree" || return 0

    if [[ -z "$target_dir" || "$record_worktree" == "$preferred_dir" ]]; then
        target_dir="$record_worktree"
        target_branch="$record_branch"
        target_is_bare="$record_bare"
        prunable="$record_prunable"
    fi
}

force=0
keep_branch=0
name=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force|-f)
            force=1
            ;;
        --keep-branch)
            keep_branch=1
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        --*)
            die "unknown option: $1"
            ;;
        *)
            if [[ -n "$name" ]]; then
                die "expected one worktree name, got extra argument: $1"
            fi
            name="$1"
            ;;
    esac
    shift
done

if [[ -z "$name" ]]; then
    usage
    exit 2
fi

if [[ "$name" == */* ]]; then
    die "pass the worktree directory name only, not a path: $name"
fi

[[ -d "$MONO_ROOT" ]] || die "worktree container root does not exist: $MONO_ROOT"
[[ -d "$BARE_REPO" ]] || die "bare repo does not exist: $BARE_REPO"
DEFAULT_BRANCH="$(worktree_container_default_branch "$BARE_REPO")"

preferred_dir="$WORKTREES_DIR/$name"
legacy_dir="$MONO_ROOT/$name"
target_dir=""
target_branch=""
target_is_bare=0
prunable=0

record_worktree=""
record_branch=""
record_bare=0
record_prunable=0

while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == worktree\ * ]]; then
        store_record_if_target
        record_worktree="${line#worktree }"
        record_branch=""
        record_bare=0
        record_prunable=0
        continue
    fi

    case "$line" in
        branch\ refs/heads/*)
            record_branch="${line#branch refs/heads/}"
            ;;
        prunable*)
            record_prunable=1
            ;;
        bare)
            record_bare=1
            ;;
        "")
            store_record_if_target
            record_worktree=""
            record_branch=""
            record_bare=0
            record_prunable=0
            ;;
    esac
done < <(git --git-dir="$BARE_REPO" worktree list --porcelain)
store_record_if_target

if [[ -z "$target_dir" ]]; then
    die "not a registered worktree named '$name' under $WORKTREES_DIR or $MONO_ROOT"
fi

if [[ "$target_is_bare" -eq 1 || "$name" == ".bare" ]]; then
    die "refusing to remove the bare repository"
fi

if [[ "$name" == "$DEFAULT_BRANCH" || "$target_branch" == "$DEFAULT_BRANCH" ]]; then
    die "refusing to remove the default branch: $DEFAULT_BRANCH"
fi

if [[ -d "$target_dir" ]]; then
    target_real="$(cd "$target_dir" && pwd -P)"
    pwd_real="$(pwd -P)"
    if [[ "$pwd_real" == "$target_real" || "$pwd_real" == "$target_real/"* ]]; then
        die "you are inside $target_dir; cd out before removing it"
    fi

    if ! dirty_output="$(git -C "$target_dir" status --porcelain=v1 --untracked-files=all 2>&1)"; then
        if [[ "$force" -ne 1 ]]; then
            printf 'Could not inspect worktree status:\n%s\n' "$dirty_output" >&2
            die "use --force only if you are sure this worktree can be removed"
        fi
    elif [[ -n "$dirty_output" && "$force" -ne 1 ]]; then
        printf 'Worktree has uncommitted or untracked changes:\n%s\n' "$dirty_output" >&2
        die "use --force to remove it anyway"
    fi
else
    prunable=1
fi

removed_worktree=0

if [[ "$prunable" -eq 1 && ! -d "$target_dir" ]]; then
    printf 'Pruning missing worktree entry: %s\n' "$target_dir"
    git --git-dir="$BARE_REPO" worktree prune
    removed_worktree=1
else
    remove_args=(worktree remove)
    if [[ "$force" -eq 1 ]]; then
        remove_args+=(--force)
    fi
    remove_args+=("$target_dir")

    printf 'Removing worktree: %s\n' "$target_dir"
    if ! remove_output="$(git --git-dir="$BARE_REPO" "${remove_args[@]}" 2>&1)"; then
        printf '%s\n' "$remove_output" >&2
        if [[ "$remove_output" == *prunable* || "$remove_output" == *'does not exist'* ]]; then
            printf 'Pruning stale worktree entries...\n'
            git --git-dir="$BARE_REPO" worktree prune
        fi
        die "failed to remove worktree"
    fi
    [[ -n "$remove_output" ]] && printf '%s\n' "$remove_output"
    removed_worktree=1
fi

registry_action="no Pi pane registry"
registry="$HOME/.config/zellij/pi-session-registry.py"
if [[ "$removed_worktree" -eq 1 && -x "$registry" ]]; then
    registry_cwd="${target_real:-$target_dir}"
    if registry_output="$("$registry" clear --cwd "$registry_cwd" 2>&1)"; then
        if [[ "$registry_output" == *'"cleared": true'* ]]; then
            registry_action="removed Pi pane registry (session history retained)"
        fi
    else
        printf 'warning: failed to remove Pi pane registry: %s\n' "$registry_output" >&2
        registry_action="Pi pane registry cleanup failed"
    fi
fi

branch_action="no branch to delete"

if [[ -n "$target_branch" ]]; then
    if [[ "$keep_branch" -eq 1 ]]; then
        branch_action="kept branch $target_branch"
    elif ! git --git-dir="$BARE_REPO" show-ref --verify --quiet "refs/heads/$target_branch"; then
        branch_action="branch already absent: $target_branch"
    else
        unique_commits="$(git --git-dir="$BARE_REPO" rev-list --count "refs/remotes/origin/$DEFAULT_BRANCH..refs/heads/$target_branch" 2>/dev/null || printf 'unknown')"
        if [[ "$force" -eq 1 || "$unique_commits" == "0" ]]; then
            delete_flag="-D"
            if [[ "$force" -ne 1 ]]; then
                printf 'Branch has no commits beyond origin/%s; deleting branch: %s\n' \
                    "$DEFAULT_BRANCH" "$target_branch"
            else
                printf 'Force-deleting branch: %s\n' "$target_branch"
            fi
            git --git-dir="$BARE_REPO" branch "$delete_flag" "$target_branch"
            branch_action="deleted branch $target_branch"
        else
            printf 'Branch %s has commits not reachable from origin/%s.\n' \
                "$target_branch" "$DEFAULT_BRANCH" >&2
            printf 'Keeping it. Use --force to delete it, or --keep-branch to make that explicit.\n' >&2
            branch_action="kept branch $target_branch"
        fi
    fi
fi

tab_action="not in zellij"

if [[ -n "${ZELLIJ:-}" ]] && command -v zellij >/dev/null; then
    current_tab_id=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            id:\ *)
                current_tab_id="${line#id: }"
                ;;
        esac
    done < <(zellij action current-tab-info 2>/dev/null || true)

    target_tab_id=""
    while read -r tab_id _position tab_name rest; do
        [[ "$tab_id" == "TAB_ID" ]] && continue
        if [[ "$tab_name" == "$name" && -z "${rest:-}" ]]; then
            target_tab_id="$tab_id"
            break
        fi
    done < <(zellij action list-tabs 2>/dev/null || true)

    if [[ -z "$target_tab_id" ]]; then
        tab_action="no matching zellij tab"
    elif [[ "$target_tab_id" == "$current_tab_id" ]]; then
        tab_action="left current zellij tab open"
    else
        printf 'Closing zellij tab: %s\n' "$name"
        zellij action close-tab-by-id "$target_tab_id"
        tab_action="closed zellij tab $name"
    fi
fi

if [[ "$removed_worktree" -eq 1 ]]; then
    printf 'Removed worktree: %s\n' "$target_dir"
fi
printf '%s\n' "$branch_action"
printf '%s\n' "$tab_action"
printf '%s\n' "$registry_action"
