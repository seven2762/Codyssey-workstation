-- =====================================================================
--  도서 관리 데이터베이스 - 스키마 생성 스크립트 (MySQL 8 버전)
--  실행: mysql -uroot -p < schema.sql
--  요구: MySQL 8.0.16+ (CHECK 제약 강제), 스토리지 엔진 InnoDB
--
--  SQLite 버전과의 주요 차이
--    - AUTOINCREMENT              -> AUTO_INCREMENT
--    - PRAGMA foreign_keys=ON     -> 불필요 (InnoDB가 항상 FK 강제)
--    - TEXT                       -> VARCHAR(n) (길이 지정)
--    - 한글                       -> utf8mb4 문자셋 명시
-- =====================================================================

SET NAMES utf8mb4;

CREATE DATABASE IF NOT EXISTS library
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE library;

-- 재실행 대비: 자식 -> 부모 순서로 제거
DROP TABLE IF EXISTS rental;
DROP TABLE IF EXISTS book;
DROP TABLE IF EXISTS member;
DROP TABLE IF EXISTS publisher;
DROP TABLE IF EXISTS category;

-- ---------------------------------------------------------------------
-- category : 도서 분류 (부모)
-- ---------------------------------------------------------------------
CREATE TABLE category (
    id   INT AUTO_INCREMENT PRIMARY KEY,          -- PK, 자동 증가
    name VARCHAR(50) NOT NULL UNIQUE              -- NOT NULL + UNIQUE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- publisher : 출판사 (부모)
-- ---------------------------------------------------------------------
CREATE TABLE publisher (
    id    INT AUTO_INCREMENT PRIMARY KEY,
    name  VARCHAR(100) NOT NULL UNIQUE,           -- UNIQUE
    phone VARCHAR(30)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- member : 회원 (부모)
-- ---------------------------------------------------------------------
CREATE TABLE member (
    id              INT AUTO_INCREMENT PRIMARY KEY,
    name            VARCHAR(50)  NOT NULL,               -- NOT NULL
    email           VARCHAR(255) NOT NULL UNIQUE,        -- NOT NULL + UNIQUE
    phone           VARCHAR(30),
    membership_type VARCHAR(10)  NOT NULL DEFAULT 'BASIC'
                      CHECK (membership_type IN ('BASIC', 'PREMIUM')),  -- 값 범위 제한
    joined_at       DATE NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- book : 도서 (category, publisher 참조)
-- ---------------------------------------------------------------------
CREATE TABLE book (
    id             INT AUTO_INCREMENT PRIMARY KEY,
    title          VARCHAR(200) NOT NULL,               -- NOT NULL
    author         VARCHAR(100) NOT NULL,               -- NOT NULL
    isbn           VARCHAR(20) UNIQUE,                   -- UNIQUE
    published_year INT,
    total_copies   INT NOT NULL DEFAULT 1
                     CHECK (total_copies >= 0),          -- 0 이상만
    category_id    INT NOT NULL,                          -- FK (분류 필수)
    publisher_id   INT,                                   -- FK (미상 허용 = NULL)
    FOREIGN KEY (category_id)  REFERENCES category(id),
    FOREIGN KEY (publisher_id) REFERENCES publisher(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- rental : 대여 기록 (member, book 참조 = 1:N 두 개의 교차점)
-- ---------------------------------------------------------------------
CREATE TABLE rental (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    member_id   INT  NOT NULL,                            -- FK
    book_id     INT  NOT NULL,                            -- FK
    rented_at   DATE NOT NULL,
    due_date    DATE NOT NULL,
    returned_at DATE,                                     -- NULL = 대여 중
    FOREIGN KEY (member_id) REFERENCES member(id),
    FOREIGN KEY (book_id)   REFERENCES book(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
