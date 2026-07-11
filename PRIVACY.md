# Privacy Policy

Last updated: 2026-07-11

Codex Usage Monitor is a local macOS utility. It does not operate a server, collect analytics, create advertising identifiers, or transmit Codex usage data.

## Data the App Reads

The app reads JSONL files inside the Codex log folder you select. The default folder is `~/.codex`. The supported sources are:

- `sessions`
- `archived_sessions`
- `session_index.jsonl`

These files can contain token counts, model names, project paths, chat titles, timestamps, and locally reported usage-limit snapshots. The app does not read Codex authentication files.

## Data Stored on the Mac

App preferences are stored with macOS `UserDefaults`. They can include filters, budgets, display choices, the selected log-folder path, and editable model rates.

Parsed usage data is cached under `~/Library/Caches/CodexUsageMonitor` to make later scans faster. The cache stays on the Mac. Use **Settings > Diagnostics > Clear Caches** to remove all app-owned parsed-log caches.

The app can register itself as a macOS Login Item only when that option is enabled. It requests notification permission only when budget notifications are enabled.

## User-Initiated Exports

CSV export writes the currently filtered usage events to a location you choose. Settings export writes app preferences and editable rate rows; it does not include token-event history or source-log contents. **Copy Report** writes a support summary to the clipboard without raw log rows, project paths, or chat titles and redacts custom folder paths to their final folder name. Review any copied report before sharing it. The app does not upload exports or copied reports.

## Network Activity

The app does not make network requests. Choosing **Open Pricing Source** asks macOS to open the public OpenAI pricing page in your default browser; no local usage data is added to that URL.

## Data Sharing and Tracking

No data is sold or shared by the app. The app does not track people across apps or websites.

## Removing Local Data

Use **Settings > Diagnostics > Clear Caches** to remove parsed-log caches. App preferences can be removed by deleting Codex Usage Monitor's preferences through macOS or by uninstalling the app and its preference domain. Original Codex logs are owned by Codex and are never deleted by this app.

## Changes

Material privacy changes should be documented in the changelog and reflected in the bundled `PrivacyInfo.xcprivacy` manifest before release.
