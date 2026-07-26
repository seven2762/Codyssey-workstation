#!/usr/bin/env bash
#
# 도서 관리 DB - 스키마/데이터 적재 후 쿼리를 실행해 결과를 캡처한다.
#   ./run.sh
# 산출물:
#   library.db                  : SQLite 데이터베이스 파일
#   results/results.txt         : queries.sql 전체 실행 결과(쿼리 + 결과 표)
#   results/fk-violation.txt    : FK 위반 시도 및 차단 결과(보너스)

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

DB=library.db
mkdir -p results

echo "[1/3] 스키마와 샘플 데이터 적재..."
rm -f "$DB"
sqlite3 "$DB" < schema.sql
sqlite3 "$DB" < data.sql

echo "[2/3] 쿼리 실행 결과 캡처 -> results/results.txt"
# .echo on : 실행되는 각 SQL을 결과 위에 함께 출력 -> 쿼리와 결과가 짝지어 보인다.
# .mode box + .headers on : 결과를 사람이 보기 좋은 표로 출력.
sqlite3 "$DB" <<'SQL' > results/results.txt 2>&1
.echo on
.mode box
.headers on
.read queries.sql
SQL

echo "[3/3] FK 무결성 시연 -> results/fk-violation.txt"
{
  echo "# 존재하지 않는 member_id(999)로 대여를 시도하면 FK 제약이 막는다."
  echo "\$ INSERT INTO rental(member_id, book_id, ...) VALUES (999, 1, ...);"
  echo "--- 결과 ---"
  sqlite3 "$DB" "PRAGMA foreign_keys=ON; \
    INSERT INTO rental(member_id, book_id, rented_at, due_date) \
    VALUES (999, 1, '2026-07-26', '2026-08-09');" 2>&1 || true
} > results/fk-violation.txt

echo "완료. library.db 및 results/ 생성됨."
