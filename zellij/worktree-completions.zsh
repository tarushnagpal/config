# Zsh completions for bare-repo worktree container helpers.

_proximal_worktree_mono_root() {
  if [[ -n "${PROXIMAL_MONO_ROOT:-}" ]]; then
    print -r -- "$PROXIMAL_MONO_ROOT"
    return 0
  fi

  local search_dir="${PWD:A}"
  while true; do
    if [[ -d "$search_dir/.bare" ]]; then
      print -r -- "$search_dir"
      return 0
    fi
    [[ "$search_dir" != "/" ]] || break
    search_dir="${search_dir:h}"
  done

  print -r -- "${WORKTREE_CONTAINER_DEFAULT_ROOT:-$HOME/workspace/proximal/mono}"
}

_proximal_worktree_bare_repo() {
  local mono_root
  mono_root="$(_proximal_worktree_mono_root)"
  print -r -- "${PROXIMAL_BARE_REPO:-$mono_root/.bare}"
}

_proximal_worktree_branch_prefix() {
  print -r -- "${PROXIMAL_BRANCH_PREFIX:-tarush}"
}

_proximal_worktree_default_branch() {
  local bare_repo remote_head head_branch
  bare_repo="$(_proximal_worktree_bare_repo)"
  [[ -d "$bare_repo" ]] || return 0

  remote_head="$(git --git-dir="$bare_repo" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
  if [[ "$remote_head" == origin/* ]]; then
    print -r -- "${remote_head#origin/}"
    return 0
  fi

  head_branch="$(git --git-dir="$bare_repo" symbolic-ref --quiet --short HEAD 2>/dev/null)"
  if [[ -n "$head_branch" ]] && git --git-dir="$bare_repo" show-ref --verify --quiet "refs/heads/$head_branch"; then
    print -r -- "$head_branch"
    return 0
  fi

  print -r -- main
}

_proximal_worktree_entries() {
  local bare_repo default_branch line wt_path branch bare name
  bare_repo="$(_proximal_worktree_bare_repo)"
  default_branch="$(_proximal_worktree_default_branch)"
  [[ -d "$bare_repo" ]] || return 0

  wt_path=""
  branch=""
  bare=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      worktree\ *)
        wt_path="${line#worktree }"
        branch=""
        bare=0
        ;;
      branch\ refs/heads/*)
        branch="${line#branch refs/heads/}"
        ;;
      bare)
        bare=1
        ;;
      "")
        if [[ -n "$wt_path" && "$bare" != "1" ]]; then
          name="${wt_path:t}"
          if [[ "$name" != ".bare" && "$branch" != "$default_branch" ]]; then
            print -r -- "$name:${branch:-$wt_path}"
          fi
        fi
        wt_path=""
        branch=""
        bare=0
        ;;
    esac
  done < <(git --git-dir="$bare_repo" worktree list --porcelain 2>/dev/null)

  if [[ -n "$wt_path" && "$bare" != "1" ]]; then
    name="${wt_path:t}"
    if [[ "$name" != ".bare" && "$branch" != "$default_branch" ]]; then
      print -r -- "$name:${branch:-$wt_path}"
    fi
  fi
}

_proximal_worktree_remote_branch_entries() {
  local bare_repo prefix ref short
  bare_repo="$(_proximal_worktree_bare_repo)"
  prefix="$(_proximal_worktree_branch_prefix)"
  [[ -d "$bare_repo" ]] || return 0

  while IFS= read -r ref; do
    [[ -n "$ref" && "$ref" != "HEAD" ]] || continue
    print -r -- "$ref:origin/$ref"
    if [[ "$ref" == "$prefix/"* ]]; then
      short="${ref#"$prefix/"}"
      [[ -n "$short" ]] && print -r -- "$short:origin/$ref"
    fi
  done < <(git --git-dir="$bare_repo" for-each-ref --format='%(refname:strip=3)' refs/remotes/origin 2>/dev/null)
}

_proximal_complete_worktrees() {
  local -a entries
  entries=("${(@f)$(_proximal_worktree_entries)}")
  _describe -t proximal-worktrees 'proximal worktree' entries
}

_proximal_complete_worktrees_and_branches() {
  local -a entries
  entries=("${(@f)$(_proximal_worktree_entries)}" "${(@f)$(_proximal_worktree_remote_branch_entries)}")
  _describe -t proximal-worktrees-and-branches 'proximal worktree or origin branch' entries
}

_nwt() {
  _arguments \
    '(-h --help)'{-h,--help}'[show help]' \
    '1:new worktree name:'
}

_owt() {
  _arguments \
    '(-h --help)'{-h,--help}'[show help]' \
    '1:worktree or branch:_proximal_complete_worktrees_and_branches' \
    '2:worktree name:'
}

_rmwt() {
  _arguments \
    '(-h --help)'{-h,--help}'[show help]' \
    '(-f --force)'{-f,--force}'[remove even if dirty]' \
    '--keep-branch[remove worktree but keep branch]' \
    '1:worktree:_proximal_complete_worktrees'
}

_wtsetup() {
  _arguments \
    '--if-pending[run only when setup marker exists]' \
    '1:worktree:_proximal_complete_worktrees'
}

_gclone() {
  _arguments \
    '(-h --help)'{-h,--help}'[show help]' \
    '1:Git repository URL:' \
    '2:container directory:_directories'
}

_piw() {
  _arguments '(-h --help)'{-h,--help}'[show help]'
}

compdef _nwt nwt
compdef _owt owt
compdef _rmwt rmwt
compdef _wtsetup wtsetup
compdef _gclone gclone
compdef _piw piw
