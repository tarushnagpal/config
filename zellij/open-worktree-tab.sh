#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=worktree-container-lib.sh
source "$SCRIPT_DIR/worktree-container-lib.sh"

tab_name="${1:-}"
worktree_dir="${2:-}"
layout="${3:-${PROXIMAL_WORKTREE_LAYOUT:-$HOME/.config/zellij/layouts/worktree.kdl}}"

[[ -n "$tab_name" && -n "$worktree_dir" ]] || {
    printf 'Usage: %s <tab-name> <worktree-dir> [layout]\n' "${0##*/}" >&2
    exit 2
}
[[ -d "$worktree_dir" ]] || {
    printf 'error: worktree directory does not exist: %s\n' "$worktree_dir" >&2
    exit 1
}
worktree_dir="$(cd "$worktree_dir" && pwd -P)"
container_root="$(worktree_resolve_container_root "$worktree_dir")"
[[ -d "$container_root" ]] || {
    printf 'error: worktree container root does not exist: %s\n' "$container_root" >&2
    exit 1
}

if [[ -z "${ZELLIJ:-}" ]]; then
    printf 'Not inside zellij; no tab was opened.\n'
    exit 0
fi

command -v zellij >/dev/null || {
    printf 'error: zellij is not on PATH\n' >&2
    exit 1
}
command -v python3 >/dev/null || {
    printf 'error: python3 is not on PATH\n' >&2
    exit 1
}
[[ -f "$layout" ]] || {
    printf 'error: zellij layout does not exist: %s\n' "$layout" >&2
    exit 1
}

if zellij action list-tabs --json --all 2>/dev/null | python3 -c '
import json, sys
name = sys.argv[1]
raise SystemExit(0 if any(tab.get("name") == name for tab in json.load(sys.stdin)) else 1)
' "$tab_name"; then
    zellij action go-to-tab-name "$tab_name"
    printf 'Focused existing zellij tab %s.\n' "$tab_name"
    exit 0
fi

# Keep the tab itself rooted at the container so Zellij can serialize it after
# the associated worktree is deleted. Command panes, including Pi, start in the
# worktree. Sanitized resurrection layouts bootstrap registered Pi panes from
# the container only long enough for the launcher to resolve their durable slot.
# Custom layouts must use inline `pane ... command="..."` attributes; an
# existing inline `cwd="..."` is preserved. This matches the repository layout.
rendered_layout_dir="$(mktemp -d "${TMPDIR:-/tmp}/pi-worktree-layout.XXXXXX")"
rendered_layout="$rendered_layout_dir/layout.kdl"
trap 'rm -rf "$rendered_layout_dir"' EXIT
python3 - "$layout" "$rendered_layout" "$worktree_dir" <<'PY'
import json
import re
import sys
from pathlib import Path

source, target, worktree = map(Path, sys.argv[1:])
rendered = []
for number, line in enumerate(source.read_text(encoding="utf-8").splitlines(keepends=True), 1):
    stripped = line.lstrip()
    if stripped.startswith("pane ") and re.search(r"\bcommand\s*=", line) and not re.search(r"\bcwd\s*=", line):
        newline = "\n" if line.endswith("\n") else ""
        body = line[:-1] if newline else line
        brace = body.rfind("{")
        if brace >= 0:
            body = f"{body[:brace].rstrip()} cwd={json.dumps(str(worktree), ensure_ascii=False)} {body[brace:]}"
        else:
            body = f"{body.rstrip()} cwd={json.dumps(str(worktree), ensure_ascii=False)}"
        line = body + newline
    rendered.append(line)
target.write_text("".join(rendered), encoding="utf-8")
PY

printf 'Opening zellij tab %s...\n' "$tab_name"
if ! tab_id="$(zellij action new-tab --name "$tab_name" --cwd "$container_root" --layout "$rendered_layout" 2>&1)"; then
    printf 'Failed to open zellij tab:\n%s\n' "$tab_id" >&2
    exit 1
fi
printf 'Opened zellij tab %s (id %s).\n' "$tab_name" "$tab_id"
