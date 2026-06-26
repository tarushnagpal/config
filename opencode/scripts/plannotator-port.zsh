# Allocate a stable Plannotator port per opencode process.
# Source this from ~/.zshrc after ~/.opencode/bin is on PATH.

_plannotator_port_in_use() {
  local port="$1"

  if command -v ss >/dev/null 2>&1; then
    ss -ltnH "sport = :$port" 2>/dev/null | grep -q .
    return $?
  fi

  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
    return $?
  fi

  bash -c "</dev/tcp/127.0.0.1/$port" >/dev/null 2>&1
}

_plannotator_reap_stale_lock() {
  local lock="$1" pid
  [[ -f "$lock" ]] || return 0
  pid="$(cat "$lock" 2>/dev/null)"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && return 0
  rm -f "$lock"
}

_plannotator_alloc_port() {
  local base="${PLANNOTATOR_PORT_BASE:-19432}"
  local count="${PLANNOTATOR_PORT_COUNT:-16}"
  local dir="${PLANNOTATOR_PORT_LOCK_DIR:-$HOME/.plannotator/ports}"
  local p lock

  mkdir -p "$dir"

  for (( p = base; p < base + count; p++ )); do
    lock="$dir/$p.lock"
    _plannotator_reap_stale_lock "$lock"
    _plannotator_port_in_use "$p" && continue

    if ( set -o noclobber; printf '%s\n' "$$" > "$lock" ) 2>/dev/null; then
      printf '%s\n' "$p"
      return 0
    fi
  done

  return 1
}

opencode() {
  local port lock rc
  local host="${PLANNOTATOR_TAILNET_HOST:-devbox}"
  local lock_dir="${PLANNOTATOR_PORT_LOCK_DIR:-$HOME/.plannotator/ports}"

  if ! port="$(_plannotator_alloc_port)"; then
    print -u2 "plannotator: no free port in ${PLANNOTATOR_PORT_BASE:-19432}..$(( ${PLANNOTATOR_PORT_BASE:-19432} + ${PLANNOTATOR_PORT_COUNT:-16} - 1 ))"
    return 1
  fi

  lock="$lock_dir/$port.lock"
  export PLANNOTATOR_PORT="$port"

  local url="http://$host:$port"
  printf '\e]8;;%s\e\\plannotator -> %s\e]8;;\e\\\n' "$url" "$url"

  command opencode "$@"
  rc=$?
  rm -f "$lock"
  return "$rc"
}
