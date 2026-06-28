#!/usr/bin/env bash
set -euo pipefail

direction="${1:-}"

case "$direction" in
    next|prev) ;;
    *)
        printf 'Usage: %s <next|prev>\n' "$0" >&2
        exit 2
        ;;
esac

current_session="${ZELLIJ_SESSION_NAME:-}"

if [[ -z "$current_session" ]]; then
    printf 'ZELLIJ_SESSION_NAME is not set\n' >&2
    exit 1
fi

sessions=()
while IFS= read -r session; do
    [[ -n "$session" ]] && sessions+=("$session")
done < <(zellij list-sessions -s -n)

session_count="${#sessions[@]}"

if (( session_count < 2 )); then
    exit 0
fi

current_index=-1
for index in "${!sessions[@]}"; do
    if [[ "${sessions[$index]}" == "$current_session" ]]; then
        current_index="$index"
        break
    fi
done

if (( current_index < 0 )); then
    printf 'Current Zellij session not found: %s\n' "$current_session" >&2
    exit 1
fi

case "$direction" in
    next)
        target_index=$(( (current_index + 1) % session_count ))
        ;;
    prev)
        target_index=$(( (current_index - 1 + session_count) % session_count ))
        ;;
esac

target_session="${sessions[$target_index]}"

if [[ "$target_session" == "$current_session" ]]; then
    exit 0
fi

zellij action switch-session "$target_session"
