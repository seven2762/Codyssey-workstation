# b1-3 — 파일 기반 콘솔 가계부

표준 라이브러리만 사용한 Python 콘솔 가계부다. 거래 CRUD, 조건 검색, 월별 요약,
예산 경고, 카테고리 관리, CSV 가져오기/내보내기를 제공한다. 거래 파일은 한 번에
메모리에 올리지 않고 제너레이터로 읽으며, 수정·삭제·일괄 가져오기는 임시 파일을
완성한 뒤 `os.replace()`로 원자적으로 교체한다.

## 실행 환경과 시작

- Python 3.10 이상
- 외부 패키지 설치 불필요

`b1-3` 폴더에서 실행한다.

```bash
cd b1-3
python3 -m budget_app --help
python3 -m budget_app add
```

기본 저장 폴더는 현재 디렉터리의 `./data`다. 다른 폴더를 사용하려면 전역 옵션인
`--data-dir`을 **명령어 앞에** 지정한다.

```bash
python3 -m budget_app --data-dir ./demo-data list --limit 10
```

첫 실행 시 저장 폴더와 세 JSONL 파일을 자동 생성한다. 카테고리 파일이 없거나
비어 있으면 `food`, `transport`, `housing`, `salary`, `health`, `education`, `etc`를
기본값으로 만든다.

## 주요 명령

모든 명령과 하위 명령은 `--help`를 지원한다.

```bash
# 대화형 거래 추가
python3 -m budget_app add

# 최근 저장순 목록과 검색 (--limit 0은 전체 출력)
python3 -m budget_app list --limit 20
python3 -m budget_app search --from 2026-07-01 --to 2026-07-31 \
  --category food --type expense --q lunch --tag work

# 월 요약과 지출 카테고리 TOP 5
python3 -m budget_app summary --month 2026-07 --top 5

# 월 예산 설정·조회
python3 -m budget_app budget set --month 2026-07 --amount 500000
python3 -m budget_app budget get --month 2026-07
python3 -m budget_app budget list

# 카테고리 관리
python3 -m budget_app category add --name books
python3 -m budget_app category list
python3 -m budget_app category remove --name books

# 거래 수정: 이 프로젝트는 옵션 방식을 고정 사용한다
python3 -m budget_app update --id TRANSACTION_ID --amount 15000 --memo dinner
python3 -m budget_app update --id TRANSACTION_ID --tags "work,meal"
python3 -m budget_app update --id TRANSACTION_ID --tags ""  # 태그 전체 삭제

# 거래 삭제
python3 -m budget_app delete --id TRANSACTION_ID

# CSV 가져오기와 조건부 내보내기
python3 -m budget_app import --from ./transactions.csv
python3 -m budget_app export --out ./july.csv --month 2026-07
python3 -m budget_app export --out ./period.csv \
  --from 2026-07-01 --to 2026-07-31
```

`summary`는 총수입, 총지출, 잔액, 카테고리별 지출을 출력한다. 같은 달의 예산이
설정되어 있으면 사용률을 표시하고, 지출이 예산보다 크면 초과 경고도 출력한다.
거래가 없는 달에는 `데이터 없음`을 명확히 표시한다.

카테고리 삭제 시 해당 카테고리를 사용하는 거래가 하나라도 있으면 삭제를 막는다.
먼저 `update`로 해당 거래의 카테고리를 변경해야 한다.

## 저장 파일 위치와 형식

기본 구성은 다음과 같다.

```text
data/
├── transactions.jsonl  # 거래, 한 줄에 한 JSON 객체
├── categories.jsonl    # 등록 카테고리
├── budgets.jsonl       # 월별 예산
└── budget_app.log      # 데코레이터 실행 로그와 실행 시간
```

각 JSONL 파일은 UTF-8이며 한 줄이 독립된 JSON 객체다.

```json
{"id":"...","date":"2026-07-14","type":"expense","category":"food","amount":12000,"memo":"lunch","tags":["work","meal"]}
{"name":"food"}
{"month":"2026-07","amount":500000}
```

`transactions.jsonl`은 append 방식으로 추가한다. `list`와 `search`는 파일 끝에서
블록 단위로 역방향 읽는 제너레이터를 사용하므로 전체 파일을 리스트로 만들지 않는다.
요약과 카테고리 사용 여부 검사도 순방향 제너레이터로 한 건씩 처리한다.

수정·삭제·예산·카테고리 변경은 같은 디렉터리에 임시 파일을 쓰고 `flush`와
`fsync`를 마친 뒤 원본을 원자적으로 교체한다. CSV import도 먼저 모든 행을 검증한
뒤 거래 파일을 한 번만 교체하므로, 중간 행이 잘못되면 일부만 등록되는 일이 없다.

## import/export CSV 스키마

- 인코딩: UTF-8(가져오기는 UTF-8 BOM도 허용)
- 첫 줄: 헤더 필수
- 태그: 한 셀 안에서 쉼표로 구분. 태그가 여러 개면 CSV 규칙에 따라 셀을 큰따옴표로 감싼다.
- import의 카테고리는 미리 등록되어 있어야 한다.
- export는 `--month` 또는 `--from`과 `--to` 한 쌍 중 하나가 필수다.
- export는 항상 `id`를 포함해 내보낸다. import는 `id`가 있으면 같은 id 거래를
  교체(upsert)하고, 없으면 새 거래로 추가하므로 export→import 왕복이 멱등이다.

| column | required | 설명 |
| --- | --- | --- |
| `id` | N | 있으면 upsert 키, 없으면 새 id 발급 |
| `date` | Y | `YYYY-MM-DD` 실제 날짜 |
| `type` | Y | `income` 또는 `expense` |
| `category` | Y | 등록된 카테고리 |
| `amount` | Y | 0보다 큰 정수 |
| `memo` | N | 문자열 |
| `tags` | N | 쉼표 구분 문자열 |

예시(직접 작성 시 `id`는 생략 가능):

```csv
date,type,category,amount,memo,tags
2026-07-14,expense,food,12000,lunch,"work,meal"
2026-07-25,income,salary,3000000,monthly salary,
```

## 모듈 책임

```text
budget_app/
├── models.py        # dataclass와 검색/요약 타입 계약
├── validators.py    # 날짜·월·금액·타입·태그 검증
├── repositories.py # JSONL 스트리밍과 원자적 파일 I/O
├── services.py      # CRUD·검색·요약·예산·CSV 사용 사례
├── decorators.py   # 실행 로그와 시간 측정 공통 관심사
├── cli.py           # argparse, 대화형 입력, 출력과 종료 코드
└── __main__.py      # python -m budget_app 진입점
```

`Transaction.create(...) -> Transaction`, `iter_transactions(...) -> Iterator[Transaction]`
같은 타입 힌트는 계층 간 입력·출력 계약을 드러낸다. `@log_execution`은 비즈니스
함수의 성공·실패와 실행 시간을 기록하면서 원래 반환값과 예외를 보존한다.

## 오류와 종료 코드

예상 가능한 오류는 스택트레이스 대신 다음 두 줄로 출력한다.

```text
오류: 거래 id 'missing'를 찾을 수 없습니다.
해결 방법: list 또는 search로 올바른 id를 확인해 주세요.
```

- 정상 완료: `0`
- 입력·저장·없는 데이터 오류: `1`
- argparse 사용법 오류: `2`
- 입력 중단(`Ctrl+C`, EOF): `130`

금액과 예산은 float으로 바꾸지 않고 Python 정수로 보존한다. 따라서 일반적인
고정 폭 정수보다 큰 값도 JSONL 저장, 합계, 쉼표 출력에서 자릿수가 손실되지 않는다.
예산 사용률은 `Decimal`로 계산해 큰 정수에서도 float 오버플로가 발생하지 않는다.
단, 소수 입력은 명세상 허용되지 않으며 Python이 보안상 제한하는 비정상적으로 긴
정수 문자열은 입력 오류로 처리한다.

대화형 입력 중 표준 입력이 끝나면 EOF 안내와 함께 `130`으로 종료한다. 출력이
`head` 같은 파이프 소비자에 의해 먼저 닫힌 경우에는 `BrokenPipeError`나 종료 시
스택트레이스를 노출하지 않고 정상 종료한다.

카테고리·메모·태그·경로에는 줄바꿈, 탭, ESC 같은 제어문자와 비표시 문자를
허용하지 않는다. 이런 문자가 포함된 손상 JSONL은 저장 오류로 차단한다. 출력
함수도 이중 방어로 백슬래시, `|`, 비표시 문자를 가시적인 이스케이프 문자열로
바꾼다. 따라서 거래 목록은 항상 한 거래당 한 줄을 유지하고 ` | ` 구분 필드 수가
사용자 문자열 때문에 달라지지 않는다.

## 빠른 실행 확인

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m budget_app --help
PYTHONDONTWRITEBYTECODE=1 python3 -m budget_app --data-dir /tmp/budget-demo category list
```
