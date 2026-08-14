"""Mini Redis REPL의 실행 진입점이다."""

from mini_redis import MiniRedis


def main():
    """사용자 입력을 반복 실행하고 종료 명령 또는 EOF에서 끝낸다."""
    redis = MiniRedis()
    while True:
        try:
            command_line = input("mini-redis> ")
        except EOFError:
            print()
            break
        result = redis.execute(command_line)
        if result is None:
            break
        if result:
            print(result)


if __name__ == "__main__":
    main()
