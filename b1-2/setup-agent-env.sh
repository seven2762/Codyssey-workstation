#!/usr/bin/env bash

set -euo pipefail

AGENT_HOME="${AGENT_HOME:-/home/agent/agent-app}"
AGENT_PORT="${AGENT_PORT:-15034}"
AGENT_UPLOAD_DIR="${AGENT_UPLOAD_DIR:-${AGENT_HOME}/upload_files}"
AGENT_KEY_PATH="${AGENT_KEY_PATH:-${AGENT_HOME}/api_keys}"
AGENT_LOG_DIR="${AGENT_LOG_DIR:-${AGENT_HOME}/logs}"
AGENT_KEY_FILE="${AGENT_KEY_FILE:-${AGENT_KEY_PATH}/secret.key}"
AGENT_KEY_VALUE="${AGENT_KEY_VALUE:-agent_api_key_test}"
ENV_FILE="${ENV_FILE:-${AGENT_HOME}/.env}"

log() {
    printf '[setup-agent-env] %s\n' "$*"
}

validate_port() {
    case "$AGENT_PORT" in
        ''|*[!0-9]*)
            printf '[ERROR] AGENT_PORT must be an integer: %s\n' "$AGENT_PORT" >&2
            exit 1
            ;;
    esac

    if [ "$AGENT_PORT" -lt 1 ] || [ "$AGENT_PORT" -gt 65535 ]; then
        printf '[ERROR] AGENT_PORT must be between 1 and 65535: %s\n' "$AGENT_PORT" >&2
        exit 1
    fi
}

write_environment_file() {
    mkdir -p "$(dirname "$ENV_FILE")"
    umask 077
    {
        printf 'export AGENT_HOME=%q\n' "$AGENT_HOME"
        printf 'export AGENT_PORT=%q\n' "$AGENT_PORT"
        printf 'export AGENT_UPLOAD_DIR=%q\n' "$AGENT_UPLOAD_DIR"
        printf 'export AGENT_KEY_PATH=%q\n' "$AGENT_KEY_PATH"
        printf 'export AGENT_LOG_DIR=%q\n' "$AGENT_LOG_DIR"
    } > "$ENV_FILE"
    chmod 600 "$ENV_FILE"
}

create_directories_and_key() {
    mkdir -p "$AGENT_HOME" "$AGENT_UPLOAD_DIR" "$AGENT_KEY_PATH" "$AGENT_LOG_DIR"
    chmod 755 "$AGENT_HOME" "$AGENT_UPLOAD_DIR" "$AGENT_LOG_DIR"
    chmod 700 "$AGENT_KEY_PATH"

    if [ ! -e "$AGENT_KEY_FILE" ]; then
        umask 077
        printf '%s\n' "$AGENT_KEY_VALUE" > "$AGENT_KEY_FILE"
        log "created key file: $AGENT_KEY_FILE"
    else
        log "preserving existing key file: $AGENT_KEY_FILE"
    fi
    chmod 600 "$AGENT_KEY_FILE"
}

main() {
    validate_port
    create_directories_and_key
    write_environment_file

    log "environment ready"
    printf '  AGENT_HOME=%s\n' "$AGENT_HOME"
    printf '  AGENT_PORT=%s\n' "$AGENT_PORT"
    printf '  ENV_FILE=%s\n' "$ENV_FILE"
    printf '  load with: source %q\n' "$ENV_FILE"
}

main "$@"
