"""REPL entry point for Mini Redis."""

from mini_redis import MiniRedis


def main():
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
