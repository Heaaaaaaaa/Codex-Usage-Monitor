#!/usr/bin/env python3
import json
import plistlib
import subprocess
import sys
import tempfile
import zipfile
from datetime import datetime, timezone
from pathlib import Path

from MakeDemoFixture import DEMO_MARKER, DEMO_SESSIONS, build_demo_fixture
from MakeReleaseManifest import pricing_metadata
from ReleasePreflight import developer_id_identity_error, notary_history_command
from ValidateBundleIdentifier import public_bundle_identifier_error
from ValidatePublicSource import archive_errors, history_errors, snapshot_errors
from ValidateReleaseVersion import release_version_errors
from VerifyDiskImage import verify_disk_image


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def require_equal(actual, expected, message: str) -> None:
    if actual != expected:
        raise AssertionError(f"{message}: expected {expected!r}, got {actual!r}")


def test_developer_id_identity_validation() -> None:
    require_equal(
        developer_id_identity_error("Developer ID Application: Example Dev (TEAMID)"),
        None,
        "Developer ID identity accepted",
    )
    require(
        "Set SIGN_IDENTITY" in (developer_id_identity_error("-") or ""),
        "missing identity explains SIGN_IDENTITY",
    )
    require(
        "Developer ID Application" in (developer_id_identity_error("Apple Development: Example Dev (TEAMID)") or ""),
        "development identity rejected",
    )
    require(
        "Team ID" in (developer_id_identity_error("Developer ID Application: Example Dev") or ""),
        "identity without team id rejected",
    )


def test_public_bundle_identifier_validation() -> None:
    require_equal(public_bundle_identifier_error("dev.codexusage.monitor"), None, "public bundle id accepted")
    require(public_bundle_identifier_error("local.codex.usagemonitor") is not None, "local bundle id rejected")
    require(public_bundle_identifier_error("com.example") is not None, "generic example bundle id rejected")
    require(public_bundle_identifier_error("com.example.codex usage") is not None, "invalid characters rejected")


def test_menu_bar_bundle_metadata() -> None:
    repo = Path(__file__).resolve().parent.parent
    with (repo / "Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    makefile = (repo / "Makefile").read_text(encoding="utf-8")
    launcher = (repo / "Sources/Launcher.swift").read_text(encoding="utf-8")
    icon_tool = (repo / "Tools/MakeAppIcon.py").read_text(encoding="utf-8")

    require(info.get("LSUIElement") is True, "menu-bar app must be an LSUIElement agent")
    require("Print :LSUIElement" in makefile, "release verification must enforce LSUIElement")
    required_snippets = [
        "NSStatusItem.squareLength",
        "private let popover = NSPopover()",
        "popover.behavior = .transient",
        'forResource: "MenuBarIcon"',
        "MENU_BAR_ICON := Resources/MenuBarIcon.png",
        'Contents/Resources/MenuBarIcon.png',
        "draw_usage_mark",
    ]
    combined = makefile + launcher + icon_tool
    for snippet in required_snippets:
        require(snippet in combined, f"menu-bar popover safeguard missing: {snippet}")
    require("NSPanel(" not in launcher, "dashboard must be hosted in a menu-bar popover, not a utility panel")
    require((repo / "Resources/MenuBarIcon.png").is_file(), "menu-bar template icon must be generated and tracked")


def test_strict_concurrency_gate() -> None:
    repo = Path(__file__).resolve().parent.parent
    makefile = (repo / "Makefile").read_text(encoding="utf-8")
    required_snippets = [
        "verify-concurrency:",
        "-typecheck -O",
        "-warn-concurrency",
        "-strict-concurrency=complete",
        "-warnings-as-errors",
        "Tools/RunTests.swift",
        "Tools/DumpSummary.swift",
        "check: verify-version verify-concurrency",
    ]
    for snippet in required_snippets:
        require(snippet in makefile, f"strict concurrency gate missing: {snippet}")


def test_parse_cache_safeguards() -> None:
    repo = Path(__file__).resolve().parent.parent
    makefile = (repo / "Makefile").read_text(encoding="utf-8")
    usage_data = (repo / "Sources/UsageData.swift").read_text(encoding="utf-8")
    swift_tests = (repo / "Tools/RunTests.swift").read_text(encoding="utf-8")
    diagnostic = (repo / "Tools/DumpSummary.swift").read_text(encoding="utf-8")
    combined = makefile + usage_data + swift_tests + diagnostic
    required_snippets = [
        "DIAGNOSTIC_CACHE :=",
        '"$(DIAGNOSTIC)" "$(abspath $(DIAGNOSTIC_CACHE))"',
        "CommandLine.arguments.dropFirst().first",
        "retitledParseCache",
        "mergedParseCache",
        "Darwin.lockf",
        "session index changes do not invalidate parsed token files",
        "package: all",
        "package-dmg: all",
    ]
    for snippet in required_snippets:
        require(snippet in combined, f"parse cache safeguard missing: {snippet}")


def test_release_version_validation() -> None:
    repo = Path(__file__).resolve().parent.parent
    version, build, errors = release_version_errors(repo, "v0.4.2")
    require_equal(version, "0.4.2", "release version")
    require_equal(build, "6", "release build")
    require_equal(errors, [], "live release metadata validates")

    _, _, bad_tag_errors = release_version_errors(repo, "v9.9.9")
    require(any("release tag must be v0.4.2" in error for error in bad_tag_errors), "mismatched release tag rejected")

    with tempfile.TemporaryDirectory() as folder:
        fixture = Path(folder)
        (fixture / "Makefile").write_text("VERSION ?= 1.2.3\nBUILD_NUMBER ?= 7\n", encoding="utf-8")
        with (fixture / "Info.plist").open("wb") as handle:
            plistlib.dump({"CFBundleShortVersionString": "1.2.2", "CFBundleVersion": "6"}, handle)
        (fixture / "CHANGELOG.md").write_text("# Changelog\n\n## 1.2.2 - 2026-07-11\n", encoding="utf-8")
        (fixture / "README.md").write_text("No release artifact listed.\n", encoding="utf-8")
        (fixture / "PUBLISHING.md").write_text("No release artifact listed.\n", encoding="utf-8")
        _, _, fixture_errors = release_version_errors(fixture, "v1.2.3")
        require(len(fixture_errors) >= 4, "inconsistent release fixture rejected")


def test_notary_keychain_command() -> None:
    require_equal(
        notary_history_command("CodexUsageMonitorCI"),
        ["xcrun", "notarytool", "history", "--keychain-profile", "CodexUsageMonitorCI"],
        "default notary history command",
    )
    require_equal(
        notary_history_command("CodexUsageMonitorCI", "/tmp/release.keychain-db"),
        [
            "xcrun",
            "notarytool",
            "history",
            "--keychain-profile",
            "CodexUsageMonitorCI",
            "--keychain",
            "/tmp/release.keychain-db",
        ],
        "file keychain is forwarded to notarytool",
    )


def test_publish_workflow_safeguards() -> None:
    repo = Path(__file__).resolve().parent.parent
    workflow = (repo / ".github/workflows/publish-release.yml").read_text(encoding="utf-8")
    required_snippets = [
        'tags:\n      - "v*"',
        "contents: write",
        "environment: release",
        "release-readiness:",
        "signing_available",
        "available=false",
        "needs: release-readiness",
        "if: needs.release-readiness.outputs.signing_available == 'true'",
        "Tools/ValidateReleaseVersion.py",
        "APPLE_DEVELOPER_ID_P12_BASE64",
        "NOTARY_KEYCHAIN=",
        "make release-dmg-notarized",
        "actions/upload-artifact@v6",
        "gh release create",
        "--verify-tag",
        "if: always()",
        "security delete-keychain",
    ]
    for snippet in required_snippets:
        require(snippet in workflow, f"publish workflow missing safeguard: {snippet}")
    require("pull_request:" not in workflow, "publishing workflow must not expose release secrets to pull requests")


def test_pricing_manifest_metadata() -> None:
    repo = Path(__file__).resolve().parent.parent
    pricing = pricing_metadata(repo)
    require_equal(pricing["verifiedDate"], "2026-07-10", "pricing verification date")
    require_equal(len(pricing["rates"]), 10, "manifest includes only shipped default rates")
    require_equal(pricing["rates"][0]["model"], "gpt-5.6-sol", "manifest includes GPT-5.6 Sol")
    require("cache writes" in pricing["limitations"], "manifest discloses cache-write limitation")
    pro_rate = next(rate for rate in pricing["rates"] if rate["model"] == "gpt-5.5-pro")
    require_equal(pro_rate["cachedInputPerMillion"], 0.0, "manifest does not invent a Pro cached-input rate")


def test_demo_fixture_generation() -> None:
    now = datetime(2026, 7, 11, 12, 0, tzinfo=timezone.utc)
    with tempfile.TemporaryDirectory() as folder:
        root = Path(folder) / "demo-codex-home"
        summary = build_demo_fixture(root, now)
        require_equal(summary["sessions"], len(DEMO_SESSIONS), "demo session count")
        require_equal(summary["events"], len(DEMO_SESSIONS), "demo event count")
        require((root / DEMO_MARKER).is_file(), "demo output includes replacement safety marker")
        require((root / "sessions").is_dir(), "demo sessions directory exists")
        require((root / "archived_sessions").is_dir(), "demo archived sessions directory exists")

        files = sorted(root.rglob("*.jsonl"))
        require_equal(len(files), len(DEMO_SESSIONS) + 1, "demo JSONL file count")
        index_rows = [json.loads(line) for line in (root / "session_index.jsonl").read_text(encoding="utf-8").splitlines()]
        require_equal(len(index_rows), len(DEMO_SESSIONS), "demo index row count")
        require(all(row["thread_name"] for row in index_rows), "every demo chat has a title")

        token_events = []
        models = set()
        projects = set()
        for path in files:
            for line in path.read_text(encoding="utf-8").splitlines():
                row = json.loads(line)
                if row.get("type") == "session_meta":
                    models.add(row["model"])
                    projects.add(row["cwd"])
                if row.get("payload", {}).get("type") == "token_count":
                    token_events.append(row)

        require_equal(len(token_events), len(DEMO_SESSIONS), "one token event per demo chat")
        require_equal(models, {"gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"}, "demo uses priced models")
        require_equal(
            projects,
            {"/Users/demo/Projects/Atlas", "/Users/demo/Projects/Launchpad", "/Users/demo/Projects/Northstar"},
            "demo uses synthetic project paths",
        )
        require_equal(sum("rate_limits" in row["payload"] for row in token_events), 1, "one current rate-limit snapshot")
        require(not any("auth" in path.name.lower() or "credential" in path.name.lower() for path in root.rglob("*")), "demo includes no auth-like files")

        try:
            build_demo_fixture(root, now)
            raise AssertionError("unmarked replacement guard was not enforced")
        except FileExistsError:
            pass
        rebuilt = build_demo_fixture(root, now, replace=True)
        require_equal(rebuilt["tokens"], summary["tokens"], "marked demo regeneration is deterministic")


def test_public_support_metadata() -> None:
    repo = Path(__file__).resolve().parent.parent
    support = (repo / "SUPPORT.md").read_text(encoding="utf-8")
    security = (repo / "SECURITY.md").read_text(encoding="utf-8")
    bug_template = (repo / ".github/ISSUE_TEMPLATE/bug_report.yml").read_text(encoding="utf-8")
    privacy = (repo / "PRIVACY.md").read_text(encoding="utf-8")
    readme = (repo / "README.md").read_text(encoding="utf-8")
    publishing = (repo / "PUBLISHING.md").read_text(encoding="utf-8")

    require("Copy Report" in support, "support guide explains the built-in diagnostic workflow")
    require("raw Codex logs" in support, "support guide warns against sharing raw logs")
    require("private vulnerability reporting" in security.lower(), "security guide provides a private reporting route")
    require("Do not attach raw Codex JSONL logs" in bug_template, "bug template protects local logs")
    require("redacts custom folder paths" in privacy, "privacy policy discloses diagnostic path redaction")
    require("[Support](SUPPORT.md)" in readme, "README links support guidance")
    require("[Security](SECURITY.md)" in readme, "README links security guidance")
    require("Do not push the development repository history" in publishing, "publishing guide protects development history")


def test_public_source_safety() -> None:
    repo = Path(__file__).resolve().parent.parent
    require_equal(snapshot_errors(repo), [], "current tracked snapshot is public-safe")

    with tempfile.TemporaryDirectory() as folder:
        fixture = Path(folder)
        subprocess.run(["git", "init", "--quiet", str(fixture)], check=True)
        (fixture / "private.txt").write_text(f"{Path.home()}/private/source\n", encoding="utf-8")
        subprocess.run(["git", "-C", str(fixture), "add", "private.txt"], check=True)
        subprocess.run(
            [
                "git",
                "-C",
                str(fixture),
                "-c",
                "commit.gpgsign=false",
                "-c",
                "user.name=Fixture Author",
                "-c",
                "user.email=fixture@build-machine.local",
                "commit",
                "--quiet",
                "-m",
                "Add unsafe fixture",
            ],
            check=True,
        )

        known_history_errors = history_errors(fixture)
        require(
            any("machine-local author email" in error for error in known_history_errors),
            "development history flags local commit identity",
        )
        require(
            any("absolute home path" in error for error in known_history_errors),
            "development history flags removed local paths",
        )

        safe_archive = fixture / "safe.zip"
        with zipfile.ZipFile(safe_archive, "w") as source_zip:
            source_zip.writestr("CodexUsageMonitor-0.4.1/README.md", "Public source\n")
        require_equal(
            archive_errors(safe_archive, "CodexUsageMonitor-0.4.1"),
            [],
            "safe source archive accepted",
        )

        unsafe_archive = fixture / "unsafe.zip"
        fake_token = "ghp_" + ("A" * 24)
        with zipfile.ZipFile(unsafe_archive, "w") as source_zip:
            source_zip.writestr("CodexUsageMonitor-0.4.1/.env", "PRIVATE=1\n")
            source_zip.writestr("CodexUsageMonitor-0.4.1/README.md", fake_token)
        unsafe_errors = archive_errors(unsafe_archive, "CodexUsageMonitor-0.4.1")
        require(any("environment" in error for error in unsafe_errors), "source archive rejects environment files")
        require(any("GitHub token" in error for error in unsafe_errors), "source archive rejects token patterns")


def test_runtime_panel_verifier() -> None:
    repo = Path(__file__).resolve().parent.parent
    makefile = (repo / "Makefile").read_text(encoding="utf-8")
    verifier = (repo / "Tools/VerifyRuntimePanel.swift").read_text(encoding="utf-8")
    required_snippets = [
        "verify-runtime: all $(RUNTIME_VERIFIER)",
        "ModuleCache-runtime",
        '-module-cache-path "$(RUNTIME_MODULE_CACHE)"',
        "CGWindowListCopyWindowInfo",
        "width.doubleValue >= 250",
        'withBundleIdentifier: "com.apple.finder"',
        "createsNewApplicationInstance = true",
        "kAEReopenApplication",
        "NSAppleEventDescriptor(processIdentifier:",
        "unexpectedBundle",
        "panelDidNotHide",
        "launchErrorDescription",
        "NSUnderlyingErrorKey",
        "previousFrontmostApp.activate(options: [])",
    ]
    combined = makefile + verifier
    for snippet in required_snippets:
        require(snippet in combined, f"runtime panel verifier missing: {snippet}")
    require("kCGWindowLayer" not in verifier, "runtime verifier must not exclude AppKit popover window layers")


def test_disk_image_verifier_retries() -> None:
    repo = Path(__file__).resolve().parent.parent
    makefile = (repo / "Makefile").read_text(encoding="utf-8")
    require(
        'python3 "$(DMG_VERIFIER)" "$(RELEASE_DMG)"' in makefile,
        "release verification must use the retrying DMG verifier",
    )

    exit_codes = iter([1, 0])
    commands: list[list[str]] = []
    delays: list[float] = []
    messages: list[str] = []

    def runner(command: list[str]) -> int:
        commands.append(command)
        return next(exit_codes)

    result = verify_disk_image(
        Path("/tmp/release.dmg"),
        attempts=3,
        delay=0.25,
        runner=runner,
        sleeper=delays.append,
        logger=messages.append,
    )
    require_equal(result, 0, "transient DMG verification recovers")
    require_equal(len(commands), 2, "DMG verification retries once")
    require_equal(delays, [0.25], "DMG verification uses bounded backoff")
    require_equal(len(messages), 1, "DMG retry is reported")
    require_equal(
        commands[0],
        ["hdiutil", "verify", "/tmp/release.dmg"],
        "DMG verifier command",
    )


def main() -> int:
    tests = [
        ("Developer ID identity validation", test_developer_id_identity_validation),
        ("public bundle identifier validation", test_public_bundle_identifier_validation),
        ("menu bar bundle metadata", test_menu_bar_bundle_metadata),
        ("strict concurrency gate", test_strict_concurrency_gate),
        ("parse cache safeguards", test_parse_cache_safeguards),
        ("release version validation", test_release_version_validation),
        ("notary keychain command", test_notary_keychain_command),
        ("publish workflow safeguards", test_publish_workflow_safeguards),
        ("pricing manifest metadata", test_pricing_manifest_metadata),
        ("demo fixture generation", test_demo_fixture_generation),
        ("public support metadata", test_public_support_metadata),
        ("public source safety", test_public_source_safety),
        ("runtime panel verifier", test_runtime_panel_verifier),
        ("disk image verifier retries", test_disk_image_verifier_retries),
    ]
    failures: list[str] = []
    for name, test in tests:
        try:
            test()
            print(f"PASS {name}")
        except Exception as error:
            message = f"FAIL {name}: {error}"
            failures.append(message)
            print(message)

    if failures:
        return 1
    print(f"All {len(tests)} release tool tests passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
