#!/usr/bin/env bash

set -uo pipefail

AGENT_USER="${AGENT_USER:-agent}"
AGENT_HOME="${AGENT_HOME:-/home/${AGENT_USER}/agent-app}"
EVIDENCE_ROOT="${EVIDENCE_ROOT:-${AGENT_HOME}/evidence}"
VERIFY_EVIDENCE="${VERIFY_EVIDENCE:-1}"
FAILURES=0

pass() {
    printf '[PASS] %s\n' "$1"
}

fail() {
    printf '[FAIL] %s\n' "$1" >&2
    FAILURES=$((FAILURES + 1))
}

check_command() {
    local description=$1
    shift
    if "$@" >/dev/null 2>&1; then
        pass "$description"
    else
        fail "$description"
    fi
}

check_file() {
    local path=$1 description=$2
    if [ -f "$path" ]; then
        pass "$description"
    else
        fail "$description (missing: $path)"
    fi
}

check_executable() {
    local path=$1 description=$2
    if [ -x "$path" ]; then
        pass "$description"
    else
        fail "$description (not executable: $path)"
    fi
}

check_static_environment() {
    printf '\n## VM and service user\n'
    case "$(uname -m)" in
        x86_64|amd64) pass "machine architecture is amd64" ;;
        *) fail "machine architecture must be amd64: $(uname -m)" ;;
    esac

    check_command "service user exists" id "$AGENT_USER"
    if id "$AGENT_USER" >/dev/null 2>&1 && [ "$(id -u "$AGENT_USER")" = "1000" ]; then
        pass "service user uid is 1000"
    else
        fail "service user uid must be 1000"
    fi

    printf '\n## Runtime files\n'
    check_executable "$AGENT_HOME/bin/agent-leak-app" "agent binary"
    local script
    for script in \
        monitor.sh run-scenario.sh run-all-scenarios.sh \
        setup-agent-env.sh verify-results.sh verify-orbstack.sh; do
        check_executable "$AGENT_HOME/bin/$script" "$script"
        if [ -f "$AGENT_HOME/bin/$script" ]; then
            check_command "$script syntax" bash -n "$AGENT_HOME/bin/$script"
        fi
    done

    printf '\n## Required environment\n'
    check_file "$AGENT_HOME/.env" "sourceable agent environment"
    check_file "$AGENT_HOME/api_keys/secret.key" "required API key file"
    if [ -f "$AGENT_HOME/api_keys/secret.key" ] \
        && [ "$(< "$AGENT_HOME/api_keys/secret.key")" = "agent_api_key_test" ]; then
        pass "API key has the expected test value"
    else
        fail "API key content does not match the binary contract"
    fi

    check_command "agent can write upload directory" \
        runuser -u "$AGENT_USER" -- test -w "$AGENT_HOME/upload_files"
    check_command "agent can write log directory" \
        runuser -u "$AGENT_USER" -- test -w "$AGENT_HOME/logs"
    check_command "agent can write evidence directory" \
        runuser -u "$AGENT_USER" -- test -w "$EVIDENCE_ROOT"
}

main() {
    check_static_environment

    if [ "$VERIFY_EVIDENCE" = "1" ]; then
        printf '\n## Scenario evidence\n'
        if ! EVIDENCE_ROOT="$EVIDENCE_ROOT" bash "$AGENT_HOME/bin/verify-results.sh"; then
            FAILURES=$((FAILURES + 1))
        fi
    fi

    printf '\n'
    if [ "$FAILURES" -eq 0 ]; then
        printf 'OrbStack environment and b1-2 evidence verification passed.\n'
        exit 0
    fi

    printf 'OrbStack verification failed: %s check group(s).\n' "$FAILURES" >&2
    exit 1
}

main "$@"
