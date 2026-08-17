#!/usr/bin/env bash

set -euo pipefail

MACHINE_NAME="${MACHINE_NAME:-b1-2-agent}"
DISTRO="${DISTRO:-ubuntu:noble}"
ARCH="${ARCH:-amd64}"
ORB_BIN="${ORB_BIN:-orb}"
ACTION="${1:-up}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_AGENT_HOME="${VM_AGENT_HOME:-/home/agent/agent-app}"

usage() {
    cat <<EOF
Usage: ${0} [up|create|start|shell|provision|run-all|verify|collect|demo|reset-demo|stop|delete|list]

Actions:
  up          Create/start the machine and open a shell (default)
  provision   Install the b1-2 runtime in the VM
  run-all     Reproduce all seven Before/After scenarios
  verify      Verify VM configuration and collected evidence
  collect     Copy VM evidence back into this repository
  demo        provision -> run-all -> verify -> collect
  reset-demo  delete/create a clean VM, then run demo

Environment overrides:
  MACHINE_NAME=${MACHINE_NAME}
  DISTRO=${DISTRO}
  ARCH=${ARCH}
EOF
}

require_orb() {
    command -v "$ORB_BIN" >/dev/null 2>&1 || {
        printf '[ERROR] OrbStack CLI not found: %s\n' "$ORB_BIN" >&2
        exit 1
    }
}

validate_config() {
    [[ "$MACHINE_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
        printf '[ERROR] unsafe machine name: %s\n' "$MACHINE_NAME" >&2
        exit 1
    }
    [[ "$DISTRO" =~ ^[A-Za-z0-9][A-Za-z0-9._:/-]*$ ]] || {
        printf '[ERROR] unsafe distro identifier: %s\n' "$DISTRO" >&2
        exit 1
    }
    [[ "$ARCH" =~ ^[A-Za-z0-9_-]+$ ]] || {
        printf '[ERROR] unsafe architecture identifier: %s\n' "$ARCH" >&2
        exit 1
    }
    [[ "$VM_AGENT_HOME" =~ ^/[A-Za-z0-9._/-]+$ ]] || {
        printf '[ERROR] unsafe VM agent home: %s\n' "$VM_AGENT_HOME" >&2
        exit 1
    }
}

machine_exists() {
    "$ORB_BIN" list 2>/dev/null \
        | awk '$1 != "NAME" {print $1}' \
        | grep -Fxq "$MACHINE_NAME"
}

create_machine() {
    if machine_exists; then
        printf '[INFO] machine already exists: %s\n' "$MACHINE_NAME"
        return
    fi

    printf '[INFO] creating %s (%s, %s)\n' "$MACHINE_NAME" "$DISTRO" "$ARCH"
    "$ORB_BIN" create --arch "$ARCH" "$DISTRO" "$MACHINE_NAME"
}

start_machine() {
    create_machine
    printf '[INFO] starting machine: %s\n' "$MACHINE_NAME"
    "$ORB_BIN" start "$MACHINE_NAME"
}

run_in_machine() {
    "$ORB_BIN" -m "$MACHINE_NAME" "$@"
}

run_provision() {
    start_machine
    printf '[INFO] provisioning from OrbStack mount: %s\n' "$SCRIPT_DIR"
    run_in_machine sudo bash "$SCRIPT_DIR/provision-orbstack.sh"
}

run_all() {
    start_machine
    printf '[INFO] running all b1-2 scenarios\n'
    run_in_machine sudo -u agent -H env "AGENT_HOME=$VM_AGENT_HOME" \
        bash "$VM_AGENT_HOME/bin/run-all-scenarios.sh"
}

run_verify() {
    start_machine
    printf '[INFO] verifying VM and evidence\n'
    run_in_machine sudo env "AGENT_HOME=$VM_AGENT_HOME" \
        bash "$VM_AGENT_HOME/bin/verify-orbstack.sh"
}

collect_evidence() {
    start_machine
    printf '[INFO] collecting evidence into: %s/evidence\n' "$SCRIPT_DIR"
    run_in_machine sudo tar -C "$VM_AGENT_HOME" -cf - evidence \
        | tar -C "$SCRIPT_DIR" -xf -
}

delete_machine() {
    if ! machine_exists; then
        printf '[INFO] machine does not exist: %s\n' "$MACHINE_NAME"
        return
    fi

    printf '[INFO] deleting machine: %s\n' "$MACHINE_NAME"
    "$ORB_BIN" stop "$MACHINE_NAME" >/dev/null 2>&1 || true
    if "$ORB_BIN" delete --help 2>&1 | grep -Eq -- '(^|[[:space:]])(-f|--force)([[:space:],]|$)'; then
        "$ORB_BIN" delete --force "$MACHINE_NAME" 2>/dev/null \
            || "$ORB_BIN" delete -f "$MACHINE_NAME"
    else
        printf 'y\n' | "$ORB_BIN" delete "$MACHINE_NAME"
    fi
}

open_shell() {
    start_machine
    printf '[INFO] opening shell: %s\n' "$MACHINE_NAME"
    exec "$ORB_BIN" -m "$MACHINE_NAME"
}

demo() {
    run_provision
    run_all
    run_verify
    collect_evidence
}

main() {
    case "$ACTION" in
        -h|--help|help)
            usage
            return
            ;;
    esac

    validate_config
    require_orb
    case "$ACTION" in
        up|shell|connect) open_shell ;;
        create) create_machine ;;
        start) start_machine ;;
        provision|bootstrap) run_provision ;;
        run-all|run) run_all ;;
        verify) run_verify ;;
        collect) collect_evidence ;;
        demo) demo ;;
        reset-demo)
            delete_machine
            create_machine
            demo
            ;;
        stop) "$ORB_BIN" stop "$MACHINE_NAME" ;;
        delete) delete_machine ;;
        list) "$ORB_BIN" list ;;
        *)
            printf '[ERROR] unknown action: %s\n' "$ACTION" >&2
            usage >&2
            exit 1
            ;;
    esac
}

main "$@"
