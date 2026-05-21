#!/bin/bash
set -e

echo "======================================"
echo "  Agent App Docker Container 시작"
echo "======================================"

# ── SSH 데몬 시작 ─────────────────────────────────────────────────────────
echo "[INFO] SSH 데몬 시작 중 (포트 20022)..."
service ssh start
echo "[INFO] SSH 시작 완료"

# ── cron 데몬 시작 ────────────────────────────────────────────────────────
echo "[INFO] cron 데몬 시작 중..."
service cron start
echo "[INFO] cron 시작 완료"

# ── UFW 방화벽 설정 ───────────────────────────────────────────────────────
# Docker 컨테이너 환경에서는 iptables-legacy 로 전환해야 UFW가 동작함
echo "[INFO] iptables-legacy 전환 중..."
update-alternatives --set iptables /usr/sbin/iptables-legacy
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy

echo "[INFO] UFW 방화벽 설정 중..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 20022/tcp
ufw allow 15034/tcp
ufw --force enable
echo "[INFO] UFW 설정 완료"

# ── 환경 변수 설정 ────────────────────────────────────────────────────────
# AGENT_KEY_PATH는 Dockerfile ENV에서 제외 (Docker 보안 경고 방지)
AGENT_KEY_PATH="${AGENT_HOME}/api_keys/t_secret.key"

echo "[INFO] AGENT_HOME       = ${AGENT_HOME}"
echo "[INFO] AGENT_PORT       = ${AGENT_PORT}"
echo "[INFO] AGENT_UPLOAD_DIR = ${AGENT_UPLOAD_DIR}"
echo "[INFO] AGENT_KEY_PATH   = ${AGENT_KEY_PATH}"
echo "[INFO] AGENT_LOG_DIR    = ${AGENT_LOG_DIR}"

# ── agent-app 바이너리 실행 (agent-admin 계정으로) ────────────────────────
echo ""
echo "[INFO] agent-app 시작 (agent-admin 계정)..."
echo "--------------------------------------"

exec su -s /bin/bash agent-admin -c "
    export AGENT_HOME=${AGENT_HOME}
    export AGENT_PORT=${AGENT_PORT}
    export AGENT_UPLOAD_DIR=${AGENT_UPLOAD_DIR}
    export AGENT_KEY_PATH=${AGENT_KEY_PATH}
    export AGENT_LOG_DIR=${AGENT_LOG_DIR}
    cd \${AGENT_HOME}
    ./agent-app
"