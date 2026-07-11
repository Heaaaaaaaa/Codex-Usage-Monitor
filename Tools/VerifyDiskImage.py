#!/usr/bin/env python3
import argparse
import subprocess
import sys
import time
from pathlib import Path
from typing import Callable


CommandRunner = Callable[[list[str]], int]
Sleeper = Callable[[float], None]
Logger = Callable[[str], None]


def run_command(command: list[str]) -> int:
    return subprocess.run(command, check=False).returncode


def stderr_logger(message: str) -> None:
    print(message, file=sys.stderr)


def verify_disk_image(
    image: Path,
    attempts: int = 3,
    delay: float = 2.0,
    runner: CommandRunner = run_command,
    sleeper: Sleeper = time.sleep,
    logger: Logger = stderr_logger,
) -> int:
    if attempts < 1:
        raise ValueError("attempts must be at least 1")
    if delay < 0:
        raise ValueError("delay must not be negative")

    command = ["hdiutil", "verify", str(image)]
    last_exit_code = 1
    for attempt in range(1, attempts + 1):
        last_exit_code = runner(command)
        if last_exit_code == 0:
            return 0
        if attempt < attempts:
            wait = delay * attempt
            logger(
                f"DMG verification attempt {attempt} failed; "
                f"retrying in {wait:g}s"
            )
            sleeper(wait)
    return last_exit_code


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Verify a disk image, retrying transient macOS resource errors."
    )
    parser.add_argument("image", type=Path)
    parser.add_argument("--attempts", type=int, default=3)
    parser.add_argument("--delay", type=float, default=2.0)
    args = parser.parse_args()
    return verify_disk_image(args.image, attempts=args.attempts, delay=args.delay)


if __name__ == "__main__":
    sys.exit(main())
