#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.opencode/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

env_file="${OPENCODE_WEB_ENV_FILE:-$HOME/.local/state/opencode-web.env}"
if [[ -f "$env_file" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a
fi

: "${OPENCODE_WEB_PORT:=4096}"
: "${OPENCODE_WEB_ROOT:=$HOME/workspace/proximal/mono}"
: "${OPENCODE_SERVER_USERNAME:=opencode}"
: "${PLANNOTATOR_REMOTE:=1}"
: "${PLANNOTATOR_PORT_BASE:=19432}"
: "${PLANNOTATOR_PORT_COUNT:=64}"
: "${PLANNOTATOR_TAILNET_HOST:=devbox}"
: "${PLANNOTATOR_BROWSER:=$HOME/.config/opencode/scripts/plannotator-browser.sh}"

export OPENCODE_SERVER_USERNAME
export OPENCODE_WEB_PORT OPENCODE_WEB_ROOT
export PLANNOTATOR_REMOTE PLANNOTATOR_PORT_BASE PLANNOTATOR_PORT_COUNT PLANNOTATOR_TAILNET_HOST PLANNOTATOR_BROWSER

if [[ ! -d "$OPENCODE_WEB_ROOT" ]]; then
  printf 'opencode web root does not exist: %s\n' "$OPENCODE_WEB_ROOT" >&2
  exit 1
fi

exec zsh -lc '
  source "$HOME/.zshrc"
  if [[ -x "$HOME/.config/opencode/scripts/patch-plannotator-session-active.js" ]]; then
    "$HOME/.config/opencode/scripts/patch-plannotator-session-active.js" || exit $?
  fi
  cd "$OPENCODE_WEB_ROOT"
  exec command opencode web --port "$OPENCODE_WEB_PORT"
'
