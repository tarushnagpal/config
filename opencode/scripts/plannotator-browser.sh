#!/usr/bin/env bash
set -euo pipefail

url="${1:-}"
[[ -n "$url" ]] || exit 0

devbox_host="${PLANNOTATOR_TAILNET_HOST:-devbox}"
laptop_host="${PLANNOTATOR_LAPTOP_HOST:?set PLANNOTATOR_LAPTOP_HOST}"
opener_port="${PLANNOTATOR_OPENER_PORT:-19500}"

case "$url" in
  http://localhost:*) rewritten="http://${devbox_host}:${url#http://localhost:}" ;;
  http://127.0.0.1:*) rewritten="http://${devbox_host}:${url#http://127.0.0.1:}" ;;
  *) rewritten="$url" ;;
esac

curl -fsS -m 3 "http://${laptop_host}:${opener_port}/open" \
  --data-urlencode "url=${rewritten}" >/dev/null 2>&1 &

exit 0
