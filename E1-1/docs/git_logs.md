# Git 설정 및 GitHub 연동 로그

## 1. Git 사용자 정보 및 기본 브랜치 설정

```bash
$ git config --global user.name "본인이름"
$ git config --global user.email "본인이메일@example.com"
$ git config --global init.defaultBranch main
```

### 설정 확인

```bash
$ git config --list
# user.name=seven2762
user.email=seven2762@gmail.com
core.autocrlf=input
init.defaultbranch=main
core.repositoryformatversion=0
core.filemode=true
core.bare=false
core.logallrefupdates=true
core.ignorecase=true
core.precomposeunicode=true
remote.origin.url=git@github.com:seven2762/Codyssey.git
remote.origin.fetch=+refs/heads/*:refs/remotes/origin/*
branch.main.remote=origin
branch.main.merge=refs/heads/main
```

## 2. Git 저장소 초기화 및 GitHub 연동

```bash
$ git init
# /Users/ihyeonmin/Desktop/dev-workstation/.git/ 안의 기존 깃 저장소를 다시 초기화했습니다
$ git add .
$ git commit -m "개발 워크스테이션 구축 과제"
# 현재 브랜치 main
브랜치가 'origin/main'에 맞게 업데이트된 상태입니다.

커밋할 사항 없음, 작업 폴더 깨끗함


$ git remote add origin https://github.com/seven2762/Codyssey.git
$ git branch -M main
$ git push -u origin main
# error: origin 리모트가 이미 있습니다. (이미 그 전에 연결 해 있었음)
```

## 3. SSH 키 설정

### 3-1. SSH 키 생성

```bash
$ ssh-keygen -t ed25519 -C "본인이메일@example.com"
# Enter file in which to save the key (/Users/사용자/.ssh/id_ed25519): (엔터)
# Enter passphrase: (엔터 또는 비밀번호 입력)

```

### 3-2. SSH 키 확인

```bash
$ ls -la ~/.ssh/
# id_ed25519      → 개인 키 (절대 공개 금지)
# id_ed25519.pub  → 공개 키 (GitHub에 등록할 키)
```

### 3-3. 공개 키 복사

```bash
$ cat ~/.ssh/id_ed25519.pub
# (출력 결과 — 이 내용을 GitHub에 등록)
# 예: ssh-ed25519 AAAA...생략...xxxx 본인이메일@example.com
```

### 3-4. GitHub에 SSH 키 등록

1. GitHub 접속 → 우측 상단 프로필 → **Settings**
2. 좌측 메뉴 **SSH and GPG keys** 클릭
3. **New SSH key** 클릭
4. Title: 본인이 알아볼 수 있는 이름 (예: "MacBook")
5. Key: 위에서 복사한 공개 키 붙여넣기
6. **Add SSH key** 클릭

> GitHub SSH 키 등록 스크린샷:
> ![SSH 키 등록](../images/github-ssh-key.png)

### 3-5. SSH 연결 테스트

```bash
$ ssh -T git@github.com
# Hi seven2762! You've successfully authenticated, but GitHub does not provide shell access.
```

위 메시지가 출력되면 SSH 인증 성공이다.

## 4. Remote URL을 HTTPS → SSH로 변경

```bash
# 현재 remote 확인 (HTTPS)
$ git remote -v
# origin  https://github.com/본인계정/저장소명.git (fetch)
# origin  https://github.com/본인계정/저장소명.git (push)

# SSH 방식으로 변경
$ git remote set-url origin git@github.com:본인계정/저장소명.git

# 변경 확인
$ git remote -v
# origin  git@github.com:본인계정/저장소명.git (fetch)
# origin  git@github.com:본인계정/저장소명.git (push)
```

## 5. SSH 방식으로 push 동작 확인

```bash
$ git add .
$ git commit -m "SSH 연동 테스트"
$ git push origin main
# 오브젝트 나열하는 중: 6, 완료.
오브젝트 개수 세는 중: 100% (6/6), 완료.
Delta compression using up to 8 threads
오브젝트 압축하는 중: 100% (4/4), 완료.
오브젝트 쓰는 중: 100% (4/4), 68.59 KiB | 22.86 MiB/s, 완료.
Total 4 (delta 1), reused 0 (delta 0), pack-reused 0
remote: Resolving deltas: 100% (1/1), completed with 1 local object.
To github.com:seven2762/Codyssey.git
   d7f7f48..5df97c3  main -> main
```

