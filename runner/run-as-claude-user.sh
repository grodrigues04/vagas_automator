#!/usr/bin/env bash
# Sourced at the top of every script that runs Claude. The container starts as root, with the
# MongoDB URI and the encryption password in its environment, so it can send the results through
# interface-personal-whats. Claude reads web pages that may carry prompt injection, so it must
# never see those secrets: when started as root (scheduler or `docker exec`), the script runs
# itself again as the `node` user with a clean environment holding only what Claude needs.
# /proc/1/environ of a root process is not readable by `node`.
if [ "$(id -u)" = "0" ]; then
  exec setpriv --reuid=node --regid=node --init-groups \
    env -i \
      HOME=/home/node \
      PATH="$PATH" \
      TZ="${TZ:-America/Sao_Paulo}" \
      DISABLE_AUTOUPDATER=1 \
      DISABLE_TELEMETRY=1 \
      CLAUDE_CODE_OAUTH_TOKEN="${CLAUDE_CODE_OAUTH_TOKEN:-}" \
      CLAUDE_MODEL="${CLAUDE_MODEL:-}" \
      CLAUDE_TIMEOUT="${CLAUDE_TIMEOUT:-}" \
      CLAUDE_MAX_TURNS="${CLAUDE_MAX_TURNS:-}" \
      MANUAL_RUN="${MANUAL_RUN:-0}" \
      "$0" "$@"
fi
