# Attach opencode TUIs to the always-on devbox web server.
# Source this from ~/.zshrc after ~/.opencode/bin is on PATH.

[[ "$(uname -s 2>/dev/null)" == "Linux" ]] || return 0 2>/dev/null || exit 0

_opencode_load_web_env() {
  local env_file="${OPENCODE_WEB_ENV_FILE:-$HOME/.local/state/opencode-web.env}"
  [[ -f "$env_file" ]] || return 0
  set -a
  source "$env_file"
  set +a
}

_opencode_should_passthrough() {
  local first="${1:-}"
  case "$first" in
    -h|--help|-v|--version|--print-logs|--log-level|--pure|attach|web|serve|run|debug|providers|auth|agent|upgrade|uninstall|models|stats|export|import|github|pr|session|plugin|plug|db|completion|acp|mcp)
      return 0
      ;;
  esac
  return 1
}

opencode() {
  if _opencode_should_passthrough "${1:-}"; then
    command opencode "$@"
    return $?
  fi

  _opencode_load_web_env

  local port="${OPENCODE_WEB_PORT:-4096}"
  local host="${OPENCODE_WEB_HOST:-127.0.0.1}"
  local url="${OPENCODE_WEB_URL:-http://$host:$port}"
  local -a args
  args=(attach "$url" --dir "$PWD")

  [[ -n "${OPENCODE_SERVER_USERNAME:-}" ]] && args+=(--username "$OPENCODE_SERVER_USERNAME")
  [[ -n "${OPENCODE_SERVER_PASSWORD:-}" ]] && args+=(--password "$OPENCODE_SERVER_PASSWORD")

  command opencode "${args[@]}"
}
