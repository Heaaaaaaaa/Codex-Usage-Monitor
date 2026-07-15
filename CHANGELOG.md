# Changelog

## 0.4.3 - 2026-07-15

- Fixed a launch and popover crash caused by exhausting the 256-file LaunchServices descriptor limit while watching recent Codex session logs.
- Bounded active session-file watches, drained canceled watchers before restarting, and added a release regression check for the descriptor budget.

## 0.4.2 - 2026-07-13

- Identified rate-limit cards from each snapshot's reported window duration instead of assuming the primary slot is always five hours and the secondary slot is always weekly.
- Adapted the Limits row to weekly-only and future window combinations, hiding unreported windows and restoring them automatically when Codex reports them again.
- Added regression coverage for weekly-only, reversed, daily, multi-day, hourly, minute, and invalid rate-limit windows.

## 0.4.1 - 2026-07-11

- Refreshed the synthetic public screenshots with complete cursor-free dashboard and Rates captures.
- Allowed standard version tags to skip notarized publishing cleanly when Apple signing secrets are not configured.

- Declared the app as an `LSUIElement` agent so it launches directly as a menu-bar utility without a transient Dock presence.
- Counted the first usage snapshot after a cumulative token-counter reset instead of silently dropping that segment.
- Limited fallback deduplication to consecutive duplicate snapshots so later legitimate turns with the same token shape remain counted.
- Bounded relevant JSONL lines at 8 MB and continued scanning later events after an oversized malformed line.
- Labeled dollar figures and budgets more explicitly as API-rate estimates, including the input-rate assumption for total-only legacy rows.
- Expired rate-limit windows and reset credits now stop presenting stale availability, with minute-by-minute countdown refreshes while the dashboard is visible.
- Hardened numeric log parsing against non-finite, out-of-range, and negative values so malformed local events cannot crash or corrupt usage totals.
- Redacted custom folder paths and selected project/chat labels from copied diagnostics, and documented the remaining clipboard contents in the privacy policy.
- Added public support, security, and privacy-preserving bug-report guidance.
- Added a reusable native runtime gate that proves the panel reopens and hides when another app receives focus.
- Made pricing edits transactional so Add, remove, restore, and field changes affect estimates only after Apply; Revert or leaving Settings discards the draft.
- Isolated the runtime verifier's Swift module cache and included LaunchServices error codes in failed gate diagnostics.
- Added public-source scanning and a clean source-archive workflow so removed local paths and machine-local commit metadata are not accidentally published.
- Made UI state explicitly main-actor owned, kept log parsing off the main thread, and added a warning-free Swift complete-concurrency release gate.
- Preserved parsed token caches across chat-title index updates, isolated release diagnostics from the live app cache, and merged cache writes under an interprocess lock so concurrent scans cannot repeatedly evict each other.
- Made direct ZIP and DMG packaging rebuild the app first so stale bundles cannot be archived accidentally.
- Replaced the detached utility window with a transient menu-bar popover that anchors under the status icon and closes naturally when focus moves elsewhere.
- Added a migrated icon-only menu-bar mode to minimize space on crowded menu bars while retaining optional token and cost labels.
- Replaced the chart artwork with a unified cobalt usage mark for the app icon and a matching monochrome menu-bar template.

## 0.4.0 - 2026-07-11

- Added a Tokens/Cost selector to the daily trend so estimated spend can be inspected across the active time, project, chat, or model filter.
- Persisted the selected trend metric and included it in backward-compatible settings import/export and diagnostics.
- Filled inactive calendar days in trends and aligned Today, 7-day, and 30-day filters to calendar-day boundaries.
- Captured immutable scan sources and rejected stale completions so changing the Codex log folder during a scan cannot briefly display results from the previous folder.
- Expanded Clear Caches to remove all app-owned parsed-log caches while protecting active scans.
- Simplified the app icon to a text-free chart mark that remains recognizable at 16- and 32-pixel macOS sizes.
- Added release tag/version validation and a credential-gated GitHub workflow for Developer ID signing, Apple notarization, stapling, artifact verification, and release creation.
- Added file-based notary keychain support for CI and removed an unsupported notary-history argument from network preflight checks.
- Added a guarded, deterministic synthetic Codex-log generator and privacy-safe public UI screenshots for release presentation and parser demos.
- Added regression coverage for trend continuity, cost reconciliation, saved display preferences, stale scan rejection, and cache safety.

## 0.3.0 - 2026-07-08

- Added launch-at-login support through macOS Login Items.
- Added optional quiet startup for menu-bar-only launches.
- Reopening the already-running app from Finder now reveals the dashboard.
- Dashboard window now behaves as a transient, nonfloating panel and hides when another app becomes active.
- Added a right-click menu-bar Usage Snapshot with filter, tokens, estimated cost, budgets, and scan status.
- Added configurable menu-bar display for tokens, estimated cost, or both.
- Added configurable auto-refresh intervals: off, 1 minute, 5 minutes, and 15 minutes.
- Added debounced local log watching so enabled auto-refresh reacts quickly when Codex writes new usage events.
- Throttled watcher and timer refreshes to at most once per minute so continuous log writes cannot chain Lifetime scans indefinitely.
- Made the Touch Bar summary and time-window selection update live as usage and filters change.
- Added JSON import/export for app settings, budgets, filters, selected log folder, and editable model rates.
- Added visible OpenAI pricing source metadata plus direct source and restore controls for the default rate table.
- Added current GPT-5.6 Sol, Terra, and Luna Standard short-context rates with versioned migration that preserves edits and removals while keeping current built-ins first.
- Added token-level pricing coverage across the dashboard, menu bar, Touch Bar, status menu, copied summaries, diagnostics, and health warnings.
- Restricted automatic model-rate aliases to exact IDs and official date-snapshot forms so similarly named models are not silently mispriced.
- Added explicit cost-estimate limitations for cache writes, tool calls, long context, processing modes, regional pricing, and subscriptions.
- Added release-manifest pricing metadata for shipped rate source, verification date, and built-in model rates.
- Added a configurable Codex log folder with menu and Settings controls, while keeping `~/.codex` as the default.
- Added a wrong-folder health warning with a direct Choose Folder recovery action.
- Added a Today window for calendar-day token and cost monitoring.
- Added previous-period comparison for tokens and estimated cost in Today, 7-day, and 30-day windows.
- Added reset-credit expiry rows when local Codex rate-limit snapshots include individual credit expiry data.
- Added effective average cost per 1M tokens and 30-day cost pace metrics.
- Added a Cost Mix dashboard panel that explains estimated spend by non-cached input, cached input, output, and total-only log rows.
- Added optional token and estimated-cost budgets for the active filter window.
- Added menu-bar warning markers and status-menu alert detail for configured budgets near or over their limit.
- Added optional macOS notifications for budget warning and exceeded states.
- Reworked Settings into a dedicated, keyboard-accessible view with clear categories instead of appending controls below the dashboard.
- Consolidated secondary dashboard actions into an accessible overflow menu so the compact toolbar keeps its title and primary actions visible.
- Added a Recent Activity panel for the latest token events in the current filter.
- Expanded project, chat, and model target selectors to include every local match, while keeping visible breakdowns concise.
- Fixed bounded scans so recently updated long-running chats are included even when their session filenames are older than the loaded history window.
- Added an explicit loading state when switching to a usage window that needs a wider log scan, preventing stale metrics from appearing under a new filter label.
- Added Diagnostics & Privacy scan metadata for local path, loaded window, scanned files, cache hits, cache size, events, and latest event.
- Added scan-health notices for first launch, missing logs, empty filters, and incomplete cost estimates.
- Added a copyable diagnostics report for support/debugging from the app and status menus.
- Added parser diagnostics for malformed or unreadable token log lines, including dashboard, health, cache, and copied-report visibility.
- Added a local parsed-log cache to make repeat startup and refresh scans much faster while still reparsing changed files.
- Added cache pruning for deleted log files plus a clear-cache control in Diagnostics & Privacy.
- Added a `UserDefaults` required-reason API declaration to the privacy manifest.
- Added release validation for privacy manifest required-reason API contents and records them in the release manifest.
- Added release verification targets for the app bundle, zip, DMG, checksums, and disk image.
- Added a GitHub Actions release-check workflow that builds, verifies, and uploads release artifacts.
- Added a public publishing checklist and made CI artifact upload paths version-tolerant.
- Added a public release preflight target for Developer ID, notary, bundle metadata, privacy manifest, entitlements, and universal binary prerequisites.
- Added release-tool tests and early rejection for non-Developer-ID signing identities in public preflight.
- Made release diagnostics use an isolated 7-day scan instead of saved dashboard preferences.
- Generated bundle metadata from release variables so publish builds can override the bundle identifier safely.
- Made release artifact paths work from both the workspace and OneDrive project layouts.
- Fixed release verification for output folders whose paths contain spaces.
- Added a credential-gated notarized DMG release target for public distribution.
- Preserved Developer ID app signatures when packaging signed DMGs.
- Added a generated release manifest with artifact sizes, SHA-256 hashes, version, build, commit, and privacy metadata.
- Verified release manifests against app bundle metadata.
- Verified release manifests against packaged artifact sizes and hashes.
- Avoided duplicate startup scans when the window appears during an active refresh.
- Coalesced overlapping refresh requests from startup, menu, Touch Bar, and auto-refresh.
- Added unpriced-model warnings and one-click placeholder rate rows.
- Added editable model names plus custom add/remove rows in the rate table.
- Added persisted filter, scope, target, startup, refresh, menu-bar, and rate preferences.
- Added DMG packaging plus portable SHA-256 checksum files.
- Added an About panel, privacy manifest, hardened-runtime signing target, and notarization helper targets.
- Expanded the test harness to cover parser behavior, cost math, preferences, unpriced models, reset-credit display, exports, and startup/menu-bar settings.

## 0.2.0 - 2026-07-08

- Added the native macOS menu-bar app bundle, icon, status item, Touch Bar controls, CSV export, and local release packaging.
- Added local Codex JSONL parsing for sessions, archived sessions, and session index metadata.
- Added 7-day, 30-day, lifetime, project, chat, and model views with editable model rates.
