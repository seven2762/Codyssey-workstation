#!/bin/bash
set -euo pipefail

# Manage the OrbStack Linux machine used by this mission.
# Default action: create/start b1-agent, then open a shell in it.

MACHINE_NAME="${MACHINE_NAME:-b1-agent}"
DISTRO="${DISTRO:-ubuntu:noble}"
ARCH="${ARCH:-amd64}"
ACTION="${1:-up}"
# 이 스크립트가 있는 b1-1 디렉토리(맥 경로). OrbStack이 맥 파일시스템을 VM 안에
# 동일 경로로 마운트하므로, VM에서도 이 경로의 provision을 바로 실행할 수 있다
# (git clone/네트워크 불필요, 항상 로컬 최신 코드 사용).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat <<EOF
Usage: ${0} [up|create|start|shell|provision|reset-demo|stop|delete|list]

Environment overrides:
  MACHINE_NAME=${MACHINE_NAME}
  DISTRO=${DISTRO}
  ARCH=${ARCH}

Examples:
  ${0}
  ${0} up
  ${0} provision
  ${0} reset-demo
  ${0} shell
  MACHINE_NAME=b1-agent ${0} start
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

delete_machine() {
    if ! machine_exists; then
        echo "[INFO] OrbStack machine does not exist: ${MACHINE_NAME}"
        return
    fi

    echo "[INFO] Deleting OrbStack machine: ${MACHINE_NAME}"
    orb stop "${MACHINE_NAME}" >/dev/null 2>&1 || true
    if orb delete --help 2>&1 | grep -Eq -- '(^|[[:space:]])(-f|--force)([[:space:],]|$)'; then
        orb delete --force "${MACHINE_NAME}" 2>/dev/null || orb delete -f "${MACHINE_NAME}"
    else
        printf 'y\n' | orb delete "${MACHINE_NAME}"
    fi
}

run_provision() {
    start_machine
    echo "[INFO] Running provision inside ${MACHINE_NAME} from mount: ${SCRIPT_DIR}"
    local quoted_dir
    printf -v quoted_dir '%q' "${SCRIPT_DIR}"

    # OrbStack 마운트로 VM에서 동일 경로가 보이므로 provision을 직접 실행한다.
    # provision-orbstack.sh가 패키지 설치까지 스스로 처리하므로 curl/git 불필요.
    orb -m "${MACHINE_NAME}" bash -lc "sudo bash ${quoted_dir}/provision-orbstack.sh"
}

reset_demo() {
    delete_machine
    create_machine
    run_provision
    open_shell
}

run_default() {
    if ! machine_exists; then
        echo "[INFO] OrbStack machine is missing; running reset-demo flow."
        reset_demo
        return
    fi

    start_machine
    open_shell
}

open_shell() {
    echo "[INFO] Opening shell: ${MACHINE_NAME}"
    exec orb -m "${MACHINE_NAME}"
}

main() {
    require_orb

    case "${ACTION}" in
        up)
            run_default
            ;;
        create)
            create_machine
            ;;
        start)
            start_machine
            ;;
        provision|bootstrap)
            run_provision
            ;;
        reset-demo|demo)
            reset_demo
            ;;
        shell|connect)
            start_machine
            open_shell
            ;;
        stop)
            orb stop "${MACHINE_NAME}"
            ;;
        delete)
            delete_machine
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
