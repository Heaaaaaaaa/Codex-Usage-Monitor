# Support

Codex Usage Monitor is a local macOS utility. The latest published release is the supported version.

## Before Reporting a Bug

1. Use **Refresh** and confirm the selected Codex log folder contains `sessions`, `archived_sessions`, or `session_index.jsonl`.
2. Open **Settings > Diagnostics**, confirm the latest scan completed, and note any parse issues.
3. Use **Copy Report**, review the text, and remove any remaining information you do not want to share.
4. Reproduce the issue with the latest release when possible.

Open a bug using the repository issue template. Include the app version and build, macOS version, Mac architecture, concise reproduction steps, expected behavior, actual behavior, and a reviewed diagnostic report.

Do not attach raw Codex logs, the contents of `~/.codex`, authentication files, exported usage CSV files, or screenshots containing personal project and chat names. A synthetic fixture can be generated with `make demo-data` when an example is needed.

## Cost Questions

Displayed USD values are estimates based on editable per-model API rates. They are not subscription balances or invoices and may not include cache writes, tool calls, long-context multipliers, processing modes, regional pricing, or other account-specific charges.

## Security Issues

Do not open a public bug for a suspected vulnerability. Follow [SECURITY.md](SECURITY.md) instead.
