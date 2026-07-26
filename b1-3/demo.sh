#!/usr/bin/env bash
#
# b1-3 가계부 앱 시연 스크립트.
#   ./demo.sh          # 자동으로 쭉 실행
#   PAUSE=1 ./demo.sh  # 단계마다 Enter로 넘기며 시연
#
# 실행 결과와 저장 파일은 ./demo-run/ 아래에 남겨 두어 직접 확인할 수 있다.

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DEMO_DIR="$ROOT_DIR/demo-run"
DATA_DIR="$DEMO_DIR/data"
APP=(python3 -m budget_app --data-dir "$DATA_DIR")

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_TITLE='\033[1;36m'; C_CMD='\033[1;33m'; C_NOTE='\033[0;90m'; C_WARN='\033[0;31m'; C_OFF='\033[0m'
else
    C_TITLE=''; C_CMD=''; C_NOTE=''; C_WARN=''; C_OFF=''
fi

section() {
    printf "\n${C_TITLE}========================================================\n"
    printf "  %s\n" "$1"
    printf "========================================================${C_OFF}\n"
}

note() { printf "${C_NOTE}# %s${C_OFF}\n" "$1"; }

# 명령을 화면에 보여준 뒤 실행한다. 실패(0이 아닌 종료)해도 시연은 계속한다.
run() {
    printf "\n${C_CMD}\$ %s${C_OFF}\n" "$*"
    set +e
    "$@"
    local rc=$?
    set -e
    [ $rc -ne 0 ] && printf "${C_WARN}[종료 코드 %d]${C_OFF}\n" "$rc"
    return 0
}

pause() {
    [ "${PAUSE:-0}" = "1" ] || return 0
    printf "${C_NOTE}"
    read -rp "  -- Enter로 계속 --" _
    printf "${C_OFF}"
}

cd "$ROOT_DIR"
rm -rf "$DEMO_DIR"
mkdir -p "$DATA_DIR"
trap 'printf "\n${C_NOTE}# 시연 데이터: %s${C_OFF}\n" "$DEMO_DIR"' EXIT

# ---------------------------------------------------------------------------
section "1. 카테고리 — 기본 목록 확인 & 추가"
note "설치 시 기본 카테고리가 자동 생성된다."
run "${APP[@]}" category list
run "${APP[@]}" category add --name cafe
pause

# ---------------------------------------------------------------------------
section "2. 대화형 추가 (add) — 프롬프트에 값을 순서대로 입력"
note "date -> type -> category -> amount -> memo -> tags 순서로 물어본다."
printf '2026-07-25\nexpense\nfood\n15000\n저녁 회식\ndinner\n' | run "${APP[@]}" add
pause

# ---------------------------------------------------------------------------
section "3. CSV 가져오기 (import) — 여러 건을 한 번에"
cat > "$DEMO_DIR/seed.csv" <<'CSV'
date,type,category,amount,memo,tags
2026-07-01,income,salary,3000000,7월 급여,
2026-07-03,expense,food,12000,점심,"work,lunch"
2026-07-10,expense,transport,50000,교통카드,
2026-07-15,expense,cafe,8000,아메리카노,cafe
2026-07-20,expense,housing,600000,월세,
2026-08-02,expense,food,9000,점심,
CSV
note "헤더(첫 줄)에 필수 열이 있어야 하고, 카테고리는 미리 등록돼 있어야 한다."
run cat "$DEMO_DIR/seed.csv"
run "${APP[@]}" import --from "$DEMO_DIR/seed.csv"
pause

# ---------------------------------------------------------------------------
section "4. 목록 (list) — 기본 20건 vs --limit 0(전체)"
note "옵션 없으면 최신 20건까지만. --limit 0 이면 전체를 출력."
run "${APP[@]}" list --limit 3
run "${APP[@]}" list --limit 0
pause

# ---------------------------------------------------------------------------
section "5. 검색 (search) — 조건 조합"
run "${APP[@]}" search --from 2026-07-01 --to 2026-07-31 --type expense
run "${APP[@]}" search --tag cafe
pause

# ---------------------------------------------------------------------------
section "6. 예산 (budget) — 설정 후 요약에서 초과 경고"
run "${APP[@]}" budget set --month 2026-07 --amount 500000
run "${APP[@]}" budget list
note "7월 지출이 예산을 넘으므로 요약에 초과 경고가 뜬다."
run "${APP[@]}" summary --month 2026-07
pause

# ---------------------------------------------------------------------------
section "7. 내보내기 (export) — id 열을 포함한 CSV 생성"
run "${APP[@]}" export --out "$DEMO_DIR/july.csv" --month 2026-07
note "export한 CSV는 맨 앞에 id 열을 포함한다."
run cat "$DEMO_DIR/july.csv"
pause

# ---------------------------------------------------------------------------
section "8. 재가져오기가 멱등 (upsert) — 같은 파일 두 번 넣어도 중복 X"
before=$("${APP[@]}" list --limit 0 | grep -c '|' || true)
run "${APP[@]}" import --from "$DEMO_DIR/july.csv"
run "${APP[@]}" import --from "$DEMO_DIR/july.csv"
after=$("${APP[@]}" list --limit 0 | grep -c '|' || true)
note "재import 전 거래 수: $before / 두 번 재import 후: $after  (id로 교체되어 그대로)"
pause

# ---------------------------------------------------------------------------
section "9. 오류 처리 — 헤더 없는 CSV는 안전하게 거부"
printf 'not,a,valid\nheader,row,here\n' > "$DEMO_DIR/bad.csv"
note "필수 열이 없으니 저장소를 건드리지 않고 실패한다(종료 코드 1)."
run "${APP[@]}" import --from "$DEMO_DIR/bad.csv"
pause

# ---------------------------------------------------------------------------
section "10. 저장 형식 — 내부는 JSONL, 교환은 CSV"
note "내부 저장소는 한 줄에 JSON 하나(JSONL):"
run head -n 3 "$DATA_DIR/transactions.jsonl"
note "같은 데이터를 CSV로 내보내면(위 7단계 july.csv) 표 형태가 된다."

section "시연 종료"
