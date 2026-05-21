# 주의: agent-app은 x86_64 ELF 바이너리입니다.
# 빌드 및 실행 시 반드시 --platform linux/amd64 를 명시하세요.
# 예) docker build --platform linux/amd64 -t agent-app .
#     docker run  --platform linux/amd64 --cap-add NET_ADMIN --cap-add NET_RAW -d ...
#
# Ubuntu 22.04 → 24.04 변경 이유:
#   바이너리가 GLIBC_2.38 을 요구하는데 22.04는 2.35까지만 제공.
#   24.04는 GLIBC 2.39 포함으로 호환됨.
FROM ubuntu:24.04

# ── 필수 패키지 설치 ──────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y \
    sudo \
    acl \
    ufw \
    iptables \
    iproute2 \
    procps \
    cron \
    bc \
    vim \
    openssh-server \
    && rm -rf /var/lib/apt/lists/*

# ── SSH 설정 ──────────────────────────────────────────────────────────────
RUN mkdir -p /var/run/sshd && \
    sed -i 's/#Port 22/Port 20022/' /etc/ssh/sshd_config && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config && \
    echo "PermitRootLogin no" >> /etc/ssh/sshd_config

# ── 환경 변수 ─────────────────────────────────────────────────────────────
# AGENT_KEY_PATH는 "key" 단어로 인해 Docker 보안 경고가 발생하므로
# entrypoint.sh 에서 설정합니다.
ENV AGENT_HOME=/home/agent-admin/agent-app \
    AGENT_PORT=15034 \
    AGENT_UPLOAD_DIR=/home/agent-admin/agent-app/upload_files \
    AGENT_LOG_DIR=/var/log/agent-app

# ── 그룹 생성 ─────────────────────────────────────────────────────────────
RUN groupadd agent-common && groupadd agent-core

# ── 계정 생성 ─────────────────────────────────────────────────────────────
RUN useradd -m -s /bin/bash agent-admin && \
    useradd -m -s /bin/bash agent-dev   && \
    useradd -m -s /bin/bash agent-test

# ── 그룹 멤버 등록 ────────────────────────────────────────────────────────
# agent-common: admin, dev, test
RUN usermod -aG agent-common agent-admin && \
    usermod -aG agent-common agent-dev   && \
    usermod -aG agent-common agent-test
# agent-core: admin, dev
RUN usermod -aG agent-core agent-admin && \
    usermod -aG agent-core agent-dev

# ── 디렉토리 생성 ─────────────────────────────────────────────────────────
RUN mkdir -p /home/agent-admin/agent-app/upload_files \
             /home/agent-admin/agent-app/api_keys \
             /home/agent-admin/agent-app/bin \
             /var/log/agent-app

# ── 키 파일 생성 ──────────────────────────────────────────────────────────
RUN echo 'agent_api_key_test' > /home/agent-admin/agent-app/api_keys/t_secret.key

# ── app 바이너리 복사 및 실행 권한 부여 ──────────────────────────────────
COPY agent-app /home/agent-admin/agent-app/agent-app
RUN chmod +x /home/agent-admin/agent-app/agent-app

# ── monitor.sh 복사 ───────────────────────────────────────────────────────
COPY monitor.sh /home/agent-admin/agent-app/bin/monitor.sh

# ── 소유권 및 권한 설정 ───────────────────────────────────────────────────
RUN chown -R agent-admin:agent-admin /home/agent-admin/agent-app

# upload_files: agent-common R/W
RUN chown agent-admin:agent-common /home/agent-admin/agent-app/upload_files && \
    chmod 770 /home/agent-admin/agent-app/upload_files

# api_keys: agent-core ONLY
RUN chown agent-admin:agent-core /home/agent-admin/agent-app/api_keys && \
    chmod 770 /home/agent-admin/agent-app/api_keys && \
    chmod o-rwx /home/agent-admin/agent-app/api_keys && \
    chmod 640 /home/agent-admin/agent-app/api_keys/t_secret.key

# /var/log/agent-app: agent-core ONLY
RUN chown agent-admin:agent-core /var/log/agent-app && \
    chmod 770 /var/log/agent-app && \
    chmod o-rwx /var/log/agent-app

# monitor.sh: agent-dev 소유, agent-core 그룹, 750
RUN chown agent-dev:agent-core /home/agent-admin/agent-app/bin/monitor.sh && \
    chmod 750 /home/agent-admin/agent-app/bin/monitor.sh

# ── ACL 설정 ──────────────────────────────────────────────────────────────
RUN setfacl -m g:agent-common:rwx /home/agent-admin/agent-app/upload_files && \
    setfacl -d -m g:agent-common:rwx /home/agent-admin/agent-app/upload_files && \
    setfacl -m g:agent-core:rwx /home/agent-admin/agent-app/api_keys && \
    setfacl -d -m g:agent-core:rwx /home/agent-admin/agent-app/api_keys && \
    setfacl -m g:agent-core:rwx /var/log/agent-app && \
    setfacl -d -m g:agent-core:rwx /var/log/agent-app

# ── crontab 등록 (agent-admin, 매분 monitor.sh 실행) ─────────────────────
RUN echo '* * * * * /bin/bash /home/agent-admin/agent-app/bin/monitor.sh >> /var/log/agent-app/cron.log 2>&1' \
    | crontab -u agent-admin -

# ── 포트 노출 ─────────────────────────────────────────────────────────────
EXPOSE 15034
EXPOSE 20022

# ── 엔트리포인트 ──────────────────────────────────────────────────────────
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]