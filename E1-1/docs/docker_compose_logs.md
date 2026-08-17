# Docker Compose 로그

## 1. Docker Compose 기초

### docker-compose.yml 기본 구조

아까 만든 Nginx 웹 서버를 Compose로 실행한다. `docker-compose.yml` 파일을 프로젝트 루트에 생성한다.

```yaml
# docker-compose.yml
version: '3.8'
services:
  web:
    build: .
    ports:
      - "8080:80"
```

> `docker run -d -p 8080:80 my-webserver`와 동일한 동작을 yml 파일로 문서화한 것이다.
> 매번 긴 명령어를 칠 필요 없이 `docker compose up` 한 줄로 실행할 수 있다.

### 단일 서비스 Compose 실행

```bash
# Compose로 실행
$ docker compose up -d
# 
 ✔ Container dev-workstation-web-1  Started

# 상태 확인
$ docker compose ps
# NAME                    IMAGE                 COMMAND                   SERVICE   CREATED          STATUS          PORTS
dev-workstation-web-1   dev-workstation-web   "/docker-entrypoint.…"   web       33 seconds ago   Up 32 seconds   0.0.0.0:8082->80/tcp, [::]:8082->80/tcp

# 접속 확인
$ curl http://localhost:8082
# <h1>바인드 마운트 수정 테스트</h1>

# 종료
$ docker compose down
#  ✔ Container dev-workstation-web-1  Removed                                                      0.2s
 ✔ Network dev-workstation_default  Removed
```

---

## 2. Docker Compose 멀티 컨테이너

웹 서버(Nginx) + 보조 서비스(Redis)를 함께 실행하고, 컨테이너 간 네트워크 통신을 확인한다.

### docker-compose.yml 수정

```yaml
# docker-compose.yml
version: '3.8'
services:
  web:
    build: .
    ports:
      - "8080:80"
    depends_on:
      - redis

  redis:
    image: redis:alpine
    ports:
      - "6379:6379"
```

> `depends_on`은 web 서비스가 redis 서비스에 의존한다는 것을 명시한다.
> Compose는 같은 네트워크를 자동 생성하여 서비스 이름으로 통신할 수 있다.

### 멀티 컨테이너 실행

```bash
# 실행
$ docker compose up -d
# [+] Running 8/8
 ✔ redis Pulled                                                                                  6.2s
   ✔ d8ad8cd72600 Already exists                                                                 0.0s
   ✔ 23f9dd1197f4 Pull complete                                                                  1.0s
   ✔ a00a8d76fa16 Pull complete                                                                  1.1s
   ✔ 7747c4bb2680 Pull complete                                                                  1.8s
   ✔ 81f4f35ddaa6 Pull complete                                                                  2.0s
   ✔ 4f4fb700ef54 Pull complete                                                                  2.0s
   ✔ 1fb7b7102933 Pull complete                                                                  2.4s
[+] Running 3/3
 ✔ Network dev-workstation_default    Created                                                    0.0s
 ✔ Container dev-workstation-redis-1  Started                                                    0.3s
 ✔ Container dev-workstation-web-1    Started

# 2개 서비스 모두 실행 확인
$ docker compose ps
# NAME                      IMAGE                 COMMAND                   SERVICE   CREATED          STATUS          PORTS
dev-workstation-redis-1   redis:alpine          "docker-entrypoint.s…"   redis     21 seconds ago   Up 20 seconds   0.0.0.0:6379->6379/tcp, [::]:6379->6379/tcp
dev-workstation-web-1     dev-workstation-web   "/docker-entrypoint.…"   web       20 seconds ago   Up 20 seconds   0.0.0.0:8082->80/tcp, [::]:8082->80/tcp
```


## 3. Compose 운영 명령어 습득

### 상태 확인 루틴

```bash
# 실행
$ docker compose up -d
# (출력 결과 붙여넣기)

# 상태 확인
$ docker compose ps
# (출력 결과 붙여넣기)

# 전체 로그 확인
$ docker compose logs
# web-1  | /docker-entrypoint.sh: /docker-entrypoint.d/ is not empty, will attempt to perform configuration
web-1  | /docker-entrypoint.sh: Looking for shell scripts in /docker-entrypoint.d/
web-1  | /docker-entrypoint.sh: Launching /docker-entrypoint.d/10-listen-on-ipv6-by-default.sh
web-1  | 10-listen-on-ipv6-by-default.sh: info: Getting the checksum of /etc/nginx/conf.d/default.conf
web-1  | 10-listen-on-ipv6-by-default.sh: info: Enabled listen on IPv6 in /etc/nginx/conf.d/default.conf
web-1  | /docker-entrypoint.sh: Sourcing /docker-entrypoint.d/15-local-resolvers.envsh
web-1  | /docker-entrypoint.sh: Launching /docker-entrypoint.d/20-envsubst-on-templates.sh
web-1  | /docker-entrypoint.sh: Launching /docker-entrypoint.d/30-tune-worker-processes.sh
web-1  | /docker-entrypoint.sh: Configuration complete; ready for start up
web-1  | 2026/03/31 20:35:22 [notice] 1#1: using the "epoll" event method
web-1  | 2026/03/31 20:35:22 [notice] 1#1: nginx/1.29.7
web-1  | 2026/03/31 20:35:22 [notice] 1#1: built by gcc 15.2.0 (Alpine 15.2.0)
web-1  | 2026/03/31 20:35:22 [notice] 1#1: OS: Linux 6.17.8-orbstack-00308-g8f9c941121b1
web-1  | 2026/03/31 20:35:22 [notice] 1#1: getrlimit(RLIMIT_NOFILE): 20480:1048576
web-1  | 2026/03/31 20:35:22 [notice] 1#1: start worker processes
web-1  | 2026/03/31 20:35:22 [notice] 1#1: start worker process 30
web-1  | 2026/03/31 20:35:22 [notice] 1#1: start worker process 31
web-1  | 2026/03/31 20:35:22 [notice] 1#1: start worker process 32
web-1  | 2026/03/31 20:35:22 [notice] 1#1: start worker process 33
web-1  | 2026/03/31 20:35:22 [notice] 1#1: start worker process 34
web-1  | 2026/03/31 20:35:22 [notice] 1#1: start worker process 35
web-1  | 2026/03/31 20:35:22 [notice] 1#1: start worker process 36
web-1  | 2026/03/31 20:35:22 [notice] 1#1: start worker process 37
redis-1  | Starting Redis Server
redis-1  | 1:C 31 Mar 2026 20:35:22.188 * oO0OoO0OoO0Oo Redis is starting oO0OoO0OoO0Oo
redis-1  | 1:C 31 Mar 2026 20:35:22.188 * Redis version=8.6.2, bits=64, commit=00000000, modified=1, pid=1, just started
redis-1  | 1:C 31 Mar 2026 20:35:22.188 * Configuration loaded
redis-1  | 1:M 31 Mar 2026 20:35:22.189 * monotonic clock: ARM CNTVCT @ 24 ticks/us
redis-1  | 1:M 31 Mar 2026 20:35:22.190 * Running mode=standalone, port=6379.
redis-1  | 1:M 31 Mar 2026 20:35:22.191 * <bf> RedisBloom version 8.6.0 (Git=unknown)
redis-1  | 1:M 31 Mar 2026 20:35:22.191 * <bf> Registering configuration options: [
redis-1  | 1:M 31 Mar 2026 20:35:22.191 * <bf>     { bf-error-rate       :      0.01 }
redis-1  | 1:M 31 Mar 2026 20:35:22.191 * <bf>     { bf-initial-size     :       100 }
redis-1  | 1:M 31 Mar 2026 20:35:22.191 * <bf>     { bf-expansion-factor :         2 }
redis-1  | 1:M 31 Mar 2026 20:35:22.191 * <bf>     { cf-bucket-size      :         2 }
redis-1  | 1:M 31 Mar 2026 20:35:22.191 * <bf>     { cf-initial-size     :      1024 }
redis-1  | 1:M 31 Mar 2026 20:35:22.191 * <bf>     { cf-max-iterations   :        20 }
redis-1  | 1:M 31 Mar 2026 20:35:22.191 * <bf>     { cf-expansion-factor :         1 }
redis-1  | 1:M 31 Mar 2026 20:35:22.191 * <bf>     { cf-max-expansions   :        32 }
redis-1  | 1:M 31 Mar 2026 20:35:22.191 * <bf> ]
redis-1  | 1:M 31 Mar 2026 20:35:22.191 * Module 'bf' loaded from /usr/local/lib/redis/modules//redisbloom.so


### 명령어 정리

| 명령어 | 설명 |
|--------|------|
| `docker compose up -d` | 백그라운드로 서비스 실행 |
| `docker compose down` | 서비스 종료 및 컨테이너 삭제 |
| `docker compose ps` | 실행 중인 서비스 상태 확인 |
| `docker compose logs` | 전체 서비스 로그 확인 |
| `docker compose logs [서비스명]` | 특정 서비스 로그 확인 |
| `docker compose exec [서비스명] [명령]` | 실행 중인 서비스에 명령 실행 |

---

## 4. 환경 변수 활용

Dockerfile 또는 Compose에서 환경 변수를 주입하여 서버 포트/모드를 바꿔본다.

### .env 파일 생성

```bash
$ cat > .env << 'EOF'
HOST_PORT=9090
CONTAINER_PORT=80
EOF
```

### docker-compose.yml에서 환경 변수 사용

```yaml
# docker-compose.yml
version: '3.8'
services:
  web:
    build: .
    ports:
      - "${HOST_PORT}:${CONTAINER_PORT}"
    environment:
      - APP_MODE=production

  redis:
    image: redis:alpine
    ports:
      - "6379:6379"
```

> `.env` 파일에 값을 분리하면, 코드를 수정하지 않고 설정만 바꿔서 다른 환경(개발/운영)에 대응할 수 있다.
> 이것이 **설정과 코드의 분리** 원칙이다.
```

### 환경 변수 적용 확인

```bash

# 실행
$ docker compose up -d
# (출력 결과 붙여넣기)

# 포트가 9090으로 바뀌었는지 확인
$ docker compose ps
# dev-workstation-web-1     dev-workstation-web   "/docker-entrypoint.…"   web       8 seconds ago   Up 7 seconds   0.0.0.0:9090->80/tcp, [::]:9090->80/tcp

```


