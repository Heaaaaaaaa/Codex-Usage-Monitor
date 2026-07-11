#!/usr/bin/env python3
import argparse
import plistlib
import shutil
import subprocess
import sys
from pathlib import Path

from ValidateBundleIdentifier import public_bundle_identifier_error

REQUIRED_PRIVACY_API = "NSPrivacyAccessedAPICategoryUserDefaults"
REQUIRED_PRIVACY_REASON = "CA92.1"


def result(ok: bool, title: str, detail: str = "") -> bool:
    prefix = "PASS" if ok else "FAIL"
    print(f"{prefix} {title}")
    if detail:
        print(f"     {detail}")
    return ok


def command_output(command: list[str]) -> tuple[int, str]:
    try:
        completed = subprocess.run(command, text=True, capture_output=True, check=False)
        output = (completed.stdout + completed.stderr).strip()
        return completed.returncode, output
    except OSError as error:
        return 127, str(error)


def has_tool(name: str) -> bool:
    return shutil.which(name) is not None


def developer_id_identity_error(identity: str) -> str | None:
    value = identity.strip()
    if not value or value == "-":
        return "Set SIGN_IDENTITY='Developer ID Application: Name (TEAMID)'."
    if not value.startswith("Developer ID Application: "):
        return "SIGN_IDENTITY must be a Developer ID Application certificate, not an Apple Development or ad-hoc identity."
    if "(" not in value or not value.endswith(")"):
        return "SIGN_IDENTITY should include the Apple Team ID, for example Developer ID Application: Name (TEAMID)."
    return None


def load_plist(path: Path) -> dict | None:
    try:
        with path.open("rb") as handle:
            value = plistlib.load(handle)
        return value if isinstance(value, dict) else None
    except (OSError, plistlib.InvalidFileException):
        return None


def check_identity(identity: str) -> bool:
    identity_error = developer_id_identity_error(identity)
    if identity_error is not None:
        return result(False, "Developer ID signing identity", identity_error)

    code, output = command_output(["security", "find-identity", "-v", "-p", "codesigning"])
    if code != 0:
        return result(False, "codesigning identities", output or "Could not read Keychain identities.")
    return result(
        identity in output,
        "Developer ID signing identity",
        f"Found '{identity}'." if identity in output else f"'{identity}' was not found in Keychain.",
    )


def notary_history_command(profile: str, keychain: str = "") -> list[str]:
    command = ["xcrun", "notarytool", "history", "--keychain-profile", profile]
    if keychain:
        command.extend(["--keychain", keychain])
    return command


def check_notary_profile(profile: str, network: bool, keychain: str = "") -> bool:
    if not profile:
        return result(False, "notary profile", "Set NOTARY_PROFILE to a stored notarytool keychain profile.")
    if keychain and not Path(keychain).is_file():
        return result(False, "notary keychain", f"Keychain file was not found: {keychain}")
    if not network:
        location = f" in '{keychain}'" if keychain else ""
        return result(True, "notary profile name", f"Using '{profile}'{location}. Run with CHECK_NOTARY=1 to validate with Apple.")

    code, output = command_output(notary_history_command(profile, keychain))
    return result(
        code == 0,
        "notary profile validation",
        "Apple notarytool accepted the profile." if code == 0 else output,
    )


def check_bundle_identifier(bundle_identifier: str) -> bool:
    error = public_bundle_identifier_error(bundle_identifier)
    return result(error is None, "public bundle identifier", bundle_identifier if error is None else error)


def check_app_metadata(
    app: Path,
    app_name: str,
    bundle_identifier: str,
    version: str,
    build: str,
    minimum_macos: str,
) -> bool:
    plist = load_plist(app / "Contents" / "Info.plist")
    if plist is None:
        return result(False, "app Info.plist", f"Could not read {app / 'Contents' / 'Info.plist'}.")

    expected = {
        "CFBundleExecutable": app_name,
        "CFBundleIdentifier": bundle_identifier,
        "CFBundleShortVersionString": version,
        "CFBundleVersion": build,
        "LSMinimumSystemVersion": minimum_macos,
    }
    mismatches = [
        f"{key}: expected {expected_value}, got {plist.get(key, '')}"
        for key, expected_value in expected.items()
        if plist.get(key, "") != expected_value
    ]
    return result(not mismatches, "app metadata matches release settings", "; ".join(mismatches) if mismatches else app.name)


def check_executable(app: Path, app_name: str) -> bool:
    executable = app / "Contents" / "MacOS" / app_name
    ok = executable.exists() and executable.is_file() and executable.stat().st_mode & 0o111 != 0
    return result(ok, "app executable exists", str(executable) if ok else f"Missing or not executable: {executable}")


def check_universal_binary(app: Path, app_name: str) -> bool:
    executable = app / "Contents" / "MacOS" / app_name
    code, output = command_output(["xcrun", "lipo", str(executable), "-verify_arch", "arm64", "x86_64"])
    return result(code == 0, "universal app binary", "arm64 + x86_64" if code == 0 else output)


def check_privacy_manifest(app: Path) -> bool:
    path = app / "Contents" / "Resources" / "PrivacyInfo.xcprivacy"
    manifest = load_plist(path)
    if manifest is None:
        return result(False, "bundled privacy manifest", f"Could not read {path}.")

    errors: list[str] = []
    if manifest.get("NSPrivacyTracking") is not False:
        errors.append("NSPrivacyTracking must be false")
    if manifest.get("NSPrivacyCollectedDataTypes") != []:
        errors.append("NSPrivacyCollectedDataTypes must be empty")
    if manifest.get("NSPrivacyTrackingDomains") != []:
        errors.append("NSPrivacyTrackingDomains must be empty")

    accessed_apis = manifest.get("NSPrivacyAccessedAPITypes", [])
    has_required_reason = any(
        isinstance(entry, dict)
        and entry.get("NSPrivacyAccessedAPIType") == REQUIRED_PRIVACY_API
        and REQUIRED_PRIVACY_REASON in entry.get("NSPrivacyAccessedAPITypeReasons", [])
        for entry in accessed_apis
    )
    if not has_required_reason:
        errors.append(f"missing {REQUIRED_PRIVACY_API} reason {REQUIRED_PRIVACY_REASON}")

    return result(not errors, "bundled privacy manifest", "; ".join(errors) if errors else "Local-only declaration present.")


def check_entitlements(path: Path) -> bool:
    entitlements = load_plist(path)
    if entitlements is None:
        return result(False, "release entitlements", f"Could not read {path}.")

    unexpected = [
        key for key, value in entitlements.items()
        if (key.startswith("com.apple.security.network") or key == "com.apple.security.app-sandbox") and value is True
    ]
    return result(
        not unexpected,
        "minimal release entitlements",
        "No sandbox or network entitlements enabled." if not unexpected else f"Unexpected entitlements: {', '.join(unexpected)}",
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Check public release prerequisites before notarization.")
    parser.add_argument("--app-name", default="CodexUsageMonitor")
    parser.add_argument("--sign-identity", required=True)
    parser.add_argument("--notary-profile", required=True)
    parser.add_argument("--notary-keychain", default="")
    parser.add_argument("--bundle-identifier", required=True)
    parser.add_argument("--app", required=True)
    parser.add_argument("--entitlements", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--minimum-macos", default="13.0")
    parser.add_argument("--check-notary-network", action="store_true")
    args = parser.parse_args()

    checks: list[bool] = []
    checks.append(result(has_tool("xcrun"), "xcrun available"))
    checks.append(result(has_tool("codesign"), "codesign available"))
    checks.append(result(has_tool("security"), "security available"))
    checks.append(result(has_tool("hdiutil"), "hdiutil available"))
    checks.append(check_bundle_identifier(args.bundle_identifier))
    checks.append(result(args.version.strip() != "", "version set", args.version))
    checks.append(result(args.build.strip() != "", "build number set", args.build))
    checks.append(result(args.minimum_macos.strip() != "", "minimum macOS set", args.minimum_macos))
    app = Path(args.app)
    entitlements = Path(args.entitlements)
    app_exists = result(app.exists(), "app bundle exists", args.app)
    entitlements_exist = result(entitlements.exists(), "release entitlements exist", args.entitlements)
    checks.append(app_exists)
    checks.append(entitlements_exist)

    if app_exists:
        checks.append(check_app_metadata(app, args.app_name, args.bundle_identifier, args.version, args.build, args.minimum_macos))
        checks.append(check_executable(app, args.app_name))
        checks.append(check_universal_binary(app, args.app_name))
        checks.append(check_privacy_manifest(app))
    if entitlements_exist:
        checks.append(check_entitlements(entitlements))

    checks.append(check_identity(args.sign_identity))

    checks.append(check_notary_profile(args.notary_profile, args.check_notary_network, args.notary_keychain))

    if all(checks):
        print("Ready for release-dmg-notarized.")
        return 0

    print("Public release preflight failed.")
    return 2


if __name__ == "__main__":
    sys.exit(main())
