#!/usr/bin/env python3
import argparse
import plistlib
import sys
from pathlib import Path


REQUIRED_API = "NSPrivacyAccessedAPICategoryUserDefaults"
REQUIRED_REASON = "CA92.1"


def load_plist(path: Path) -> dict:
    with path.open("rb") as handle:
        return plistlib.load(handle)


def validate(path: Path) -> list[str]:
    errors: list[str] = []
    if not path.exists():
        return [f"{path}: missing privacy manifest"]

    try:
        manifest = load_plist(path)
    except (plistlib.InvalidFileException, OSError) as error:
        return [f"{path}: could not read plist: {error}"]

    if manifest.get("NSPrivacyTracking") is not False:
        errors.append(f"{path}: NSPrivacyTracking must be false")

    collected_data = manifest.get("NSPrivacyCollectedDataTypes")
    if collected_data != []:
        errors.append(f"{path}: NSPrivacyCollectedDataTypes must be an empty array")

    tracking_domains = manifest.get("NSPrivacyTrackingDomains")
    if tracking_domains != []:
        errors.append(f"{path}: NSPrivacyTrackingDomains must be an empty array")

    accessed_apis = manifest.get("NSPrivacyAccessedAPITypes")
    if not isinstance(accessed_apis, list):
        errors.append(f"{path}: NSPrivacyAccessedAPITypes must be an array")
        accessed_apis = []

    matching_entries = [
        entry for entry in accessed_apis
        if isinstance(entry, dict) and entry.get("NSPrivacyAccessedAPIType") == REQUIRED_API
    ]
    if not matching_entries:
        errors.append(f"{path}: missing {REQUIRED_API}")
    elif not any(
        REQUIRED_REASON in entry.get("NSPrivacyAccessedAPITypeReasons", [])
        for entry in matching_entries
    ):
        errors.append(f"{path}: {REQUIRED_API} must include reason {REQUIRED_REASON}")

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate Codex Usage Monitor privacy manifests.")
    parser.add_argument("manifests", nargs="+", help="PrivacyInfo.xcprivacy files to validate.")
    args = parser.parse_args()

    errors: list[str] = []
    for manifest in args.manifests:
        errors.extend(validate(Path(manifest)))

    if errors:
        for error in errors:
            print(f"FAIL {error}")
        return 2

    for manifest in args.manifests:
        print(f"PASS privacy manifest {manifest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
