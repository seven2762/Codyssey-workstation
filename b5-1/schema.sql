-- =====================================================================
--  도서 관리 데이터베이스 - 스키마 생성 스크립트
--  DB: SQLite 3
--  실행: sqlite3 library.db < schema.sql
--
--  테이블(5) : category, publisher, member, book, rental
--  1:N 관계(4):
--    category  1 ── N  book     (book.category_id  -> category.id)
--    publisher 1 ── N  book     (book.publisher_id -> publisher.id)
--    member    1 ── N  rental   (rental.member_id  -> member.id)
--    book      1 ── N  rental   (rental.book_id    -> book.id)
-- =====================================================================

-- [SQLite 전용] FK 제약을 실제로 강제하려면 연결마다 아래 PRAGMA가 필요하다.
-- (SQLite는 기본값이 OFF이며, MySQL/PostgreSQL은 항상 FK를 강제한다.)
PRAGMA foreign_keys = ON;

-- 재실행 시 깨끗한 상태에서 시작하도록 자식 -> 부모 순서로 제거한다.
DROP TABLE IF EXISTS rental;
DROP TABLE IF EXISTS book;
DROP TABLE IF EXISTS member;
DROP TABLE IF EXISTS publisher;
DROP TABLE IF EXISTS category;

-- ---------------------------------------------------------------------
-- category : 도서 분류 (부모 테이블)
-- ---------------------------------------------------------------------
CREATE TABLE category (
    id    INTEGER PRIMARY KEY AUTOINCREMENT,           -- PK. [SQLite] AUTOINCREMENT = 자동 증가 키
    name  TEXT    NOT NULL UNIQUE                       -- 분류명. NOT NULL + UNIQUE (중복 분류 금지)
);

-- ---------------------------------------------------------------------
-- publisher : 출판사 (부모 테이블)
-- ---------------------------------------------------------------------
CREATE TABLE publisher (
    id    INTEGER PRIMARY KEY AUTOINCREMENT,
    name  TEXT    NOT NULL UNIQUE,                      -- 출판사명. UNIQUE
    phone TEXT                                          -- 연락처(선택)
);

-- ---------------------------------------------------------------------
-- member : 회원 (부모 테이블)
-- ---------------------------------------------------------------------
CREATE TABLE member (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    name            TEXT NOT NULL,                       -- 이름. NOT NULL
    email           TEXT NOT NULL UNIQUE,                -- 이메일. NOT NULL + UNIQUE (로그인 식별자 가정)
    phone           TEXT,
    membership_type TEXT NOT NULL DEFAULT 'BASIC'        -- 등급. 값 범위를 CHECK로 제한
                      CHECK (membership_type IN ('BASIC', 'PREMIUM')),
    joined_at       DATE NOT NULL                        -- 가입일 (YYYY-MM-DD)
);

-- ---------------------------------------------------------------------
-- book : 도서 (category, publisher 를 참조하는 자식)
-- ---------------------------------------------------------------------
CREATE TABLE book (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    title          TEXT    NOT NULL,                     -- 제목. NOT NULL
    author         TEXT    NOT NULL,                     -- 저자. NOT NULL
    isbn           TEXT    UNIQUE,                        -- ISBN. UNIQUE (중복 도서 방지)
    published_year INTEGER,                               -- 출간 연도
    total_copies   INTEGER NOT NULL DEFAULT 1             -- 보유 권수. 0 이상만 허용
                     CHECK (total_copies >= 0),
    category_id    INTEGER NOT NULL,                      -- FK -> category.id (분류 없는 도서 금지)
    publisher_id   INTEGER,                               -- FK -> publisher.id (미상 허용 위해 NULL 가능)
    FOREIGN KEY (category_id)  REFERENCES category(id),
    FOREIGN KEY (publisher_id) REFERENCES publisher(id)
);

-- ---------------------------------------------------------------------
-- rental : 대여 기록 (member, book 를 참조하는 자식 = 1:N 두 개의 교차점)
-- ---------------------------------------------------------------------
CREATE TABLE rental (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    member_id   INTEGER NOT NULL,                         -- FK -> member.id
    book_id     INTEGER NOT NULL,                         -- FK -> book.id
    rented_at   DATE    NOT NULL,                         -- 대여일
    due_date    DATE    NOT NULL,                         -- 반납 예정일
    returned_at DATE,                                     -- 실제 반납일. NULL 이면 '대여 중'
    FOREIGN KEY (member_id) REFERENCES member(id),
    FOREIGN KEY (book_id)   REFERENCES book(id)
);
