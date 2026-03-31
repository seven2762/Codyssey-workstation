# Docker 운영 및 검증 로그

## 1. Docker 설치 및 기본 점검

```bash
$ docker --version
# Docker version 26.0.1, build d260a54c81

$ docker info
# Client: Docker Engine - Community
 Version:    26.0.1
 Context:    orbstack
 Debug Mode: false
 Plugins:
  ai: Ask Gordon - Docker Agent (Docker Inc.)
    Version:  v0.5.1
    Path:     /Users/ihyeonmin/.docker/cli-plugins/docker-ai
  buildx: Docker Buildx (Docker Inc.)
    Version:  v0.29.1
    Path:     /Users/ihyeonmin/.docker/cli-plugins/docker-buildx
  compose: Docker Compose (Docker Inc.)
    Version:  v2.40.3
    Path:     /Users/ihyeonmin/.docker/cli-plugins/docker-compose
  debug: Get a shell into any image or container (Docker Inc.)
    Version:  0.0.37
    Path:     /Users/ihyeonmin/.docker/cli-plugins/docker-debug
  desktop: Docker Desktop commands (Beta) (Docker Inc.)
    Version:  v0.1.0
    Path:     /Users/ihyeonmin/.docker/cli-plugins/docker-desktop
  dev: Docker Dev Environments (Docker Inc.)
    Version:  v0.1.2
    Path:     /Users/ihyeonmin/.docker/cli-plugins/docker-dev
  extension: Manages Docker extensions (Docker Inc.)
    Version:  v0.2.27
    Path:     /Users/ihyeonmin/.docker/cli-plugins/docker-extension
  feedback: Provide feedback, right in your terminal! (Docker Inc.)
    Version:  v1.0.5
    Path:     /Users/ihyeonmin/.docker/cli-plugins/docker-feedback
  init: Creates Docker-related starter files for your project (Docker Inc.)
    Version:  v1.4.0
    Path:     /Users/ihyeonmin/.docker/cli-plugins/docker-init
  sbom: View the packaged-based Software Bill Of Materials (SBOM) for an image (Anchore Inc.)
    Version:  0.6.0
    Path:     /Users/ihyeonmin/.docker/cli-plugins/docker-sbom
  scout: Docker Scout (Docker Inc.)
    Version:  v1.15.1
    Path:     /Users/ihyeonmin/.docker/cli-plugins/docker-scout

Server:
 Containers: 1
  Running: 1
  Paused: 0
  Stopped: 0
 Images: 1
 Server Version: 28.5.2
 Storage Driver: overlay2
  Backing Filesystem: btrfs
  Supports d_type: true
  Using metacopy: false
  Native Overlay Diff: true
  userxattr: false
 Logging Driver: json-file
 Cgroup Driver: cgroupfs
 Cgroup Version: 2
 Plugins:
  Volume: local
  Network: bridge host ipvlan macvlan null overlay
  Log: awslogs fluentd gcplogs gelf journald json-file local splunk syslog
 CDI spec directories:
  /etc/cdi
  /var/run/cdi
 Swarm: inactive
 Runtimes: io.containerd.runc.v2 runc
 Default Runtime: runc
 Init Binary: docker-init
 containerd version: 1c4457e00facac03ce1d75f7b6777a7a851e5c41
 runc version: d842d7719497cc3b774fd71620278ac9e17710e0
 init version: de40ad0
 Security Options:
  seccomp
   Profile: builtin
  cgroupns
 Kernel Version: 6.17.8-orbstack-00308-g8f9c941121b1
 Operating System: OrbStack
 OSType: linux
 Architecture: aarch64
 CPUs: 8
 Total Memory: 7.808GiB
 Name: orbstack
 ID: 2b3303bd-c71d-4168-a4ee-879d98c08a5d
 Docker Root Dir: /var/lib/docker
 Debug Mode: false
 Experimental: false
 Insecure Registries:
  ::1/128
  127.0.0.0/8
 Live Restore Enabled: false
 Product License: Community Engine
 Default Address Pools:
   Base: 192.168.97.0/24, Size: 24
   Base: 192.168.107.0/24, Size: 24
   Base: 192.168.117.0/24, Size: 24
   Base: 192.168.147.0/24, Size: 24
   Base: 192.168.148.0/24, Size: 24
   Base: 192.168.155.0/24, Size: 24
   Base: 192.168.156.0/24, Size: 24
   Base: 192.168.158.0/24, Size: 24
   Base: 192.168.163.0/24, Size: 24
   Base: 192.168.164.0/24, Size: 24
   Base: 192.168.165.0/24, Size: 24
   Base: 192.168.166.0/24, Size: 24
   Base: 192.168.167.0/24, Size: 24
   Base: 192.168.171.0/24, Size: 24
   Base: 192.168.172.0/24, Size: 24
   Base: 192.168.181.0/24, Size: 24
   Base: 192.168.183.0/24, Size: 24
   Base: 192.168.186.0/24, Size: 24
   Base: 192.168.207.0/24, Size: 24
   Base: 192.168.214.0/24, Size: 24
   Base: 192.168.215.0/24, Size: 24
   Base: 192.168.216.0/24, Size: 24
   Base: 192.168.223.0/24, Size: 24
   Base: 192.168.227.0/24, Size: 24
   Base: 192.168.228.0/24, Size: 24
   Base: 192.168.229.0/24, Size: 24
   Base: 192.168.237.0/24, Size: 24
   Base: 192.168.239.0/24, Size: 24
   Base: 192.168.242.0/24, Size: 24
   Base: 192.168.247.0/24, Size: 24
   Base: fd07:b51a:cc66:d000::/56, Size: 64

WARNING: DOCKER_INSECURE_NO_IPTABLES_RAW is set
```


## 2. Docker 기본 운영 명령

```bash
$ docker images
# REPOSITORY     TAG       IMAGE ID       CREATED       SIZE
my-webserver   latest    d6b75b3ac68d   2 hours ago   61.6MB
hello-world    latest    eb84fdc6f2a3   7 days ago    5.2kB

$ docker ps -a
# ef41d31f0dc8   hello-world    "/hello"                  6 minutes ago   Exited (0) 6 minutes ago                                           gifted_vaughan
6f31213da32b   my-webserver   "/docker-entrypoint.…"   2 hours ago     Up 2 hours                 0.0.0.0:8080->80/tcp, :::8080->80/tcp   webserver

$ docker logs webserver
# /docker-entrypoint.sh: /docker-entrypoint.d/ is not empty, will attempt to perform configuration
/docker-entrypoint.sh: Looking for shell scripts in /docker-entrypoint.d/
/docker-entrypoint.sh: Launching /docker-entrypoint.d/10-listen-on-ipv6-by-default.sh
10-listen-on-ipv6-by-default.sh: info: Getting the checksum of /etc/nginx/conf.d/default.conf
10-listen-on-ipv6-by-default.sh: info: Enabled listen on IPv6 in /etc/nginx/conf.d/default.conf
/docker-entrypoint.sh: Sourcing /docker-entrypoint.d/15-local-resolvers.envsh
/docker-entrypoint.sh: Launching /docker-entrypoint.d/20-envsubst-on-templates.sh
/docker-entrypoint.sh: Launching /docker-entrypoint.d/30-tune-worker-processes.sh
/docker-entrypoint.sh: Configuration complete; ready for start up
2026/03/31 16:22:55 [notice] 1#1: using the "epoll" event method
2026/03/31 16:22:55 [notice] 1#1: nginx/1.29.7
2026/03/31 16:22:55 [notice] 1#1: built by gcc 15.2.0 (Alpine 15.2.0)
2026/03/31 16:22:55 [notice] 1#1: OS: Linux 6.17.8-orbstack-00308-g8f9c941121b1
2026/03/31 16:22:55 [notice] 1#1: getrlimit(RLIMIT_NOFILE): 20480:1048576
2026/03/31 16:22:55 [notice] 1#1: start worker processes
2026/03/31 16:22:55 [notice] 1#1: start worker process 30
2026/03/31 16:22:55 [notice] 1#1: start worker process 31
2026/03/31 16:22:55 [notice] 1#1: start worker process 32
2026/03/31 16:22:55 [notice] 1#1: start worker process 33
2026/03/31 16:22:55 [notice] 1#1: start worker process 34
2026/03/31 16:22:55 [notice] 1#1: start worker process 35
2026/03/31 16:22:55 [notice] 1#1: start worker process 36
2026/03/31 16:22:55 [notice] 1#1: start worker process 37
192.168.215.1 - - [31/Mar/2026:16:23:06 +0000] "GET / HTTP/1.1" 200 247 "-" "curl/8.7.1" "-"
192.168.215.1 - - [31/Mar/2026:16:23:24 +0000] "GET / HTTP/1.1" 200 247 "-" "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36" "-"
192.168.215.1 - - [31/Mar/2026:16:23:24 +0000] "GET /favicon.ico HTTP/1.1" 404 555 "http://localhost:8080/" "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36" "-"
2026/03/31 16:23:24 [error] 31#31: *2 open() "/usr/share/nginx/html/favicon.ico" failed (2: No such file or directory), client: 192.168.215.1, server: localhost, request: "GET /favicon.ico HTTP/1.1", host: "localhost:8080", referrer: "http://localhost:8080/"

$ docker stats webserver --no-stream
# (CONTAINER ID   NAME        CPU %     MEM USAGE / LIMIT     MEM %     NET I/O           BLOCK I/O        PIDS
6f31213da32b   webserver   0.00%     6.508MiB / 7.808GiB   0.08%     4.59kB / 2.99kB   745kB / 8.19kB   9
```

## 3. 컨테이너 실행 실습
```bash
$ docker run hello-world
# Hello from Docker!
This message shows that your installation appears to be working correctly.

To generate this message, Docker took the following steps:
 1. The Docker client contacted the Docker daemon.
 2. The Docker daemon pulled the "hello-world" image from the Docker Hub.
    (arm64v8)
 3. The Docker daemon created a new container from that image which runs the
    executable that produces the output you are currently reading.
 4. The Docker daemon streamed that output to the Docker client, which sent it
    to your terminal.

To try something more ambitious, you can run an Ubuntu container with:
 $ docker run -it ubuntu bash

Share images, automate workflows, and more with a free Docker ID:
 https://hub.docker.com/

For more examples and ideas, visit:
 https://docs.docker.com/get-started/
 
 $ docker run -it --name my-ubuntu ubuntu:latest

# root@c299f73cd7a1:/# ls
bin  boot  dev  etc  home  lib  media  mnt  opt  proc  root  run  sbin  srv  sys  tmp  usr  var
# root@c299f73cd7a1:/# echo

$ docker attach test2
root@b7dd295bec10:/# exit
exit
$ docker ps
CONTAINER ID   IMAGE          COMMAND                   CREATED       STATUS       PORTS                                   NAMES
6f31213da32b   my-webserver   "/docker-entrypoint.…"   3 hours ago   Up 3 hours   0.0.0.0:8080->80/tcp, :::8080->80/tcp   webserver

테이너 종료/유지: attach vs exec
컨테이너에는 생성 시 지정된 메인 프로세스가 존재한다. 이 메인 프로세스의 종료 여부에 따라 컨테이너의 생존이 결정된다.
attach는 메인 프로세스에 직접 재접속하는 명령이다. exit으로 빠져나오면 메인 프로세스가 종료되므로 컨테이너도 함께 종료된다.
exec는 메인 프로세스와 별개로 새로운 프로세스를 추가 실행하는 명령이다. exit으로 빠져나와도 메인 프로세스는 그대로 유지되므로 컨테이너가 종료되지 않는다.
```


## 4. Dockerfile


```dockerfile
FROM nginx:alpine
COPY app/ /usr/share/nginx/html/
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]

| 명령어 | 커스텀 내용 | 목적 |
|--------|------------|------|
| `COPY app/ /usr/share/nginx/html/` | 직접 작성한 정적 콘텐츠를 Nginx 기본 경로에 복사 | 기본 Welcome 페이지 대신 커스텀 웹페이지 제공 |
| `EXPOSE 80` | 컨테이너의 80번 포트를 외부에 명시 | 웹 서버 접속 포트 문서화 |
| `CMD ["nginx", "-g", "daemon off;"]` | Nginx를 포그라운드 모드로 실행 | 컨테이너가 즉시 종료되지 않도록 유지 |
```

## 5. 이미지 빌드 및 실행

```bash
$ docker build -t my-webserver .
# Building 1.7s (7/7) FINISHED                                                                                                                           docker:orbstack
 => [internal] load build definition from Dockerfile                                                                                                                  0.0s
 => => transferring dockerfile: 133B                                                                                                                                  0.0s
 => [internal] load metadata for docker.io/library/nginx:alpine                                                                                                       1.5s
 => [internal] load .dockerignore                                                                                                                                     0.0s
 => => transferring context: 2B                                                                                                                                       0.0s
 => [internal] load build context                                                                                                                                     0.0s
 => => transferring context: 59B                                                                                                                                      0.0s
 => [1/2] FROM docker.io/library/nginx:alpine@sha256:e7257f1ef28ba17cf7c248cb8ccf6f0c6e0228ab9c315c152f9c203cd34cf6d1                                                 0.0s
 => CACHED [2/2] COPY app/ /usr/share/nginx/html/                                                                                                                     0.0s
 => exporting to image                                                                                                                                                0.0s
 => => exporting layers                                                                                                                                               0.0s
 => => writing image sha256:d6b75b3ac68dcce244a7aa72fa440c0906e4185c28d1f372282799b7053a9b96                                                                          0.0s
 => => naming to docker.io/library/my-webserver                                                                                                                       0.0s

View build details: docker-desktop://dashboard/build/orbstack/orbstack/p1tf73i36bj1elbru1jjz2lel

$ docker images
# REPOSITORY     TAG       IMAGE ID       CREATED       SIZE
my-webserver   latest    d6b75b3ac68d   3 hours ago   61.6MB

$ docker run -d --name webserver -p 8080:80 my-webserver
# 3a2603cdb0cba5c24bee58e1512a6054e13f582ed742bf22e69ed0c09e9d67a0
```
## 6. 포트 매핑 접속 확인

```bash
$ curl http://localhost:8080
# <!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <title>Dev Workstation</title>
</head>
<body>
    <h1>개발 워크스테이션 과제</h1>
    <p>Docker + Nginx 웹 서버가 정상 동작 중입니다.</p>
</body>
</html>
```


## 7. 바인드 마운트
### 실행 명령
```bash
$ docker stop webserver && docker rm webserver

$ docker run -d --name webserver-bind \
  -p 8080:80 \
  -v $(pwd)/app:/usr/share/nginx/html \
  nginx:alpine
# 8bc115989ae900d355db14bbb7612ed580078bc542fa398cacd19a9d90cb9a8c
```

### 변경 전 확인
```bash
$ curl http://localhost:8080
# <!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <title>Dev Workstation</title>
</head>
<body>
    <h1>개발 워크스테이션 과제</h1>
    <p>Docker + Nginx 웹 서버가 정상 동작 중입니다.</p>
</body>
```

### 호스트에서 파일 수정
```bash
$ echo '<h1>바인드 마운트 수정 테스트</h1>' > app/index.html
```

### 변경 후 확인
```bash
$ curl http://localhost:8080
# <h1>바인드 마운트 수정 테스트</h1>
```

## 7. Docker 볼륨 영속성

### 볼륨 생성 및 연결
```bash
$ docker volume create my-data

$ docker run -d --name webserver-vol \
  -p 8081:80 \
  -v my-data:/usr/share/nginx/html \
  nginx:alpine
# 50369e56bccaebc16d13a4499fffa2cdb102f37286d88514c361556178d5d0be

$ docker exec webserver-vol sh -c \
  'echo "<h1>볼륨 영속성 테스트</h1>" > /usr/share/nginx/html/index.html'
```

### 삭제 전 확인
```bash
$ curl http://localhost:8081
# <h1>볼륨 영속성 테스트</h1>
```

### 컨테이너 삭제 후 재연결
```bash
$ docker stop webserver-vol && docker rm webserver-vol

$ docker run -d --name webserver-vol2 \
  -p 8081:80 \
  -v my-data:/usr/share/nginx/html \
  nginx:alpine
# 613ec6d67cfe15e631cf4fff98ab06932a7452853acfbeaa899b932fce2c5c7e
```

### 삭제 후 확인 (데이터 영속성 증명)
```bash
$ curl http://localhost:8081
# <h1>볼륨 영속성 테스트</h1>
```

### 볼륨 상세 정보
```bash
$ docker volume ls
# DRIVER    VOLUME NAME
local     my-data

$ docker volume inspect my-data
# [
    {
        "CreatedAt": "2026-04-01T04:46:40+09:00",
        "Driver": "local",
        "Labels": null,
        "Mountpoint": "/var/lib/docker/volumes/my-data/_data",
        "Name": "my-data",
        "Options": null,
        "Scope": "local"
    }
]
```
