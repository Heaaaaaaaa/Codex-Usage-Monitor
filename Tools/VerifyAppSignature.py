#!/usr/bin/env python3
import subprocess
import sys
import tempfile
from pathlib import Path


def verify_app_signature(app: Path) -> None:
    if not app.is_dir():
        raise SystemExit(f"app bundle not found: {app}")

    with tempfile.TemporaryDirectory(prefix="codex-usage-signature-") as folder:
        clean_app = Path(folder) / app.name
        subprocess.run(["ditto", "--norsrc", str(app), str(clean_app)], check=True)
        subprocess.run(["xattr", "-cr", str(clean_app)], check=True)
        subprocess.run(
            ["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(clean_app)],
            check=True,
        )


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: VerifyAppSignature.py /path/to/App.app", file=sys.stderr)
        return 2
    verify_app_signature(Path(sys.argv[1]).resolve())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
