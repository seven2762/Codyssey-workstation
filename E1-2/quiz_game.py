from __future__ import annotations

import datetime
import json
import random
from pathlib import Path
from typing import Callable

from quiz import Quiz


class QuizGame:
    """퀴즈 게임 전체를 운영하는 클래스 — 메뉴, 게임 진행, 점수 관리, 파일 저장/로드를 담당한다."""

    def __init__(
        self,
        state_path: str | Path | None = None,
        input_func: Callable[[str], str] = input,
    ) -> None:
        """생성자 — state.json 경로 설정, 입력 함수 주입(테스트용), 상태 로드"""
        if state_path is None:
            # quiz_game.py가 있는 폴더 기준으로 state.json 경로를 설정한다
            self.state_path = Path(__file__).resolve().parent / "state.json"
        else:
            self.state_path = Path(state_path)
        # input 함수를 외부에서 주입받아 테스트 시 가짜 입력을 넣을 수 있게 한다 (의존성 주입)
        self.input_func = input_func
        self.quizzes: list[Quiz] = []
        self.history: list[dict[str, str | int]] = []
        # 프로그램 시작 시 state.json에서 데이터를 불러온다
        self.load_state()

    def default_quizzes(self) -> list[Quiz]:
        """state.json이 없거나 손상되었을 때 사용할 기본 퀴즈 6개를 반환한다."""
        return [
            Quiz(
                "축구 경기에서 한 팀이 동시에 뛸 수 있는 선수 수는 몇 명인가?",
                ["9명", "10명", "11명", "12명"],
                3,
                "hint : 10명 이상이다.",
            ),
            Quiz(
                "국제 축구 경기의 정규 시간은 보통 몇 분인가?",
                ["70분", "80분", "90분", "100분"],
                3,
                "hint : 정규 시간은 전반전과 후반전 각 2쿼터로 나뉘는데 한 쿼터당 45분이다.",
            ),
            Quiz(
                "페널티킥은 일반적으로 골문에서 몇 미터 지점에서 차는가?",
                ["11m", "9m", "12m", "15m"],
                1,
                "hint: 한 자릿수는 아니다.",
            ),
            Quiz(
                "축구에서 골키퍼가 페널티 에어리어 안에서 손으로 공을 잡을 수 있는 상황은?",
                [
                    "상대 팀 선수가 플레이한 공일 때",
                    "자기 팀 선수가 발로 의도적으로 백패스한 공일 때",
                    "자기 팀 선수가 스로인한 공이 직접 왔을 때",
                    "골키퍼가 이미 손에서 놓은 공을 다른 선수 접촉 없이 다시 손으로 잡을 때",
                ],
                1,
                "hint: 얍삽? 해 보이지 않는 선택지를 고르면 된다.",
            ),
            Quiz(
                "월드컵에서 우승 국가에게 수여되는 트로피의 이름은?",
                ["챔피언스컵", "FIFA 월드컵 트로피", "골든볼", "슈퍼컵"],
                2,
                "hint : 문제 속에 답이 있다.",
            ),
            Quiz(
                "다음 중 축구에서 오프사이드가 적용되지 않는 방식은?",
                ["프리킥", "골킥", "코너킥", "스로인"],
                4,
                "hint : 필드 플레이어가 유일하게 손을 사용할 수 있는 상황이다.",
            ),
        ]

    def record_history(self, question_count: int, score: int) -> None:
        """플레이 기록(날짜, 문제 수, 점수)을 history 리스트에 추가한다."""
        played_at = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

        record = {
            "played_at": played_at,
            "question_count": question_count,
            "score": score,
        }

        self.history.append(record)

    def get_answer_with_hint(self, quiz: Quiz) -> tuple[int, bool] | None:
        """사용자로부터 정답 또는 힌트 요청을 입력받는다.
        반환값: (정답 번호, 힌트 사용 여부) 튜플 또는 중단 시 None"""
        used_hint = False
        while True:
            raw = self.safe_input("정답 번호(1~4) 또는 힌트(h)를 입력하세요: ")
            if raw is None:
                return None

            value = raw.strip()
            if value == "":
                print("빈 입력은 사용할 수 없습니다.")
                continue

            # 힌트 요청 처리
            if value.lower() == "h":
                if used_hint:
                    print("이미 힌트를 사용했습니다.")
                else:
                    print(f"힌트: {quiz.hint}")
                    used_hint = True
                continue

            # 숫자 변환 시도
            try:
                answer = int(value)
            except ValueError:
                print("정답 번호 또는 h만 입력해주세요.")
                continue

            # 범위 검증
            if not (1 <= answer <= 4):
                print("1부터 4 사이 숫자를 입력해주세요.")
                continue

            return answer, used_hint

    def load_state(self) -> None:
        """state.json 파일에서 퀴즈 데이터와 히스토리를 불러온다.
        파일이 없으면 기본 퀴즈로 시작하고, 손상되었으면 기본 퀴즈로 복구한다."""
        # 파일이 존재하지 않으면 기본 퀴즈로 초기화
        if not self.state_path.exists():
            self.quizzes = self.default_quizzes()
            self.best_score = None
            self.save_state(silent=True)
            return

        try:
            # JSON 파일을 열어서 dict로 파싱
            with self.state_path.open("r", encoding="utf-8") as file:
                data = json.load(file)

            quizzes_data = data.get("quizzes", [])
            history_data = data.get("history", [])

            # dict 리스트를 Quiz 객체 리스트로 변환 (역직렬화)
            self.quizzes = [Quiz.from_dict(item) for item in quizzes_data]
            self.history = history_data
            if not self.quizzes:
                self.quizzes = self.default_quizzes()
        except (OSError, json.JSONDecodeError, KeyError, TypeError, ValueError):
            # 파일 손상 시 기본 퀴즈로 복구
            print("데이터 파일을 읽는 중 문제가 발생했습니다. 기본 퀴즈 데이터로 복구합니다.")
            self.quizzes = self.default_quizzes()
            self.save_state(silent=True)

    def save_state(self, silent: bool = False) -> None:
        """현재 퀴즈 데이터와 히스토리를 state.json 파일에 저장한다.
        silent=True이면 저장 실패 시 에러 메시지를 출력하지 않는다."""
        data = {
            # Quiz 객체 리스트를 dict 리스트로 변환 (직렬화)
            "quizzes": [quiz.to_dict() for quiz in self.quizzes],
            "history": self.history,
        }

        try:
            with self.state_path.open("w", encoding="utf-8") as file:
                # dict를 JSON 문자열로 변환하여 파일에 쓴다
                json.dump(data, file, ensure_ascii=False, indent=2)
        except OSError:
            if not silent:
                print("데이터 저장 중 오류가 발생했습니다.")

    def safe_input(self, prompt: str) -> str | None:
        """input() 함수를 예외 처리로 감싼 래퍼 메서드.
        Ctrl+C나 EOF 발생 시 현재 상태를 저장하고 None을 반환한다."""
        try:
            return self.input_func(prompt)
        except EOFError:
            print("\n입력이 종료되었습니다. 가능한 범위에서 저장 후 안전하게 종료합니다.")
            self.save_state(silent=True)
            return None
        except KeyboardInterrupt:
            print("\n사용자에 의해 중단되었습니다. 가능한 범위에서 저장 후 안전하게 종료합니다.")
            self.save_state(silent=True)
            return None

    def input_number(self, prompt: str, min_value: int, max_value: int) -> int | None:
        """숫자 입력을 받아 유효 범위 내의 정수를 반환한다.
        빈 입력, 숫자 아닌 입력, 범위 밖 입력 시 재입력을 유도한다."""
        while True:
            raw = self.safe_input(prompt)
            # Ctrl+C 또는 EOF로 중단된 경우 None을 위로 전달
            if raw is None:
                return None

            value = raw.strip()
            if value == "":
                print("빈 입력은 사용할 수 없습니다. 다시 입력해주세요.")
                continue

            # 문자열을 정수로 변환 시도
            try:
                number = int(value)
            except ValueError:
                print("숫자만 입력해주세요.")
                continue

            # 허용 범위 검증
            if not (min_value <= number <= max_value):
                print(f"{min_value}부터 {max_value} 사이의 숫자를 입력해주세요.")
                continue

            return number

    def select_quizzes(self) -> list[Quiz] | None:
        """풀 문제 수를 입력받고, 전체 퀴즈를 랜덤으로 섞어서 선택한 개수만큼 반환한다."""
        total_quizzes = len(self.quizzes)
        count = self.input_number(
            f"몇 문제를 풀까요? (1~{total_quizzes}): ",
            1,
            total_quizzes,
        )
        if count is None:
            return None

        # 원본 리스트를 복사한 뒤 셔플하여 랜덤 출제
        shuffled_quizzes = self.quizzes[:]
        random.shuffle(shuffled_quizzes)
        return shuffled_quizzes[:count]

    def delete_quiz(self) -> None:
        """퀴즈 목록을 보여준 뒤 번호를 입력받아 해당 퀴즈를 삭제한다."""
        if not self.quizzes:
            print("삭제할 퀴즈가 없습니다.")
            return
        self.list_quizzes()
        number = self.input_number(
            f"삭제할 퀴즈 번호를 입력하세요 (1~{len(self.quizzes)}): ",
            1,
            len(self.quizzes),
        )
        if number is None:
            return

        # pop으로 해당 인덱스의 퀴즈를 제거하고 삭제된 퀴즈를 반환받는다
        deleted_quiz = self.quizzes.pop(number - 1)
        self.save_state()
        print(f"'{deleted_quiz.question}' 문제가 삭제되었습니다.")

    def show_menu(self) -> None:
        """메인 메뉴를 콘솔에 출력한다."""
        print("\n=== 퀴즈 게임 ===")
        print("1. 퀴즈 풀기")
        print("2. 퀴즈 추가")
        print("3. 퀴즈 삭제")
        print("4. 퀴즈 목록 보기")
        print("5. 최고 점수 확인")
        print("6. 점수 기록 보기")
        print("7. 종료")

    def play_quiz(self) -> None:
        """퀴즈 풀기를 실행한다. 문제 수 선택 → 문제 풀이 → 점수 계산 → 기록 저장"""
        if not self.quizzes:
            print("등록된 퀴즈가 없습니다.")
            return

        selected_quizzes = self.select_quizzes()
        if selected_quizzes is None:
            return

        print(f"\n총 {len(selected_quizzes)}문제를 시작합니다.")
        score = 0

        # 선택된 퀴즈를 순회하며 문제 출력 → 정답 입력 → 채점
        for index, quiz in enumerate(selected_quizzes, start=1):
            quiz.display(index)
            result = self.get_answer_with_hint(quiz)
            # 중단(Ctrl+C/EOF) 시 기록 없이 복귀
            if result is None:
                return
            answer, used_hint = result

            if quiz.is_correct(answer):
                if used_hint:
                    print("정답입니다! 힌트를 사용해 점수는 획득하지 않습니다.")
                else:
                    print("정답입니다!")
                    score += 1
            else:
                print(f"오답입니다. 정답은 {quiz.answer}번입니다.")

        print(f"\n퀴즈 종료! 점수: {score}/{len(selected_quizzes)}")
        # 기록 저장 전에 이전 최고 점수를 먼저 조회
        previous_best = self.get_best_score()
        self.record_history(len(selected_quizzes), score)
        self.save_state(silent=True)
        # 최고 점수 갱신 여부 안내
        if previous_best is None or score > previous_best:
            print("최고 점수가 갱신되었습니다!")
        else:
            print(f"현재 최고 점수는 {previous_best}점입니다.")

    def add_quiz(self) -> None:
        """사용자로부터 문제, 힌트, 선택지 4개, 정답 번호를 입력받아 새 퀴즈를 추가한다."""
        print("\n=== 새 퀴즈 추가 ===")

        # 문제 입력 (빈 입력 시 재입력 유도)
        while True:
            question = self.safe_input("문제를 입력하세요: ")
            if question is None:
                return
            question = question.strip()
            if question == "":
                print("문제는 비어 있을 수 없습니다. 다시 입력해주세요.")
                continue
            break

        # 힌트 입력
        while True:
            hint = self.safe_input("힌트를 입력하세요: ")
            if hint is None:
                return
            hint = hint.strip()
            if hint == "":
                print("힌트는 비어 있을 수 없습니다. 다시 입력해주세요.")
                continue
            break

        # 선택지 4개 입력
        choices: list[str] = []
        for i in range(1, 5):
            while True:
                choice = self.safe_input(f"선택지 {i}를 입력하세요: ")
                if choice is None:
                    return
                choice = choice.strip()
                if choice == "":
                    print("선택지는 비어 있을 수 없습니다. 다시 입력해주세요.")
                    continue
                choices.append(choice)
                break

        # 정답 번호 입력
        answer = self.input_number("정답 번호를 입력하세요 (1~4): ", 1, 4)
        if answer is None:
            return

        # Quiz 객체 생성 — __post_init__에서 유효성 검증, 실패 시 except로 처리
        try:
            new_quiz = Quiz(question, choices, answer, hint)
        except ValueError as error:
            print(f"퀴즈를 추가할 수 없습니다: {error}")
            return

        self.quizzes.append(new_quiz)
        self.save_state()
        print("새 퀴즈가 저장되었습니다.")

    def list_quizzes(self) -> None:
        """등록된 전체 퀴즈 목록을 번호와 함께 출력한다."""
        if not self.quizzes:
            print("등록된 퀴즈가 없습니다.")
            return

        print("\n=== 퀴즈 목록 ===")
        for index, quiz in enumerate(self.quizzes, start=1):
            print(f"{index}. {quiz.question}")
            for choice_index, choice in enumerate(quiz.choices, start=1):
                print(f"   {choice_index}) {choice}")
            print(f"   정답: {quiz.answer}번")

    def get_best_score(self) -> int | None:
        """히스토리에서 최고 점수를 계산하여 반환한다. 기록이 없으면 None."""
        if not self.history:
            return None
        return max(record["score"] for record in self.history)

    def show_best_score(self) -> None:
        """현재 최고 점수를 콘솔에 출력한다."""
        best = self.get_best_score()
        if best is None:
            print("아직 퀴즈를 푼 기록이 없습니다.")
            return

        print(f"현재 최고 점수는 {best}점입니다.")

    def show_history(self) -> None:
        """전체 점수 기록(날짜, 문제 수, 점수)을 콘솔에 출력한다."""
        if not self.history:
            print("아직 저장된 점수 기록이 없습니다.")
            return

        print("\n=== 점수 기록 ===")
        for index, record in enumerate(self.history, start=1):
            print(
                f"{index}. 날짜/시간: {record['played_at']}, "
                f"문제 수: {record['question_count']}, 점수: {record['score']}"
            )

    def run(self) -> None:
        """메인 루프 — 메뉴를 출력하고 사용자 선택에 따라 각 기능을 실행한다."""
        while True:
            self.show_menu()
            choice = self.input_number("메뉴 번호를 입력하세요: ", 1, 7)
            # Ctrl+C 또는 EOF로 중단된 경우 종료
            if choice is None:
                print("프로그램을 종료합니다.")
                return

            if choice == 1:
                self.play_quiz()
            elif choice == 2:
                self.add_quiz()
            elif choice == 3:
                self.delete_quiz()
            elif choice == 4:
                self.list_quizzes()
            elif choice == 5:
                self.show_best_score()
            elif choice == 6:
                self.show_history()
            elif choice == 7:
                self.save_state(silent=True)
                print("프로그램을 종료합니다.")
                return
