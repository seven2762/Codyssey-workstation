#!/bin/bash
set -euo pipefail

# Manage the OrbStack Linux machine used by this mission.
# Default action: create/start b1-agent, then open a shell in it.

MACHINE_NAME="${MACHINE_NAME:-b1-agent}"
DISTRO="${DISTRO:-ubuntu:noble}"
ARCH="${ARCH:-amd64}"
ACTION="${1:-up}"

usage() {
    cat <<EOF
Usage: ./orbstack-machine.sh [up|create|start|shell|stop|delete|list]

Environment overrides:
  MACHINE_NAME=${MACHINE_NAME}
  DISTRO=${DISTRO}
  ARCH=${ARCH}

Examples:
  ./orbstack-machine.sh
  ./orbstack-machine.sh up
  ./orbstack-machine.sh shell
  MACHINE_NAME=b1-agent ./orbstack-machine.sh start
EOF
}

require_orb() {
    if ! command -v orb >/dev/null 2>&1; then
        echo "[ERROR] orb 명령을 찾을 수 없습니다. OrbStack이 설치된 macOS 호스트에서 실행하세요." >&2
        exit 1
    fi
}

machine_exists() {
    orb list 2>/dev/null | awk '$1 != "NAME" {print $1}' | grep -Fxq "${MACHINE_NAME}"
}

create_machine() {
    if machine_exists; then
        echo "[INFO] OrbStack machine already exists: ${MACHINE_NAME}"
        return
    fi

    echo "[INFO] Creating OrbStack machine: ${MACHINE_NAME} (${DISTRO}, ${ARCH})"
    orb create --arch "${ARCH}" "${DISTRO}" "${MACHINE_NAME}"
}

start_machine() {
    create_machine
    echo "[INFO] Starting OrbStack machine: ${MACHINE_NAME}"
    orb start "${MACHINE_NAME}"
}

open_shell() {
    echo "[INFO] Opening shell: ${MACHINE_NAME}"
    exec orb -m "${MACHINE_NAME}"
}

main() {
    require_orb

    case "${ACTION}" in
        up)
            start_machine
            open_shell
            ;;
        create)
            create_machine
            ;;
        start)
            start_machine
            ;;
        shell|connect)
            create_machine
            open_shell
            ;;
        stop)
            orb stop "${MACHINE_NAME}"
            ;;
        delete)
            orb delete "${MACHINE_NAME}"
            ;;
        list)
            orb list
            ;;
        -h|--help|help)
            usage
            ;;
        *)
            echo "[ERROR] Unknown action: ${ACTION}" >&2
            usage >&2
            exit 1
            ;;
    esac
}

main "$@"
