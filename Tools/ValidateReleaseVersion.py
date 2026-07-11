#!/usr/bin/env python3
import argparse
import plistlib
import re
import sys
from datetime import date
from pathlib import Path


SEMANTIC_VERSION = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
MAKE_ASSIGNMENT = re.compile(r"^([A-Z][A-Z0-9_]*)\s*\?=\s*(.*?)\s*$", re.MULTILINE)
CHANGELOG_HEADING = re.compile(r"^## ([^\s]+) - ([0-9]{4}-[0-9]{2}-[0-9]{2})$", re.MULTILINE)


def make_assignments(path: Path) -> dict[str, str]:
    return dict(MAKE_ASSIGNMENT.findall(path.read_text(encoding="utf-8")))


def release_version_errors(repo: Path, tag: str | None = None) -> tuple[str, str, list[str]]:
    errors: list[str] = []
    makefile = repo / "Makefile"
    info_plist = repo / "Info.plist"
    changelog = repo / "CHANGELOG.md"
    readme = repo / "README.md"
    publishing = repo / "PUBLISHING.md"

    required_files = [makefile, info_plist, changelog, readme, publishing]
    missing_files = [str(path.relative_to(repo)) for path in required_files if not path.is_file()]
    if missing_files:
        return "", "", [f"missing release file: {path}" for path in missing_files]

    assignments = make_assignments(makefile)
    version = assignments.get("VERSION", "").strip()
    build = assignments.get("BUILD_NUMBER", "").strip()

    if not SEMANTIC_VERSION.fullmatch(version):
        errors.append(f"Makefile VERSION must be semantic x.y.z, got {version or 'missing'}")
    if not build.isdigit() or int(build or "0") <= 0:
        errors.append(f"Makefile BUILD_NUMBER must be a positive integer, got {build or 'missing'}")

    try:
        with info_plist.open("rb") as handle:
            plist = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException) as error:
        plist = {}
        errors.append(f"Info.plist could not be read: {error}")

    if str(plist.get("CFBundleShortVersionString", "")) != version:
        errors.append("Info.plist CFBundleShortVersionString does not match Makefile VERSION")
    if str(plist.get("CFBundleVersion", "")) != build:
        errors.append("Info.plist CFBundleVersion does not match Makefile BUILD_NUMBER")

    headings = CHANGELOG_HEADING.findall(changelog.read_text(encoding="utf-8"))
    if not headings:
        errors.append("CHANGELOG.md has no dated release heading")
    else:
        latest_version, latest_date = headings[0]
        if latest_version != version:
            errors.append(f"latest changelog version {latest_version} does not match {version}")
        try:
            date.fromisoformat(latest_date)
        except ValueError:
            errors.append(f"latest changelog date is invalid: {latest_date}")

    expected_dmg = f"CodexUsageMonitor-{version}.dmg"
    for path in [readme, publishing]:
        if expected_dmg not in path.read_text(encoding="utf-8"):
            errors.append(f"{path.name} does not list {expected_dmg}")

    if tag is not None:
        expected_tag = f"v{version}"
        if tag != expected_tag:
            errors.append(f"release tag must be {expected_tag}, got {tag or 'empty'}")

    return version, build, errors


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate release version, build, changelog, docs, and optional tag.")
    parser.add_argument("--repo", default=".", help="Repository root")
    parser.add_argument("--tag", help="Optional release tag, expected to be vVERSION")
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    version, build, errors = release_version_errors(repo, args.tag)
    if errors:
        for error in errors:
            print(f"FAIL release version\n     {error}")
        return 2

    print(f"PASS release version\n     {version} (build {build})")
    if args.tag is not None:
        print(f"PASS release tag\n     {args.tag}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
