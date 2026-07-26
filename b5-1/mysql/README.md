# b5-1 · 도서 관리 DB — MySQL 버전 (Docker)

SQLite 원본(`b5-1/`)을 **MySQL 8**로 이식한 버전이다. 스키마·데이터·쿼리는
동일하고, DB 고유 문법만 MySQL에 맞게 바꿨다(각 파일 주석에 `[MySQL]` 표시).

- `schema.sql` : 테이블 5개 (InnoDB, utf8mb4, PK/FK/제약)
- `data.sql`   : 샘플 데이터 (각 테이블 10행 이상)
- `queries.sql`: 핵심 쿼리 20개
- 요구: **MySQL 8.0.16+** (CHECK 제약 강제)

## Docker로 실행 (인텔맥 등)

```bash
# 1) MySQL 8 컨테이너 실행
docker run --name b5-mysql \
  -e MYSQL_ROOT_PASSWORD=rootpw \
  -p 3306:3306 -d mysql:8

# (컨테이너가 준비될 때까지 몇 초 대기)

# 2) 스키마 -> 데이터 -> 쿼리 순서로 적재/실행
docker exec -i b5-mysql mysql -uroot -prootpw < schema.sql
docker exec -i b5-mysql mysql -uroot -prootpw library < data.sql
docker exec -i b5-mysql mysql -uroot -prootpw library < queries.sql

# 3) 접속해서 직접 조회
docker exec -it b5-mysql mysql -uroot -prootpw library
```

> `schema.sql`이 `CREATE DATABASE library`와 `USE library`를 포함하므로,
> data/queries는 `library` DB를 지정해 실행한다.

## 실행 결과를 텍스트로 캡처

`mysql`의 `-t`(표 형태) + `-v`(실행 SQL 함께 출력)로 SQLite 결과 캡처와 유사하게 남길 수 있다.

```bash
docker exec -i b5-mysql mysql -t -v -uroot -prootpw library \
  < queries.sql > results.txt
```

## 접속 (CLI)

```bash
# 컨테이너 내부 mysql 로 접속
docker exec -it b5-mysql mysql -uroot -prootpw library

# 호스트에 mysql 클라이언트가 있으면 TCP 로도 가능
mysql -h 127.0.0.1 -P 3306 -uroot -prootpw library
```

접속 후:
```sql
SHOW TABLES;
DESCRIBE book;         -- 테이블 구조
SELECT * FROM member LIMIT 5;
SOURCE queries.sql;    -- 파일 실행 (mysql 내부 명령)
```

## 정리 후

```bash
docker stop b5-mysql && docker rm b5-mysql   # 컨테이너 제거
```

## SQLite → MySQL 이식 포인트

| 항목 | SQLite | MySQL |
| --- | --- | --- |
| 자동증가 PK | `INTEGER PRIMARY KEY AUTOINCREMENT` | `INT AUTO_INCREMENT PRIMARY KEY` |
| FK 강제 | `PRAGMA foreign_keys=ON` | InnoDB 기본 강제 (불필요) |
| 문자 타입 | `TEXT` | `VARCHAR(n)` |
| 한글 | 자동 | `CHARACTER SET utf8mb4` |
| 연체일수 | `julianday(a)-julianday(b)` | `DATEDIFF(a, b)` |
| 오늘 | `date('now')` | `CURDATE()` |
| 파생테이블 | 별칭 생략 가능 | **별칭 필수** `(...) AS sub` |
| 인덱스 | `CREATE INDEX IF NOT EXISTS` | `CREATE INDEX` (IF NOT EXISTS 미지원) |
| 인덱스 조회 | `sqlite_master` | `SHOW INDEX FROM ...` |
| FK 위반 | `FOREIGN KEY constraint failed` | `Cannot add or update a child row: a foreign key constraint fails` |

> 이 폴더의 파일은 이 저장소 환경에서 실행하지 않고(MySQL 서버 미실행),
> 인텔맥 Docker 환경에서 실행/결과 캡처하는 것을 전제로 작성했다.
