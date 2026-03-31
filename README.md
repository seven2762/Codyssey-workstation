# E1-1 과제 체크리스트 및 테스트 로그

## 1. 실행 환경

- OS: MacOS Taheo 26.3
- Shell: bash
- Docker: 26.0.1
- Git: 2.43.0

## 2. 수행 체크리스트

- [x] 터미널 기본 조작 및 폴더 구성
- [x] 권한 변경 실습
- [x] Docker 설치/점검
- [x] hello-world 실행
- [x] Dockerfile 빌드/실행
- [x] 포트 매핑 접속(2회)
- [x] 바인드 마운트 반영
- [x] 볼륨 영속성
- [x] Git 설정 + VSCode GitHub 연

## 3. 수행 로그

상세 수행 로그는 아래 하위 문서에서 확인할 수 있다.

| 문서 | 내용 |
|------|------|
| [docs/terminal_logs.md](docs/terminal_logs.md) | 터미널 조작, 권한 실습, Git 설정 로그 |
| [docs/docker_logs.md](docs/docker_logs.md) | Docker 설치 점검, 운영 명령, Dockerfile, 바인드 마운트, 볼륨 로그 |

## 4. 트러블슈팅

### 트러블슈팅 1: 컨테이너 실행 즉시 종료

- **문제**: `docker run` 실행 후 `docker ps`에 컨테이너가 안 보임. `docker ps -a`에서 `Exited (0)` 확인.
- **원인 **: Dockerfile CMD에서 `daemon off` 없이 Nginx를 실행하면 백그라운드로 전환되어 Docker가 포그라운드 프로세스 없음으로 판단, 컨테이너 종료.
- **확인**: `docker logs webserver` — 에러 없이 종료됨.
- **해결**: `CMD ["nginx", "-g", "daemon off;"]`로 수정 후 재빌드.

### 트러블슈팅 2: (직접 겪은 문제 기록)

- **문제**:
- **원인 가설**:
- **확인**:
- **해결/대안**:
