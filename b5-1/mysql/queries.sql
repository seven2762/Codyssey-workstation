-- =====================================================================
--  도서 관리 데이터베이스 - 핵심 쿼리 20개 (MySQL 8 버전)
--  실행: mysql -uroot -p library < queries.sql
--
--  구성  기본 조회 4 | 조인 5(INNER 3 + LEFT 2) | 집계 4 | 서브쿼리 3
--        | 수정·삭제 3 | 인덱스 2
--  기준일은 MySQL의 CURDATE() = 실행 당일. (SQLite date('now') 대응)
--
--  SQLite 버전과 다른 부분(주석에 [MySQL] 표시)
--    - julianday(a)-julianday(b)   -> DATEDIFF(a, b)
--    - date('now')                 -> CURDATE()
--    - FROM (SELECT ...)           -> 파생테이블에 별칭 필수 (AS sub)
--    - CREATE INDEX IF NOT EXISTS  -> MySQL 미지원 -> 일반 CREATE INDEX
--    - 인덱스 목록 확인            -> SHOW INDEX
-- =====================================================================

USE library;

-- =====================================================================
--  A. 기본 조회
-- =====================================================================

-- Q01. 2018년 이후 출간 도서를 최신순으로.
SELECT title, author, published_year
FROM book
WHERE published_year >= 2018
ORDER BY published_year DESC, title ASC;

-- Q02. 보유 권수가 가장 적은 도서 TOP 5.
SELECT title, total_copies
FROM book
ORDER BY total_copies ASC
LIMIT 5;

-- Q03. 대여 중(미반납) 기록을 대여일순으로.
SELECT id, member_id, book_id, rented_at, due_date
FROM rental
WHERE returned_at IS NULL
ORDER BY rented_at;

-- Q04. PREMIUM 회원을 가입일 빠른 순으로.
SELECT name, email, joined_at
FROM member
WHERE membership_type = 'PREMIUM'
ORDER BY joined_at ASC;

-- =====================================================================
--  B. 조인 (INNER 3 + LEFT 2)
-- =====================================================================

-- Q05. [INNER] 현재 대여 중인 도서: 회원명 + 도서제목.
SELECT m.name AS member, b.title AS book, r.rented_at, r.due_date
FROM rental r
INNER JOIN member m ON m.id = r.member_id
INNER JOIN book   b ON b.id = r.book_id
WHERE r.returned_at IS NULL
ORDER BY r.due_date;

-- Q06. [INNER] 도서 상세: 제목 + 분류명 + 출판사명 (3테이블).
SELECT b.title, c.name AS category, p.name AS publisher, b.published_year
FROM book b
INNER JOIN category  c ON c.id = b.category_id
INNER JOIN publisher p ON p.id = b.publisher_id
ORDER BY c.name, b.title;

-- Q07. [INNER] 연체 목록 + 연체일수.
--      [MySQL] DATEDIFF(오늘, 기한) 로 일수 계산, CURDATE() = 오늘.
SELECT m.name AS member, b.title AS book, r.due_date,
       DATEDIFF(CURDATE(), r.due_date) AS overdue_days
FROM rental r
INNER JOIN member m ON m.id = r.member_id
INNER JOIN book   b ON b.id = r.book_id
WHERE r.returned_at IS NULL
  AND r.due_date < CURDATE()
ORDER BY overdue_days DESC;

-- Q08. [LEFT] 분류별 도서 수 (0권 분류도 포함).
SELECT c.name AS category, COUNT(b.id) AS book_count
FROM category c
LEFT JOIN book b ON b.category_id = c.id
GROUP BY c.id
ORDER BY book_count DESC, c.name;

-- Q09. [LEFT] 대여 기록 없는 회원 (LEFT JOIN + IS NULL).
SELECT m.name, m.email, m.joined_at
FROM member m
LEFT JOIN rental r ON r.member_id = m.id
WHERE r.id IS NULL
ORDER BY m.joined_at;

-- =====================================================================
--  C. 집계
-- =====================================================================

-- Q10. 회원별 총 대여 횟수.
SELECT m.name AS member, COUNT(r.id) AS rental_count
FROM member m
INNER JOIN rental r ON r.member_id = m.id
GROUP BY m.id
ORDER BY rental_count DESC, m.name;

-- Q11. 인기 도서 TOP 5 (대여 횟수 랭킹).
SELECT b.title AS book, COUNT(r.id) AS times_rented
FROM book b
INNER JOIN rental r ON r.book_id = b.id
GROUP BY b.id
ORDER BY times_rented DESC, b.title
LIMIT 5;

-- Q12. 출판사별 보유 도서 총 권수 (SUM).
SELECT p.name AS publisher, SUM(b.total_copies) AS total_copies
FROM publisher p
INNER JOIN book b ON b.publisher_id = p.id
GROUP BY p.id
ORDER BY total_copies DESC;

-- Q13. 분류별 평균 출간연도 (AVG).
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
--   [로직 분해 - 안쪽 서브쿼리에서 바깥으로 3단계로 읽는다]
--     1단계(가장 안쪽): 회원별 대여 횟수 목록을 만든다. (회원 1명당 1행)
--     2단계(중간):      그 횟수들의 '평균'을 구한다. (스칼라 값 1개)
--     3단계(바깥):      회원별 대여 횟수를 집계하고, HAVING으로 평균 초과만 남긴다.
--   [MySQL] 파생테이블에는 별칭이 필수 -> ... ) AS sub
SELECT m.name AS member, COUNT(r.id) AS rental_count   -- 3단계
FROM member m
INNER JOIN rental r ON r.member_id = m.id
GROUP BY m.id
HAVING COUNT(r.id) > (                                  -- 3단계 필터
    SELECT AVG(cnt) FROM (                              -- 2단계
        SELECT COUNT(*) AS cnt FROM rental GROUP BY member_id  -- 1단계
    ) AS sub
)
ORDER BY rental_count DESC;

-- Q16. [보너스] 대여 기록 없는 회원을 서브쿼리(NOT IN)로. (Q09의 LEFT JOIN 방식과 비교)
SELECT name, email, joined_at
FROM member
WHERE id NOT IN (SELECT member_id FROM rental)
ORDER BY joined_at;

-- =====================================================================
--  E. 데이터 수정·삭제
-- =====================================================================

-- Q17. 연체 대여(id=3)를 오늘자로 반납 처리 (UPDATE).
SELECT id, returned_at AS before_update FROM rental WHERE id = 3;
UPDATE rental SET returned_at = CURDATE() WHERE id = 3;   -- [MySQL] CURDATE()
SELECT id, returned_at AS after_update FROM rental WHERE id = 3;

-- Q18. 인기 도서 '클린 코드'(id=5)를 2권 재입고 (UPDATE).
SELECT title, total_copies AS before_update FROM book WHERE id = 5;
UPDATE book SET total_copies = total_copies + 2 WHERE id = 5;
SELECT title, total_copies AS after_update FROM book WHERE id = 5;

-- Q19. 2026-04-01 이전 반납 완료된 오래된 대여 기록 정리 (DELETE).
SELECT COUNT(*) AS before_count FROM rental;
DELETE FROM rental
WHERE returned_at IS NOT NULL
  AND returned_at < '2026-04-01';
SELECT COUNT(*) AS after_count FROM rental;

-- =====================================================================
--  F. 인덱스
--    [MySQL] CREATE INDEX 는 IF NOT EXISTS 를 지원하지 않는다.
--    (이미 있으면 에러 -> 재실행 시 DROP INDEX 후 생성하거나 무시)
-- =====================================================================

-- Q20-1. 회원별 대여 조회/조인(rental.member_id)이 잦으므로 인덱스 생성.
CREATE INDEX idx_rental_member_id ON rental(member_id);

-- Q20-2. 도서별 대여 집계(rental.book_id 랭킹)가 잦으므로 인덱스 생성.
CREATE INDEX idx_rental_book_id ON rental(book_id);

-- (확인) 생성된 인덱스 목록. [MySQL] SHOW INDEX 사용.
SHOW INDEX FROM rental;
