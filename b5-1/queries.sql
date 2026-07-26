-- =====================================================================
--  도서 관리 데이터베이스 - 핵심 쿼리 모음 (총 20개)
--  DB: SQLite 3
--  실행: sqlite3 library.db < queries.sql   (schema.sql, data.sql 이후)
--
--  구성  기본 조회 4 | 조인 5(INNER 3 + LEFT 2) | 집계 4 | 서브쿼리 3
--        | 수정·삭제 3(UPDATE 2 + DELETE 1) | 인덱스 2
--  각 쿼리 앞에 "무엇을 확인하는지" 한 줄 설명을 붙였다.
--  기준일은 SQLite의 date('now') = 2026-07-26 을 사용한다.
-- =====================================================================

PRAGMA foreign_keys = ON;

-- =====================================================================
--  A. 기본 조회 (WHERE / ORDER BY / LIMIT)
-- =====================================================================

-- Q01. 2018년 이후 출간된 도서를 최신 출간연도순으로 본다.
SELECT title, author, published_year
FROM book
WHERE published_year >= 2018
ORDER BY published_year DESC, title ASC;

-- Q02. 보유 권수가 가장 적은 도서 TOP 5 (재고 부족 점검).
SELECT title, total_copies
FROM book
ORDER BY total_copies ASC
LIMIT 5;

-- Q03. 아직 반납되지 않은(대여 중) 기록을 대여일순으로 본다.
SELECT id, member_id, book_id, rented_at, due_date
FROM rental
WHERE returned_at IS NULL
ORDER BY rented_at;

-- Q04. PREMIUM 등급 회원을 가입일이 빠른 순으로 본다.
SELECT name, email, joined_at
FROM member
WHERE membership_type = 'PREMIUM'
ORDER BY joined_at ASC;

-- =====================================================================
--  B. 조인 (INNER JOIN 3 + LEFT JOIN 2)
-- =====================================================================

-- Q05. [INNER] 현재 대여 중인 도서를 '회원명 + 도서제목'으로 본다.
SELECT m.name AS member, b.title AS book, r.rented_at, r.due_date
FROM rental r
INNER JOIN member m ON m.id = r.member_id
INNER JOIN book   b ON b.id = r.book_id
WHERE r.returned_at IS NULL
ORDER BY r.due_date;

-- Q06. [INNER] 도서 상세를 '제목 + 분류명 + 출판사명'으로 본다(3테이블 조인).
SELECT b.title, c.name AS category, p.name AS publisher, b.published_year
FROM book b
INNER JOIN category  c ON c.id = b.category_id
INNER JOIN publisher p ON p.id = b.publisher_id
ORDER BY c.name, b.title;

-- Q07. [INNER] 연체 목록: 미반납 + 기한 초과 건을 연체일수와 함께 본다.
--      [SQLite 전용] julianday(), date('now') 는 SQLite 날짜 함수다.
SELECT m.name AS member, b.title AS book, r.due_date,
       CAST(julianday('now') - julianday(r.due_date) AS INTEGER) AS overdue_days
FROM rental r
INNER JOIN member m ON m.id = r.member_id
INNER JOIN book   b ON b.id = r.book_id
WHERE r.returned_at IS NULL
  AND r.due_date < date('now')
ORDER BY overdue_days DESC;

-- Q08. [LEFT] 분류별 보유 도서 수 (도서가 0권인 분류도 빠짐없이 보이도록 LEFT JOIN).
SELECT c.name AS category, COUNT(b.id) AS book_count
FROM category c
LEFT JOIN book b ON b.category_id = c.id
GROUP BY c.id
ORDER BY book_count DESC, c.name;

-- Q09. [LEFT] 대여 기록이 한 번도 없는 회원 찾기 (LEFT JOIN + IS NULL 방식).
SELECT m.name, m.email, m.joined_at
FROM member m
LEFT JOIN rental r ON r.member_id = m.id
WHERE r.id IS NULL
ORDER BY m.joined_at;

-- =====================================================================
--  C. 집계 (COUNT / SUM / AVG + GROUP BY)
-- =====================================================================

-- Q10. 회원별 총 대여 횟수를 많은 순으로 집계한다.
SELECT m.name AS member, COUNT(r.id) AS rental_count
FROM member m
INNER JOIN rental r ON r.member_id = m.id
GROUP BY m.id
ORDER BY rental_count DESC, m.name;

-- Q11. 가장 많이 대여된 인기 도서 TOP 5 (대여 횟수 랭킹).
SELECT b.title AS book, COUNT(r.id) AS times_rented
FROM book b
INNER JOIN rental r ON r.book_id = b.id
GROUP BY b.id
ORDER BY times_rented DESC, b.title
LIMIT 5;

-- Q12. 출판사별 보유 도서 총 권수 합계 (SUM).
SELECT p.name AS publisher, SUM(b.total_copies) AS total_copies
FROM publisher p
INNER JOIN book b ON b.publisher_id = p.id
GROUP BY p.id
ORDER BY total_copies DESC;

-- Q13. 분류별 평균 출간연도 (AVG, 소수 첫째 자리 반올림).
SELECT c.name AS category, ROUND(AVG(b.published_year), 1) AS avg_year
FROM category c
INNER JOIN book b ON b.category_id = c.id
GROUP BY c.id
ORDER BY avg_year DESC;

-- =====================================================================
--  D. 서브쿼리
-- =====================================================================

-- Q14. 한 번도 대여된 적 없는 도서 (NOT IN 서브쿼리).
SELECT title, author
FROM book
WHERE id NOT IN (SELECT book_id FROM rental)
ORDER BY title;

-- Q15. 평균 대여 횟수보다 많이 빌린 '단골' 회원 (중첩 서브쿼리 + HAVING).
SELECT m.name AS member, COUNT(r.id) AS rental_count
FROM member m
INNER JOIN rental r ON r.member_id = m.id
GROUP BY m.id
HAVING COUNT(r.id) > (
    SELECT AVG(cnt) FROM (
        SELECT COUNT(*) AS cnt FROM rental GROUP BY member_id
    )
)
ORDER BY rental_count DESC;

-- Q16. [보너스] 대여 기록 없는 회원을 '서브쿼리(NOT IN)'로 푼다. (Q09의 LEFT JOIN 방식과 비교용)
SELECT name, email, joined_at
FROM member
WHERE id NOT IN (SELECT member_id FROM rental)
ORDER BY joined_at;

-- =====================================================================
--  E. 데이터 수정·삭제 (UPDATE 2 + DELETE 1)
--    결과 확인을 위해 각 변경 앞뒤에 SELECT를 함께 둔다.
-- =====================================================================

-- Q17. 연체 중이던 대여(id=3)를 오늘자로 반납 처리한다 (UPDATE).
SELECT id, returned_at AS before_update FROM rental WHERE id = 3;   -- 변경 전
UPDATE rental
SET returned_at = date('now')
WHERE id = 3;
SELECT id, returned_at AS after_update FROM rental WHERE id = 3;    -- 변경 후

-- Q18. 인기 도서 '클린 코드'(id=5)를 2권 재입고한다 (UPDATE).
SELECT title, total_copies AS before_update FROM book WHERE id = 5; -- 변경 전
UPDATE book
SET total_copies = total_copies + 2
WHERE id = 5;
SELECT title, total_copies AS after_update FROM book WHERE id = 5;  -- 변경 후

-- Q19. 2026-04-01 이전에 반납 완료된 오래된 대여 기록을 정리한다 (DELETE).
SELECT COUNT(*) AS before_count FROM rental;                        -- 변경 전 전체 건수
DELETE FROM rental
WHERE returned_at IS NOT NULL
  AND returned_at < '2026-04-01';
SELECT COUNT(*) AS after_count FROM rental;                         -- 변경 후 전체 건수

-- =====================================================================
--  F. 인덱스 (CREATE INDEX + 적용 이유)
-- =====================================================================

-- Q20-1. 회원별 대여 조회/조인(rental.member_id)이 잦으므로 탐색 속도를 위해 인덱스를 만든다.
CREATE INDEX IF NOT EXISTS idx_rental_member_id ON rental(member_id);

-- Q20-2. 도서별 대여 집계(rental.book_id 기준 인기 랭킹)가 잦으므로 인덱스를 만든다.
CREATE INDEX IF NOT EXISTS idx_rental_book_id ON rental(book_id);

-- (확인) 생성된 인덱스 목록.
SELECT name, tbl_name FROM sqlite_master WHERE type = 'index' AND sql IS NOT NULL;
