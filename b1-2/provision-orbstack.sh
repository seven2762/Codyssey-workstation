#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_USER="${AGENT_USER:-agent}"
AGENT_UID="${AGENT_UID:-1000}"
AGENT_HOME="${AGENT_HOME:-/home/${AGENT_USER}/agent-app}"
AGENT_PORT="${AGENT_PORT:-15034}"
ENV_FILE="${ENV_FILE:-${AGENT_HOME}/.env}"

log() {
    printf '[provision] %s\n' "$*"
}

die() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

validate_config() {
    [[ "$AGENT_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] \
        || die "unsafe service user name: $AGENT_USER"
    [[ "$AGENT_UID" =~ ^[0-9]+$ ]] \
        || die "AGENT_UID must be an integer: $AGENT_UID"
    [[ "$AGENT_PORT" =~ ^[0-9]+$ ]] \
        || die "AGENT_PORT must be an integer: $AGENT_PORT"
    [ "$AGENT_PORT" -ge 1 ] && [ "$AGENT_PORT" -le 65535 ] \
        || die "AGENT_PORT must be between 1 and 65535: $AGENT_PORT"
    [[ "$AGENT_HOME" = /* ]] || die "AGENT_HOME must be an absolute path: $AGENT_HOME"
    [[ "$ENV_FILE" = /* ]] || die "ENV_FILE must be an absolute path: $ENV_FILE"
}

require_root_linux_amd64() {
    [ "${EUID}" -eq 0 ] || die "root 권한으로 실행하세요: sudo ./provision-orbstack.sh"
    [ "$(uname -s)" = "Linux" ] || die "이 스크립트는 OrbStack Linux machine 내부에서 실행해야 합니다."

    local arch
    arch=$(dpkg --print-architecture 2>/dev/null || uname -m)
    case "$arch" in
        amd64|x86_64) ;;
        *) die "agent-leak-app-x86 실행을 위해 amd64 machine이 필요합니다: current=$arch" ;;
    esac
}

install_packages() {
    local command_name missing=0
    for command_name in pgrep ps awk getconf file runuser; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            missing=1
        fi
    done

    if [ "$missing" -eq 0 ]; then
        log "required packages already installed"
        return
    fi

    log "installing required Ubuntu packages"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y procps gawk coreutils util-linux file sudo ca-certificates
}

ensure_agent_user() {
    local existing_user
    if id "$AGENT_USER" >/dev/null 2>&1; then
        [ "$(id -u "$AGENT_USER")" = "$AGENT_UID" ] \
            || die "existing user '$AGENT_USER' must use uid=$AGENT_UID"
        return
    fi

    existing_user=$(getent passwd "$AGENT_UID" | cut -d: -f1 || true)
    [ -z "$existing_user" ] \
        || die "uid=$AGENT_UID is already used by '$existing_user'; cannot create '$AGENT_USER'"

    log "creating service user: ${AGENT_USER}(uid=${AGENT_UID})"
    useradd --create-home --uid "$AGENT_UID" --shell /bin/bash "$AGENT_USER"
}

install_runtime() {
    local agent_group
    agent_group=$(id -gn "$AGENT_USER")

    log "installing runtime into $AGENT_HOME"
    install -d -o "$AGENT_USER" -g "$agent_group" -m 755 \
        "$AGENT_HOME" "$AGENT_HOME/bin" "$AGENT_HOME/evidence"

    install -o "$AGENT_USER" -g "$agent_group" -m 755 \
        "$SCRIPT_DIR/agent-leak-app-x86" "$AGENT_HOME/bin/agent-leak-app"

    local script
    for script in \
        monitor.sh \
        run-scenario.sh \
        run-all-scenarios.sh \
        setup-agent-env.sh \
        verify-results.sh \
        verify-orbstack.sh; do
        install -o "$AGENT_USER" -g "$agent_group" -m 755 \
            "$SCRIPT_DIR/$script" "$AGENT_HOME/bin/$script"
    done

    if [ -d "$SCRIPT_DIR/evidence" ]; then
        cp -a "$SCRIPT_DIR/evidence/." "$AGENT_HOME/evidence/"
        chown -R "$AGENT_USER:$agent_group" "$AGENT_HOME/evidence"
    fi
}

configure_environment() {
    local quoted_env quoted_user
    log "configuring reproducible agent environment"
    runuser -u "$AGENT_USER" -- env \
        AGENT_HOME="$AGENT_HOME" \
        AGENT_PORT="$AGENT_PORT" \
        ENV_FILE="$ENV_FILE" \
        bash "$AGENT_HOME/bin/setup-agent-env.sh"

    printf -v quoted_env '%q' "$ENV_FILE"
    printf -v quoted_user '%q' "$AGENT_USER"
    {
        printf '%s\n' '# b1-2 agent environment'
        printf 'if [ "$(id -un)" = %s ] && [ -r %s ]; then\n' "$quoted_user" "$quoted_env"
        printf '    . %s\n' "$quoted_env"
        printf '%s\n' 'fi'
    } > /etc/profile.d/b1-2-agent.sh
    chmod 644 /etc/profile.d/b1-2-agent.sh
}

install_command_links() {
    ln -sfn "$AGENT_HOME/bin/run-all-scenarios.sh" /usr/local/bin/b1-2-run-all
    ln -sfn "$AGENT_HOME/bin/verify-orbstack.sh" /usr/local/bin/b1-2-verify
}

print_summary() {
    local quoted_home
    printf -v quoted_home '%q' "$AGENT_HOME"
    cat <<EOF

========================================
  b1-2 OrbStack VM provisioning complete
========================================
machine arch : $(uname -m)
service user : ${AGENT_USER} (uid=$(id -u "$AGENT_USER"))
agent home   : ${AGENT_HOME}

Run all scenarios:
  sudo -u ${AGENT_USER} -H env AGENT_HOME=${quoted_home} ${quoted_home}/bin/run-all-scenarios.sh

Verify environment and evidence:
  sudo b1-2-verify
EOF
}

main() {
    validate_config
    require_root_linux_amd64
    install_packages
    ensure_agent_user
    install_runtime
    configure_environment
    install_command_links
    print_summary
}

main "$@"
