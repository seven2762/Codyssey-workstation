"""
Mini NPU 시뮬레이터
MAC(Multiply-Accumulate) 연산 기반 패턴 판별 프로그램
"""

import json
import time
import os


# ─────────────────────────────────────────────
# 1. 데이터 구조
# ─────────────────────────────────────────────

class Pattern:
  """n×n 2차원 패턴 또는 필터를 저장하는 클래스"""

  def __init__(self, data: list[list[float]]):
    self._data = [row[:] for row in data]
    self.size = len(data)

  def get(self, row: int, col: int) -> float:
    return self._data[row][col]

  def set(self, row: int, col: int, value: float):
    self._data[row][col] = value

  def to_2d(self) -> list[list[float]]:
    return [row[:] for row in self._data]

  def __repr__(self):
    lines = []
    for row in self._data:
      lines.append("  " + "  ".join(f"{v:.1f}" for v in row))
    return "\n".join(lines)


# ─────────────────────────────────────────────
# 2. 라벨 정규화
# ─────────────────────────────────────────────

LABEL_MAP = {
  "+": "Cross",
  "cross": "Cross",
  "Cross": "Cross",
  "CROSS": "Cross",
  "x": "X",
  "X": "X",
  "더하기": "Cross",
  "엑스": "X",
}


def normalize_label(raw: str) -> str:
  """다양한 형태의 라벨을 표준 라벨(Cross / X)로 변환"""
  normalized = LABEL_MAP.get(raw.strip())
  if normalized is None:
    raise ValueError(f"알 수 없는 라벨: '{raw}'")
  return normalized


# ─────────────────────────────────────────────
# 3. MAC 연산
# ─────────────────────────────────────────────

def mac(pattern: Pattern, filt: Pattern) -> float:
  """
  MAC(Multiply-Accumulate) 연산
  패턴과 필터를 위치별로 곱하고 모두 더해 유사도 점수를 반환한다.
  """
  if pattern.size != filt.size:
    raise ValueError(
        f"크기 불일치: 패턴({pattern.size}×{pattern.size}) ≠ "
        f"필터({filt.size}×{filt.size})"
    )
  n = pattern.size
  total = 0.0
  for r in range(n):
    for c in range(n):
      total += pattern.get(r, c) * filt.get(r, c)
  return total


# ─────────────────────────────────────────────
# 4. 점수 비교 및 판정
# ─────────────────────────────────────────────

EPSILON = 1e-9


def judge(score_cross: float, score_x: float) -> str:
  """
  두 필터 점수를 비교해 Cross / X / UNDECIDED 를 반환한다.
  허용오차(epsilon) 기반 비교로 부동소수점 오차를 처리한다.
  """
  if abs(score_cross - score_x) < EPSILON:
    return "UNDECIDED"
  return "Cross" if score_cross > score_x else "X"


# ─────────────────────────────────────────────
# 5. 성능 측정
# ─────────────────────────────────────────────

def measure_mac_time(n: int, repeat: int = 10) -> float:
  """
  n×n 크기의 임의 패턴/필터로 MAC 연산을 repeat회 반복 측정하고
  평균 시간(ms)을 반환한다. I/O 시간은 포함하지 않는다.
  """
  # 테스트용 패턴·필터 생성 (I/O 제외, 연산만 측정)
  data = [[float((r + c) % 2) for c in range(n)] for r in range(n)]
  p = Pattern(data)
  f = Pattern(data)

  times = []
  for _ in range(repeat):
    t0 = time.perf_counter()
    mac(p, f)
    t1 = time.perf_counter()
    times.append((t1 - t0) * 1000)  # ms

  return sum(times) / len(times)


# ─────────────────────────────────────────────
# 6. 콘솔 입력 유틸
# ─────────────────────────────────────────────

def input_matrix(name: str, n: int) -> Pattern:
  """콘솔에서 n×n 행렬을 입력받아 Pattern 으로 반환한다."""
  print(f"\n[{name}] {n}×{n} 행렬 입력 (각 줄에 {n}개의 숫자를 공백으로 구분):")
  rows = []
  while len(rows) < n:
    line = input(f"  행 {len(rows) + 1}: ").strip()
    try:
      vals = list(map(float, line.split()))
      if len(vals) != n:
        print(f"  입력 형식 오류: 각 줄에 {n}개의 숫자를 공백으로 구분해 입력하세요.")
        continue
      rows.append(vals)
    except ValueError:
      print(f"  입력 형식 오류: 숫자만 입력하세요.")
  return Pattern(rows)


# ─────────────────────────────────────────────
# 7. 모드 1 – 사용자 직접 입력 (3×3)
# ─────────────────────────────────────────────

def mode_manual():
  print("\n" + "=" * 50)
  print("  [모드 1] 사용자 입력 (3×3)")
  print("=" * 50)

  filter_a = input_matrix("필터 A", 3)
  print(f"\n필터 A 저장 완료:\n{filter_a}")

  filter_b = input_matrix("필터 B", 3)
  print(f"\n필터 B 저장 완료:\n{filter_b}")

  pattern = input_matrix("입력 패턴", 3)
  print(f"\n패턴 저장 완료:\n{pattern}")

  # MAC 연산
  t0 = time.perf_counter()
  score_a = mac(pattern, filter_a)
  score_b = mac(pattern, filter_b)
  elapsed_ms = (time.perf_counter() - t0) * 1000

  result = judge(score_a, score_b)

  print("\n" + "-" * 40)
  print(f"  필터 A 점수 : {score_a:.6f}")
  print(f"  필터 B 점수 : {score_b:.6f}")
  print(f"  연산 시간   : {elapsed_ms:.4f} ms")
  print(f"  판정 결과   : {result}")
  print("-" * 40)

  # 성능 분석 (3×3)
  print("\n[성능 분석]")
  avg = measure_mac_time(3)
  print(f"  크기: 3×3 | 평균 시간: {avg:.4f} ms | 연산 횟수(N²): {3 * 3}")


# ─────────────────────────────────────────────
# 8. 모드 2 – data.json 분석
# ─────────────────────────────────────────────

def load_json(path: str) -> dict:
  with open(path, "r", encoding="utf-8") as f:
    return json.load(f)


def validate_and_run_json(data: dict):
  """data.json 을 파싱하고 모든 패턴을 판정한다."""

  filters_raw = data.get("filters", {})
  patterns_raw = data.get("patterns", {})

  # 필터 로드 및 라벨 정규화
  filters: dict[int, dict[str, Pattern]] = {}
  for size_key, filt_dict in filters_raw.items():
    try:
      n = int(size_key.split("_")[1])
    except (IndexError, ValueError):
      print(f"  [경고] 필터 키 파싱 실패: {size_key}")
      continue

    filters[n] = {}
    for label_raw, matrix in filt_dict.items():
      try:
        label = normalize_label(label_raw)
      except ValueError as e:
        print(f"  [경고] {e}")
        continue
      filters[n][label] = Pattern(matrix)

  # 패턴 로드 및 판정
  total = 0
  passed = 0
  failed = 0
  fail_cases = []

  print("\n" + "=" * 60)
  print("  [모드 2] data.json 분석 결과")
  print("=" * 60)

  for key, item in patterns_raw.items():
    total += 1
    parts = key.split("_")

    # 크기 추출: size_{N}_{idx}
    try:
      n = int(parts[1])
    except (IndexError, ValueError):
      fail_cases.append((key, "키에서 크기(N) 추출 실패"))
      failed += 1
      print(f"  [{key}] FAIL - 키 파싱 오류")
      continue

    # 필터 존재 확인
    if n not in filters:
      fail_cases.append((key, f"size_{n} 필터 없음"))
      failed += 1
      print(f"  [{key}] FAIL - size_{n} 필터 없음")
      continue

    filt_set = filters[n]
    if "Cross" not in filt_set or "X" not in filt_set:
      fail_cases.append((key, "Cross 또는 X 필터 미정의"))
      failed += 1
      print(f"  [{key}] FAIL - Cross/X 필터 미정의")
      continue

    # 패턴 로드
    try:
      pattern = Pattern(item["input"])
    except (KeyError, TypeError) as e:
      fail_cases.append((key, f"input 필드 오류: {e}"))
      failed += 1
      print(f"  [{key}] FAIL - input 파싱 오류")
      continue

    # 크기 검증
    if pattern.size != n:
      fail_cases.append((key, f"크기 불일치: 패턴={pattern.size}, 필터={n}"))
      failed += 1
      print(f"  [{key}] FAIL - 크기 불일치 (패턴:{pattern.size} ≠ 필터:{n})")
      continue

    # MAC 연산
    score_cross = mac(pattern, filt_set["Cross"])
    score_x = mac(pattern, filt_set["X"])
    verdict = judge(score_cross, score_x)

    # expected 정규화
    try:
      expected = normalize_label(item["expected"])
    except (KeyError, ValueError) as e:
      fail_cases.append((key, f"expected 필드 오류: {e}"))
      failed += 1
      print(f"  [{key}] FAIL - expected 파싱 오류")
      continue

    # PASS / FAIL
    if verdict == expected:
      outcome = "PASS"
      passed += 1
    else:
      outcome = "FAIL"
      failed += 1
      fail_cases.append((key, f"판정={verdict}, expected={expected}"))

    print(
        f"  [{key}] Cross={score_cross:.4f}  X={score_x:.4f}  "
        f"판정={verdict}  expected={expected}  → {outcome}"
    )

  return total, passed, failed, fail_cases


def mode_json(path: str):
  if not os.path.exists(path):
    print(f"  오류: '{path}' 파일을 찾을 수 없습니다.")
    return

  data = load_json(path)
  total, passed, failed, fail_cases = validate_and_run_json(data)

  # 성능 분석
  sizes = [3, 5, 13, 25]
  print("\n" + "=" * 60)
  print("  [성능 분석] 크기별 MAC 평균 연산 시간 (반복 10회)")
  print("=" * 60)
  print(f"  {'크기(N×N)':<12} {'평균 시간(ms)':<18} {'연산 횟수(N²)':<15}")
  print("  " + "-" * 42)
  for n in sizes:
    avg_ms = measure_mac_time(n, repeat=10)
    print(f"  {f'{n}×{n}':<12} {avg_ms:<18.6f} {n * n:<15}")

  # 결과 요약
  print("\n" + "=" * 60)
  print("  [결과 요약]")
  print("=" * 60)
  print(f"  전체 테스트: {total}  /  통과: {passed}  /  실패: {failed}")
  if fail_cases:
    print("\n  실패 케이스:")
    for case_id, reason in fail_cases:
      print(f"    - {case_id}: {reason}")
  else:
    print("\n  모든 테스트 통과! (실패 0건)")
    print("  → 라벨 정규화(+/x → Cross/X)와 epsilon 기반 동점 처리 덕분에")
    print("    부동소수점 오차 및 표기 불일치로 인한 오판정이 방지되었습니다.")


# ─────────────────────────────────────────────
# 9. 메인 실행 흐름
# ─────────────────────────────────────────────

def main():
  print("\n" + "╔" + "═" * 48 + "╗")
  print("║        Mini NPU 시뮬레이터 (MAC 연산)          ║")
  print("╚" + "═" * 48 + "╝")
  print("\n입력 방식을 선택하세요:")
  print("  1) 사용자 직접 입력 (3×3 필터 A/B + 패턴)")
  print("  2) data.json 분석 (5×5, 13×13, 25×25)")

  while True:
    choice = input("\n선택 (1 또는 2): ").strip()
    if choice == "1":
      mode_manual()
      break
    elif choice == "2":
      json_path = input("data.json 경로 (기본값: data.json): ").strip()
      if not json_path:
        json_path = "data.json"
      mode_json(json_path)
      break
    else:
      print("  1 또는 2를 입력하세요.")


if __name__ == "__main__":
  main()
