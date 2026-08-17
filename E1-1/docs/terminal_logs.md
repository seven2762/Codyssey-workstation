# 터미널 조작 및 권한 실습 로그

## mv 조작 로그

```
seven27629411@c4r1s1 e1-1 % mkdir testdir
seven27629411@c4r1s1 e1-1 % mv e1-1 testdir
seven27629411@c4r1s1 e1-1 % ls     
Dockerfile		app			docs			my-app
README.md		docker-compose.yml	images			testdir
seven27629411@c4r1s1 e1-1 % cd testdir
seven27629411@c4r1s1 testdir % ls
e1-1
```

[터미널 조작 실행 결과 스크린샷](../images/terminal_log_image.png)
## mkdir 
```bash
seven27629411@c4r1s1 e1-1 % mkdir test1
seven27629411@c4r1s1 e1-1 % ls
Dockerfile		docker-compose.yml	test1
README.md		docs
app			images
```
[권한 변경 결과 스크린샷](../images/change_mode.png)



