#!/bin/bash
set -euo pipefail

# Clone/update this repository inside an OrbStack Ubuntu machine, then run b1-1 provisioning.

REPO_URL="${REPO_URL:-https://github.com/seven2762/Codyssey-workstation.git}"
BRANCH="${BRANCH:-b1-1}"
TARGET_DIR="${TARGET_DIR:-${HOME}/Codyssey-workstation}"

log() {
    echo "[INFO] $*"
}

run_as_root() {
    if [ "${EUID}" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

ensure_git() {
    if command -v git >/dev/null 2>&1; then
        return
    fi

    log "git이 없어 설치합니다..."
    run_as_root apt-get update
    run_as_root apt-get install -y git ca-certificates
}

clone_or_update_repo() {
    if [ -d "${TARGET_DIR}/.git" ]; then
        log "기존 저장소 업데이트 중: ${TARGET_DIR}"
        git -C "${TARGET_DIR}" fetch origin "${BRANCH}"
        if git -C "${TARGET_DIR}" show-ref --verify --quiet "refs/heads/${BRANCH}"; then
            git -C "${TARGET_DIR}" checkout "${BRANCH}"
        else
            git -C "${TARGET_DIR}" checkout -b "${BRANCH}" "origin/${BRANCH}"
        fi
        git -C "${TARGET_DIR}" pull --ff-only origin "${BRANCH}"
        return
    fi

    if [ -e "${TARGET_DIR}" ]; then
        echo "[ERROR] TARGET_DIR가 이미 존재하지만 git 저장소가 아닙니다: ${TARGET_DIR}" >&2
        echo "        다른 경로를 쓰려면 TARGET_DIR=/path ./bootstrap-orbstack.sh 형태로 실행하세요." >&2
        exit 1
    fi

    log "저장소 clone 중: ${REPO_URL} (${BRANCH})"
    git clone --branch "${BRANCH}" "${REPO_URL}" "${TARGET_DIR}"
}

run_provision() {
    local provision_script="${TARGET_DIR}/b1-1/provision-orbstack.sh"
    if [ ! -x "${provision_script}" ]; then
        echo "[ERROR] 실행 가능한 provision 스크립트를 찾지 못했습니다: ${provision_script}" >&2
        exit 1
    fi

    log "OrbStack VM 프로비저닝 실행 중..."
    cd "${TARGET_DIR}/b1-1"
    run_as_root ./provision-orbstack.sh
}

main() {
    ensure_git
    clone_or_update_repo
    run_provision
}

main "$@"
