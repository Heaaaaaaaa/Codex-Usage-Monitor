#!/usr/bin/env python3
import argparse
import sys


PLACEHOLDER_BUNDLE_IDENTIFIERS = {
    "local.codex.usagemonitor",
    "com.example.codexusagemonitor",
    "com.yourname.codexusagemonitor",
}


def public_bundle_identifier_error(bundle_identifier: str) -> str | None:
    value = bundle_identifier.strip()
    if not value:
        return "Set BUNDLE_IDENTIFIER to your stable reverse-DNS app identifier."
    if value in PLACEHOLDER_BUNDLE_IDENTIFIERS:
        return f"Replace placeholder '{value}' with your stable reverse-DNS app identifier."
    if value != value.lower():
        return "Use lowercase only, for example com.name.codexusagemonitor."
    if any(character.isspace() for character in value):
        return "Bundle identifiers cannot contain whitespace."

    labels = value.split(".")
    if len(labels) < 3:
        return "Use a full reverse-DNS identifier with at least three labels, for example com.name.codexusagemonitor."

    allowed = set("abcdefghijklmnopqrstuvwxyz0123456789-.")
    invalid = sorted({character for character in value if character not in allowed})
    if invalid:
        return f"Bundle identifier contains invalid character(s): {''.join(invalid)}"

    for label in labels:
        if not label:
            return "Bundle identifier labels cannot be empty."
        if label.startswith("-") or label.endswith("-"):
            return "Bundle identifier labels cannot start or end with '-'."

    return None


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate a public macOS bundle identifier.")
    parser.add_argument("bundle_identifier")
    args = parser.parse_args()

    error = public_bundle_identifier_error(args.bundle_identifier)
    if error:
        print(f"FAIL public bundle identifier\n     {error}")
        return 2

    print(f"PASS public bundle identifier\n     {args.bundle_identifier}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
