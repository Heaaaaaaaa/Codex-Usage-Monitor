#!/usr/bin/env python3
import argparse
import re
import stat
import subprocess
import sys
import zipfile
from pathlib import Path, PurePosixPath


MAX_SCANNED_FILE_BYTES = 8 * 1024 * 1024

FORBIDDEN_DIRECTORY_NAMES = {
    ".git",
    ".build",
    "__pycache__",
    "build",
    "deriveddata",
    "old-output",
    "xcuserdata",
}

FORBIDDEN_FILE_NAMES = {
    ".ds_store",
    ".env",
}

FORBIDDEN_SUFFIXES = {
    ".env",
    ".jsonl",
    ".key",
    ".log",
    ".mobileprovision",
    ".p12",
    ".pem",
    ".pyc",
}

SECRET_PATTERNS = [
    ("private key", re.compile(rb"-----BEGIN (?:(?:RSA|EC|OPENSSH) )?PRIVATE KEY-----")),
    ("GitHub token", re.compile(rb"gh[pousr]_[A-Za-z0-9_]{20,}")),
    ("OpenAI-style API key", re.compile(rb"sk-[A-Za-z0-9_-]{20,}")),
    ("AWS access key", re.compile(rb"AKIA[0-9A-Z]{16}")),
]


def git_output(repo: Path, arguments: list[str]) -> bytes:
    result = subprocess.run(
        ["git", "-C", str(repo), *arguments],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return result.stdout


def risky_path_reason(path: PurePosixPath) -> str | None:
    lowered_parts = [part.lower() for part in path.parts]
    if any(part in FORBIDDEN_DIRECTORY_NAMES for part in lowered_parts[:-1]):
        return "generated or private directory"

    name = path.name.lower()
    if name in FORBIDDEN_FILE_NAMES or name.startswith(".env."):
        return "private environment or metadata file"
    if any(name.endswith(suffix) for suffix in FORBIDDEN_SUFFIXES):
        return "credential, raw-log, or generated file type"
    if ".keychain" in name:
        return "keychain file"
    return None


def content_errors(data: bytes, label: str, home_path: bytes) -> list[str]:
    errors: list[str] = []
    if home_path and home_path in data:
        errors.append(f"{label} contains the current user's absolute home path")
    for description, pattern in SECRET_PATTERNS:
        if pattern.search(data):
            errors.append(f"{label} contains a possible {description}")
    return errors


def snapshot_errors(repo: Path) -> list[str]:
    repo = repo.resolve()
    errors: list[str] = []
    home_path = (str(Path.home()) + "/").encode("utf-8")
    tracked = [item for item in git_output(repo, ["ls-files", "-z"]).split(b"\0") if item]

    for raw_path in tracked:
        relative = raw_path.decode("utf-8", errors="replace")
        posix_path = PurePosixPath(relative)
        reason = risky_path_reason(posix_path)
        if reason:
            errors.append(f"tracked path {relative!r} is a {reason}")
            continue

        path = repo / relative
        if path.is_symlink():
            errors.append(f"tracked path {relative!r} is a symbolic link")
            continue
        if not path.is_file() or path.stat().st_size > MAX_SCANNED_FILE_BYTES:
            continue
        errors.extend(content_errors(path.read_bytes(), f"tracked file {relative!r}", home_path))

    return sorted(set(errors))


def history_errors(repo: Path) -> list[str]:
    repo = repo.resolve()
    errors: list[str] = []
    home_path = (str(Path.home()) + "/").encode("utf-8")

    author_rows = git_output(repo, ["log", "--all", "--format=%H%x09%ae"]).decode(
        "utf-8", errors="replace"
    )
    local_email_commits = [line for line in author_rows.splitlines() if line.lower().endswith(".local")]
    if local_email_commits:
        errors.append(
            f"{len(local_email_commits)} commit(s) use a machine-local author email; seed the public repository with a public or no-reply identity"
        )

    patch_history = git_output(repo, ["log", "--all", "-p", "--no-ext-diff", "--format=commit:%H"])
    errors.extend(content_errors(patch_history, "Git history", home_path))

    historical_paths = git_output(repo, ["log", "--all", "--name-only", "--format="]).decode(
        "utf-8", errors="replace"
    )
    for line in historical_paths.splitlines():
        if not line.strip():
            continue
        reason = risky_path_reason(PurePosixPath(line.strip()))
        if reason:
            errors.append(f"Git history contains {reason}: {line.strip()!r}")

    return sorted(set(errors))


def archive_errors(archive: Path, expected_prefix: str | None = None) -> list[str]:
    errors: list[str] = []
    home_path = (str(Path.home()) + "/").encode("utf-8")
    prefixes: set[str] = set()

    try:
        with zipfile.ZipFile(archive) as source_zip:
            for entry in source_zip.infolist():
                posix_path = PurePosixPath(entry.filename)
                if posix_path.is_absolute() or ".." in posix_path.parts:
                    errors.append(f"archive entry has an unsafe path: {entry.filename!r}")
                    continue
                if posix_path.parts:
                    prefixes.add(posix_path.parts[0])
                if expected_prefix and (not posix_path.parts or posix_path.parts[0] != expected_prefix):
                    errors.append(f"archive entry is outside {expected_prefix!r}: {entry.filename!r}")

                mode = (entry.external_attr >> 16) & 0o170000
                if stat.S_ISLNK(mode):
                    errors.append(f"archive entry is a symbolic link: {entry.filename!r}")
                    continue
                if entry.is_dir():
                    continue

                relative_parts = posix_path.parts[1:] if expected_prefix else posix_path.parts
                relative_path = PurePosixPath(*relative_parts)
                reason = risky_path_reason(relative_path)
                if reason:
                    errors.append(f"archive path {entry.filename!r} is a {reason}")
                    continue
                if entry.file_size <= MAX_SCANNED_FILE_BYTES:
                    errors.extend(
                        content_errors(source_zip.read(entry), f"archive file {entry.filename!r}", home_path)
                    )
    except (OSError, zipfile.BadZipFile) as error:
        return [f"could not read source archive {archive}: {error}"]

    if expected_prefix and prefixes != {expected_prefix}:
        errors.append(f"archive root must be exactly {expected_prefix!r}, found {sorted(prefixes)!r}")
    return sorted(set(errors))


def has_license(repo: Path) -> bool:
    tracked = git_output(repo, ["ls-files", "LICENSE*", "COPYING*", "NOTICE*"])
    return bool(tracked.strip())


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit a source snapshot before public publication.")
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--check-history", action="store_true")
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--archive-prefix")
    args = parser.parse_args()

    errors = snapshot_errors(args.repo)
    if args.check_history:
        errors.extend(history_errors(args.repo))
    if args.archive:
        errors.extend(archive_errors(args.archive, args.archive_prefix))

    errors = sorted(set(errors))
    if errors:
        print("FAIL public source audit", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1

    print("PASS public source snapshot")
    if args.archive:
        print(f"     archive: {args.archive}")
    print(f"     license: {'present' if has_license(args.repo) else 'not selected (default copyright applies)'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
