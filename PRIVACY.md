# Privacy Policy

Last updated: 2026-10-20

Codex Usage Monitor is a local macOS utility. It does not operate a server, collect analytics, create advertising identifiers, or transmit Codex usage data.

## Data the App Reads

The app reads plain JSONL and Zstandard-compressed `.jsonl.zst` files inside the Codex log folder you select. Compressed logs are decoded in memory with a bundled decoder; originals are never modified and no extracted log copies are written to disk. The default folder is `~/.codex`. The supported sources are:

- `sessions`
- `archived_sessions`
- `session_index.jsonl`

These files can contain token counts, model names, project paths, chat titles, timestamps, and locally reported usage-limit snapshots. The monitor does not read Codex authentication files directly. Optional account reset sync delegates authentication to the official installed Codex CLI, as described below.

## Data Stored on the Mac

App preferences are stored with macOS `UserDefaults`. They can include filters, budgets, display choices, the selected log-folder path, editable model rates, the public pricing catalog, pricing-check timestamps, the automatic-pricing preference, and the account-reset-sync opt-in. Account reset counts, opaque credit IDs, and expiry dates are held in memory only and cleared when sync is disabled or the selected Codex folder changes.

Parsed usage data is cached under `~/Library/Caches/CodexUsageMonitor` to make later scans faster. The cache stays on the Mac. Use **Settings > Diagnostics > Clear Caches** to remove all app-owned parsed-log caches.

The app can register itself as a macOS Login Item only when that option is enabled. It requests notification permission only when budget notifications are enabled.

## User-Initiated Exports

CSV export writes the currently filtered usage events to a location you choose. Settings export writes app preferences and editable rate rows; it does not include token-event history or source-log contents. **Copy Report** writes a support summary to the clipboard without raw log rows, project paths, or chat titles and redacts custom folder paths to their final folder name. Review any copied report before sharing it. The app does not upload exports or copied reports.

## Network Activity

Automatic pricing updates are enabled by default and can be disabled in **Settings > Rates**. While running, the app checks the public `https://developers.openai.com/api/docs/pricing.md` document at most once every 24 hours, starting on launch. **Check official pricing now** can also request a check. The request contains no Codex logs, model-use history, project paths, chat titles, account credentials, or API key. OpenAI receives ordinary connection metadata such as your IP address. The app uses an ephemeral HTTP session without stored cookies or credentials and does not follow redirects.

The downloaded Standard short-context catalog is stored locally. Failed or incompatible responses leave saved rates unchanged, so usage tracking continues offline. Choosing **Open Pricing Source** opens the public OpenAI pricing page in your default browser without adding local usage data to the URL.

## Optional Account Reset Sync

**Settings > General > Account reset sync** is off by default. When enabled, the app launches the native Codex CLI installed with Codex, ChatGPT, or npm, using a private stdio connection. It initializes the connection and requests only `account/rateLimits/read`, the [official account interface](https://learn.chatgpt.com/docs/app-server#auth-endpoints). It does not expose a network listener, consume resets, start or modify chats, or initiate login/logout. It never displays or stores authentication tokens. The selected log folder is supplied as `CODEX_HOME`, so the CLI uses the sign-in associated with that folder.

The CLI communicates with OpenAI using its existing sign-in and may refresh or maintain its own authentication and runtime files. OpenAI receives the authenticated account request, client identification, and ordinary connection metadata. No parsed usage logs, project paths, or chat titles are included in the account request. CLI analytics are disabled for this subprocess. The monitor does not operate an intermediary server.

Automatic account checks are limited to once every five minutes during normal refresh or when opening the popover; manual refresh can request a new check. Each subprocess is time-limited and terminated after its request. Missing or unsupported reset inventory is not treated as zero. Failed checks retain the last successful in-memory count with a Saved label; counts older than fifteen minutes are also marked Saved. Known expired entries are excluded.

The app's bundled privacy manifest continues to declare no tracking and no developer-side data collection. Account requests go directly through the installed CLI to OpenAI, not to this project's developer.

## Data Sharing and Tracking

No data is sold or shared by the app. The app does not track people across apps or websites.

## Removing Local Data

Use **Settings > Diagnostics > Clear Caches** to remove parsed-log caches. App preferences can be removed by deleting Codex Usage Monitor's preferences through macOS or by uninstalling the app and its preference domain. Original Codex logs are owned by Codex and are never deleted by this app.

## Changes

Material privacy changes should be documented in the changelog and reflected in the bundled `PrivacyInfo.xcprivacy` manifest before release.
