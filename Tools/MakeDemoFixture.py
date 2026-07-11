#!/usr/bin/env python3
import argparse
import json
import shutil
from datetime import datetime, timedelta, timezone
from pathlib import Path


DEMO_MARKER = ".codex-usage-monitor-demo"
DEMO_VERSION = 1

DEMO_SESSIONS = [
    ("001", 0, "Atlas", "Plan the release dashboard", "gpt-5.6-sol", 2_420_000, 1_160_000, 318_000, 92_000),
    ("002", 0, "Launchpad", "Improve onboarding copy", "gpt-5.6-terra", 1_680_000, 640_000, 246_000, 54_000),
    ("003", 1, "Northstar", "Review usage analytics", "gpt-5.6-luna", 1_140_000, 510_000, 172_000, 31_000),
    ("004", 2, "Atlas", "Refactor authentication flow", "gpt-5.6-sol", 2_080_000, 940_000, 284_000, 76_000),
    ("005", 3, "Launchpad", "Polish empty states", "gpt-5.6-terra", 1_460_000, 590_000, 218_000, 46_000),
    ("006", 4, "Northstar", "Investigate sync latency", "gpt-5.6-sol", 1_920_000, 820_000, 266_000, 68_000),
    ("007", 5, "Atlas", "Add export validation", "gpt-5.6-luna", 980_000, 360_000, 148_000, 24_000),
    ("008", 6, "Launchpad", "Tune menu bar behavior", "gpt-5.6-terra", 1_320_000, 510_000, 194_000, 39_000),
    ("009", 7, "Northstar", "Map notification states", "gpt-5.6-luna", 860_000, 290_000, 126_000, 22_000),
    ("010", 8, "Atlas", "Audit pricing coverage", "gpt-5.6-sol", 1_740_000, 710_000, 238_000, 61_000),
    ("011", 9, "Launchpad", "Test settings migration", "gpt-5.6-terra", 1_210_000, 430_000, 182_000, 35_000),
    ("012", 10, "Northstar", "Simplify diagnostics", "gpt-5.6-luna", 790_000, 260_000, 118_000, 18_000),
    ("013", 11, "Atlas", "Profile startup scan", "gpt-5.6-sol", 1_560_000, 650_000, 224_000, 58_000),
    ("014", 12, "Launchpad", "Verify archive parsing", "gpt-5.6-terra", 1_090_000, 390_000, 164_000, 32_000),
    ("015", 13, "Northstar", "Draft release notes", "gpt-5.6-luna", 720_000, 240_000, 108_000, 16_000),
    ("016", 45, "Atlas", "Prototype token tracking", "gpt-5.6-terra", 940_000, 310_000, 142_000, 27_000),
]


def parse_now(value: str | None) -> datetime:
    if value is None:
        return datetime.now(timezone.utc).replace(microsecond=0)
    normalized = value.strip().replace("Z", "+00:00")
    parsed = datetime.fromisoformat(normalized)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc).replace(microsecond=0)


def write_jsonl(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    content = "\n".join(json.dumps(row, separators=(",", ":"), sort_keys=True) for row in rows) + "\n"
    path.write_text(content, encoding="utf-8")


def prepare_output(root: Path, replace: bool) -> None:
    if root.exists() and any(root.iterdir()):
        if not replace:
            raise FileExistsError(f"{root} is not empty; pass --replace to regenerate a marked demo folder")
        if not (root / DEMO_MARKER).is_file():
            raise FileExistsError(f"refusing to replace unmarked folder: {root}")
        shutil.rmtree(root)
    root.mkdir(parents=True, exist_ok=True)


def session_id(suffix: str) -> str:
    return f"01900000-0000-7000-8000-000000000{suffix}"


def event_timestamp(now: datetime, days_ago: int, position: int) -> datetime:
    return now - timedelta(days=days_ago, minutes=position * 17)


def rate_limits(now: datetime) -> dict:
    def unix(after: timedelta) -> int:
        return int((now + after).timestamp())

    return {
        "plan_type": "pro",
        "primary": {
            "used_percent": 38.0,
            "window_minutes": 300,
            "resets_at": unix(timedelta(hours=2, minutes=42)),
        },
        "secondary": {
            "used_percent": 57.0,
            "window_minutes": 10_080,
            "resets_at": unix(timedelta(days=4, hours=6)),
        },
        "credits": {
            "available": 3,
            "items": [
                {"id": "demo-reset-1", "label": "Reset Credit 1", "expires_at": unix(timedelta(days=12, hours=4))},
                {"id": "demo-reset-2", "label": "Reset Credit 2", "expires_at": unix(timedelta(days=21, hours=8))},
                {"id": "demo-reset-3", "label": "Reset Credit 3", "expires_at": unix(timedelta(days=28, hours=18))},
            ],
        },
    }


def build_demo_fixture(root: Path, now: datetime, replace: bool = False) -> dict:
    root = root.expanduser().resolve()
    now = now.astimezone(timezone.utc).replace(microsecond=0)
    prepare_output(root, replace=replace)
    (root / "sessions").mkdir()
    (root / "archived_sessions").mkdir()
    (root / DEMO_MARKER).write_text(
        json.dumps({"demoVersion": DEMO_VERSION, "generatedAt": now.isoformat().replace("+00:00", "Z")}, indent=2) + "\n",
        encoding="utf-8",
    )

    index_rows: list[dict] = []
    total_tokens = 0
    for position, spec in enumerate(DEMO_SESSIONS):
        suffix, days_ago, project, title, model, input_tokens, cached_tokens, output_tokens, reasoning_tokens = spec
        identifier = session_id(suffix)
        timestamp = event_timestamp(now, days_ago, position)
        total = input_tokens + output_tokens
        total_tokens += total
        index_rows.append({"id": identifier, "thread_name": title})

        payload: dict = {
            "type": "token_count",
            "info": {
                "total_token_usage": {
                    "input_tokens": input_tokens,
                    "cached_input_tokens": cached_tokens,
                    "output_tokens": output_tokens,
                    "reasoning_output_tokens": reasoning_tokens,
                    "total_tokens": total,
                }
            },
        }
        if position == 0:
            payload["rate_limits"] = rate_limits(now)

        rows = [
            {
                "type": "session_meta",
                "session_id": identifier,
                "cwd": f"/Users/demo/Projects/{project}",
                "model": model,
            },
            {
                "timestamp": timestamp.isoformat(timespec="milliseconds").replace("+00:00", "Z"),
                "type": "event_msg",
                "payload": payload,
            },
        ]
        destination = "archived_sessions" if days_ago >= 30 else "sessions"
        filename = f"rollout-{timestamp:%Y-%m-%d}-{identifier}.jsonl"
        write_jsonl(root / destination / filename, rows)

    write_jsonl(root / "session_index.jsonl", index_rows)
    return {
        "root": str(root),
        "sessions": len(DEMO_SESSIONS),
        "events": len(DEMO_SESSIONS),
        "tokens": total_tokens,
        "generatedAt": now.isoformat().replace("+00:00", "Z"),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate privacy-safe synthetic Codex JSONL logs for demos and screenshots.")
    parser.add_argument("--out", required=True, type=Path, help="Destination Codex data folder")
    parser.add_argument("--now", help="Reference ISO-8601 time; defaults to the current UTC time")
    parser.add_argument("--replace", action="store_true", help="Replace the destination only when it contains this tool's marker")
    args = parser.parse_args()

    try:
        summary = build_demo_fixture(args.out, parse_now(args.now), replace=args.replace)
    except (FileExistsError, ValueError) as error:
        parser.error(str(error))
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
