#!/usr/bin/env python3
import argparse
import hashlib
import json
import plistlib
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path


REQUIRED_PRIVACY_API = "NSPrivacyAccessedAPICategoryUserDefaults"
REQUIRED_PRIVACY_REASON = "CA92.1"
REQUIRED_ARCHITECTURES = ["arm64", "x86_64"]
MANIFEST_SCHEMA_VERSION = 2
PRICING_SOURCE = Path("Sources/UsageData.swift")
SIGNATURE_POLICIES = ("any", "developer-id")


def sha256(path: Path) -> str:
    hasher = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def git_commit(repo: Path) -> str:
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "--short", "HEAD"],
            cwd=repo,
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return "unknown"


def git_dirty(repo: Path) -> bool:
    try:
        status = subprocess.check_output(
            ["git", "status", "--short"],
            cwd=repo,
            text=True,
            stderr=subprocess.DEVNULL,
        )
        return bool(status.strip())
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False


def command_output(command: list[str]) -> str:
    try:
        return subprocess.check_output(command, text=True, stderr=subprocess.STDOUT).strip()
    except (subprocess.CalledProcessError, FileNotFoundError) as error:
        output = getattr(error, "output", "") or str(error)
        raise SystemExit(output.strip())


def executable_architectures(executable: Path) -> list[str]:
    if not executable.exists():
        raise SystemExit(f"missing executable {executable}")
    archs = sorted(command_output(["xcrun", "lipo", "-archs", str(executable)]).split())
    missing = [arch for arch in REQUIRED_ARCHITECTURES if arch not in archs]
    if missing:
        raise SystemExit(f"{executable.name} missing architecture(s): {', '.join(missing)}")
    return archs


def parse_key_value_output(output: str) -> dict[str, list[str]]:
    values: dict[str, list[str]] = {}
    for raw_line in output.splitlines():
        line = raw_line.strip()
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        values.setdefault(key, []).append(value)
    return values


def code_signature_metadata(app: Path) -> dict:
    command_output(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app)])
    display = command_output(["codesign", "--display", "--verbose=4", str(app)])
    values = parse_key_value_output(display)
    flags_match = re.search(r"flags=(0x[0-9a-fA-F]+)\(([^)]*)\)", display)
    flags = []
    flags_hex = None
    if flags_match:
        flags_hex = flags_match.group(1)
        flags = [flag.strip() for flag in flags_match.group(2).split(",") if flag.strip()]

    return {
        "valid": True,
        "identifier": values.get("Identifier", [""])[0],
        "format": values.get("Format", [""])[0],
        "signature": values.get("Signature", [""])[0],
        "teamIdentifier": values.get("TeamIdentifier", [""])[0],
        "cdHash": values.get("CDHash", [""])[0],
        "authorities": values.get("Authority", []),
        "flags": flags,
        "flagsHex": flags_hex,
        "hardenedRuntime": "runtime" in flags,
    }


def require_signature_policy(signature: dict, policy: str) -> None:
    if policy == "any":
        return
    if policy != "developer-id":
        raise SystemExit(f"unsupported signature policy {policy}")

    authorities = signature.get("authorities", [])
    if signature.get("signature") == "adhoc":
        raise SystemExit("Developer ID release must not use an ad-hoc app signature")
    if not signature.get("teamIdentifier") or signature.get("teamIdentifier") == "not set":
        raise SystemExit("Developer ID release must include a TeamIdentifier")
    if not any(authority.startswith("Developer ID Application:") for authority in authorities):
        raise SystemExit("Developer ID release must include a Developer ID Application authority")
    if signature.get("hardenedRuntime") is not True:
        raise SystemExit("Developer ID release must use hardened runtime")


def artifact_payload(path: Path, kind: str) -> dict:
    return {
        "kind": kind,
        "file": path.name,
        "sizeBytes": path.stat().st_size,
        "sha256": sha256(path),
    }


def bundle_plist(app: Path) -> dict:
    plist_path = app / "Contents" / "Info.plist"
    with plist_path.open("rb") as handle:
        return plistlib.load(handle)


def privacy_plist(resources: Path) -> dict:
    privacy_path = resources / "PrivacyInfo.xcprivacy"
    if not privacy_path.exists():
        return {}
    with privacy_path.open("rb") as handle:
        return plistlib.load(handle)


def required_reason_apis(resources: Path) -> list[dict]:
    manifest = privacy_plist(resources)
    api_entries = manifest.get("NSPrivacyAccessedAPITypes", [])
    if not isinstance(api_entries, list):
        return []

    required_apis: list[dict] = []
    for entry in api_entries:
        if not isinstance(entry, dict):
            continue
        category = entry.get("NSPrivacyAccessedAPIType")
        reasons = entry.get("NSPrivacyAccessedAPITypeReasons", [])
        if isinstance(category, str) and isinstance(reasons, list):
            required_apis.append({
                "category": category,
                "reasons": sorted(reason for reason in reasons if isinstance(reason, str)),
            })

    return sorted(required_apis, key=lambda api: api["category"])


def swift_string_constant(source: str, name: str) -> str:
    patterns = [
        rf'static let {re.escape(name)} = "([^"]+)"',
        rf'static let {re.escape(name)} = URL\(string: "([^"]+)"\)!',
    ]
    match = next((found for pattern in patterns if (found := re.search(pattern, source))), None)
    if not match:
        raise SystemExit(f"missing pricing constant {name}")
    return match.group(1)


def default_rates(source: str) -> list[dict]:
    pattern = re.compile(
        r'ModelRate\(model: "([^"]+)", inputPerMillion: ([0-9.]+), '
        r'cachedInputPerMillion: ([0-9.]+), outputPerMillion: ([0-9.]+)\)'
    )
    rates = [
        {
            "model": match.group(1),
            "inputPerMillion": float(match.group(2)),
            "cachedInputPerMillion": float(match.group(3)),
            "outputPerMillion": float(match.group(4)),
        }
        for match in pattern.finditer(source)
    ]
    if not rates:
        raise SystemExit("no default model rates found")
    return rates


def pricing_metadata(repo: Path) -> dict:
    source_path = repo / PRICING_SOURCE
    source = source_path.read_text(encoding="utf-8")
    return {
        "profile": swift_string_constant(source, "defaultRateProfileName"),
        "source": swift_string_constant(source, "defaultRateSourceName"),
        "sourceURL": swift_string_constant(source, "defaultRateSourceURL"),
        "verifiedDate": swift_string_constant(source, "defaultRateVerifiedDate"),
        "limitations": swift_string_constant(source, "defaultRateLimitations"),
        "unit": "USD per 1M tokens",
        "rates": default_rates(source),
    }


def require_metadata(actual: str, expected: str, name: str) -> None:
    if actual != expected:
        raise SystemExit(f"{name} mismatch: expected {expected}, got {actual}")


def build_manifest(args: argparse.Namespace) -> dict:
    app = Path(args.app)
    plist = bundle_plist(app)
    executable = app / "Contents" / "MacOS" / args.app_name
    resources = app / "Contents" / "Resources"
    zip_path = Path(args.zip)
    dmg_path = Path(args.dmg)
    require_metadata(plist.get("CFBundleExecutable", ""), args.app_name, "CFBundleExecutable")
    require_metadata(plist.get("CFBundleIdentifier", ""), args.bundle_identifier, "CFBundleIdentifier")
    require_metadata(plist.get("CFBundleShortVersionString", ""), args.version, "CFBundleShortVersionString")
    require_metadata(plist.get("CFBundleVersion", ""), args.build, "CFBundleVersion")
    require_metadata(plist.get("LSMinimumSystemVersion", ""), args.minimum_macos, "LSMinimumSystemVersion")

    return {
        "schemaVersion": MANIFEST_SCHEMA_VERSION,
        "appName": args.app_name,
        "bundleIdentifier": plist.get("CFBundleIdentifier", args.bundle_identifier),
        "version": plist.get("CFBundleShortVersionString", args.version),
        "build": plist.get("CFBundleVersion", args.build),
        "gitCommit": git_commit(Path(args.repo)),
        "gitDirty": git_dirty(Path(args.repo)),
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "minimumMacOS": plist.get("LSMinimumSystemVersion", args.minimum_macos),
        "signaturePolicy": args.signature_policy,
        "architectures": executable_architectures(executable),
        "signature": code_signature_metadata(app),
        "privacy": {
            "localOnly": True,
            "reads": [
                "selected Codex log folder/sessions",
                "selected Codex log folder/archived_sessions",
                "selected Codex log folder/session_index.jsonl",
            ],
            "writes": [
                "~/Library/Caches/CodexUsageMonitor",
            ],
            "doesNotRead": ["Codex auth files"],
            "network": False,
            "requiredReasonAPIs": required_reason_apis(resources),
        },
        "pricing": pricing_metadata(Path(args.repo)),
        "bundle": {
            "file": app.name,
            "executable": executable.name,
            "hasPrivacyManifest": (resources / "PrivacyInfo.xcprivacy").exists(),
            "hasIcon": (resources / "AppIcon.icns").exists(),
        },
        "artifacts": [
            artifact_payload(zip_path, "zip"),
            artifact_payload(dmg_path, "dmg"),
        ],
    }


def require_clean_release(manifest: dict, repo: Path) -> None:
    if manifest.get("gitDirty") is not False:
        raise SystemExit("manifest gitDirty must be false for a public release")
    if git_commit(repo) == "unknown":
        raise SystemExit("cannot require a clean release outside a readable git repository")
    if git_dirty(repo):
        raise SystemExit("working tree must be clean for a public release")


def verify_manifest(path: Path, repo: Path, strict_repo: bool, require_clean: bool, signature_policy: str) -> None:
    manifest = json.loads(path.read_text(encoding="utf-8"))
    folder = path.parent
    required_top_level = [
        "schemaVersion",
        "appName",
        "bundleIdentifier",
        "version",
        "build",
        "artifacts",
    ]
    for key in required_top_level:
        if key not in manifest:
            raise SystemExit(f"manifest missing {key}")

    schema_version = manifest.get("schemaVersion")
    if not isinstance(schema_version, int) or schema_version < 1 or schema_version > MANIFEST_SCHEMA_VERSION:
        raise SystemExit(f"unsupported manifest schemaVersion {schema_version}")

    app = Path(path.parent) / f"{manifest['appName']}.app"
    if app.exists():
        plist = bundle_plist(app)
        require_metadata(plist.get("CFBundleIdentifier", ""), manifest["bundleIdentifier"], "CFBundleIdentifier")
        require_metadata(plist.get("CFBundleShortVersionString", ""), manifest["version"], "CFBundleShortVersionString")
        require_metadata(plist.get("CFBundleVersion", ""), manifest["build"], "CFBundleVersion")
        require_metadata(plist.get("LSMinimumSystemVersion", ""), manifest.get("minimumMacOS", ""), "LSMinimumSystemVersion")
        executable = app / "Contents" / "MacOS" / manifest["appName"]
        actual_archs = executable_architectures(executable)
        if sorted(manifest.get("architectures", [])) != actual_archs:
            raise SystemExit("manifest architectures do not match app executable")
        if schema_version >= 2 and manifest.get("signature") != code_signature_metadata(app):
            raise SystemExit("manifest signature does not match app bundle")

    archs = manifest.get("architectures", [])
    if not isinstance(archs, list):
        raise SystemExit("manifest architectures must be an array")
    missing_archs = [arch for arch in REQUIRED_ARCHITECTURES if arch not in archs]
    if missing_archs:
        raise SystemExit(f"manifest architectures missing {', '.join(missing_archs)}")

    if schema_version >= 2:
        signature = manifest.get("signature")
        if not isinstance(signature, dict):
            raise SystemExit("manifest signature must be an object")
        required_signature_keys = ["valid", "identifier", "format", "signature", "teamIdentifier", "cdHash", "authorities", "flags", "hardenedRuntime"]
        for key in required_signature_keys:
            if key not in signature:
                raise SystemExit(f"manifest signature missing {key}")
        if signature.get("valid") is not True:
            raise SystemExit("manifest signature.valid must be true")
        if not signature.get("cdHash"):
            raise SystemExit("manifest signature.cdHash must be set")
        manifest_policy = manifest.get("signaturePolicy", "any")
        if manifest_policy not in SIGNATURE_POLICIES:
            raise SystemExit(f"unsupported manifest signaturePolicy {manifest_policy}")
        effective_policy = signature_policy if signature_policy != "any" else manifest_policy
        require_signature_policy(signature, effective_policy)

    for artifact in manifest["artifacts"]:
        artifact_path = folder / artifact["file"]
        if not artifact_path.exists():
            raise SystemExit(f"missing artifact {artifact_path}")
        actual_size = artifact_path.stat().st_size
        actual_hash = sha256(artifact_path)
        if actual_size != artifact["sizeBytes"]:
            raise SystemExit(f"size mismatch for {artifact_path.name}")
        if actual_hash != artifact["sha256"]:
            raise SystemExit(f"sha256 mismatch for {artifact_path.name}")

    privacy = manifest.get("privacy", {})
    if privacy.get("localOnly") is not True:
        raise SystemExit("manifest privacy.localOnly must be true")
    if privacy.get("network") is not False:
        raise SystemExit("manifest privacy.network must be false")
    required_reason_apis = privacy.get("requiredReasonAPIs", [])
    has_required_reason = any(
        api.get("category") == REQUIRED_PRIVACY_API
        and REQUIRED_PRIVACY_REASON in api.get("reasons", [])
        for api in required_reason_apis
        if isinstance(api, dict)
    )
    if not has_required_reason:
        raise SystemExit(f"manifest privacy missing {REQUIRED_PRIVACY_API} reason {REQUIRED_PRIVACY_REASON}")

    pricing = manifest.get("pricing", {})
    required_pricing_keys = ["profile", "source", "sourceURL", "verifiedDate", "limitations", "unit", "rates"]
    for key in required_pricing_keys:
        if key not in pricing:
            raise SystemExit(f"manifest pricing missing {key}")
    if pricing.get("sourceURL") != "https://developers.openai.com/api/docs/pricing":
        raise SystemExit("manifest pricing.sourceURL must point to OpenAI API pricing")
    if not isinstance(pricing.get("rates"), list) or not pricing["rates"]:
        raise SystemExit("manifest pricing.rates must be a non-empty array")

    if strict_repo:
        current_commit = git_commit(repo)
        if current_commit != "unknown" and manifest.get("gitCommit") != current_commit:
            raise SystemExit("git commit mismatch")
        current_dirty = git_dirty(repo)
        if manifest.get("gitDirty") != current_dirty:
            raise SystemExit("git dirty-state mismatch")
        if manifest.get("pricing") != pricing_metadata(repo):
            raise SystemExit("pricing metadata mismatch")

    if require_clean:
        require_clean_release(manifest, repo)


def main() -> None:
    parser = argparse.ArgumentParser(description="Create or verify Codex Usage Monitor release metadata.")
    parser.add_argument("--app-name", default="CodexUsageMonitor")
    parser.add_argument("--bundle-identifier", required=False, default="local.codex.usagemonitor")
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--minimum-macos", default="13.0")
    parser.add_argument("--repo", required=True)
    parser.add_argument("--app", required=True)
    parser.add_argument("--zip", required=True)
    parser.add_argument("--dmg", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--verify", action="store_true")
    parser.add_argument("--strict-repo", action="store_true")
    parser.add_argument("--require-clean", action="store_true")
    parser.add_argument("--signature-policy", choices=SIGNATURE_POLICIES, default="any")
    args = parser.parse_args()

    out = Path(args.out)
    if args.verify:
        verify_manifest(out, Path(args.repo), args.strict_repo, args.require_clean, args.signature_policy)
        return

    manifest = build_manifest(args)
    if args.require_clean:
        require_clean_release(manifest, Path(args.repo))
    out.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    verify_manifest(out, Path(args.repo), True, args.require_clean, args.signature_policy)


if __name__ == "__main__":
    main()
