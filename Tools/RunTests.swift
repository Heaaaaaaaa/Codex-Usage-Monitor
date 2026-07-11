import Darwin
import Foundation

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw TestFailure(description: message)
    }
}

private func requireEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    if actual != expected {
        throw TestFailure(description: "\(message): expected \(expected), got \(actual)")
    }
}

private func requireApprox(_ actual: Double, _ expected: Double, tolerance: Double = 0.000_001, _ message: String) throws {
    if abs(actual - expected) > tolerance {
        throw TestFailure(description: "\(message): expected \(expected), got \(actual)")
    }
}

private func requireDate(_ value: Date?, _ message: String) throws -> Date {
    guard let value else {
        throw TestFailure(description: message)
    }
    return value
}

private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() {
            return true
        }
        _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    return condition()
}

private func makeDate(daysAgo: Int) -> Date {
    Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
}

private func makeEntry(
    id: String,
    daysAgo: Int,
    sessionID: String,
    chatTitle: String,
    projectPath: String,
    model: String,
    tokens: UsageTokens
) -> UsageEntry {
    UsageEntry(
        id: id,
        timestamp: makeDate(daysAgo: daysAgo),
        sessionID: sessionID,
        chatTitle: chatTitle,
        projectPath: projectPath,
        model: model,
        tokens: tokens,
        sourceFile: "\(id).jsonl:1"
    )
}

private func isoString(daysAgo: Int, secondsOffset: TimeInterval = 0) -> String {
    let date = makeDate(daysAgo: daysAgo).addingTimeInterval(secondsOffset)
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

private func jsonLine(_ object: [String: Any]) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(data: data, encoding: .utf8) ?? "{}"
}

private func writeJSONL(_ url: URL, _ objects: [[String: Any]]) throws {
    let lines = try objects.map(jsonLine).joined(separator: "\n") + "\n"
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try lines.write(to: url, atomically: true, encoding: .utf8)
}

private func appendJSONL(_ url: URL, _ object: [String: Any]) throws {
    let line = try jsonLine(object) + "\n"
    let handle = try FileHandle(forWritingTo: url)
    defer {
        try? handle.close()
    }
    handle.seekToEndOfFile()
    handle.write(Data(line.utf8))
}

private func tokenEvent(timestamp: String, info: [String: Any], limits: [String: Any]? = nil) -> [String: Any] {
    var payload: [String: Any] = [
        "type": "token_count",
        "info": info
    ]
    if let limits {
        payload["rate_limits"] = limits
    }
    return [
        "timestamp": timestamp,
        "type": "event_msg",
        "payload": payload
    ]
}

private func tokenUsage(input: Int, cached: Int, output: Int, reasoning: Int, total: Int) -> [String: Any] {
    [
        "input_tokens": input,
        "cached_input_tokens": cached,
        "output_tokens": output,
        "reasoning_output_tokens": reasoning,
        "total_tokens": total
    ]
}

private func makeTemporaryCodexHome() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CodexUsageMonitorTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root.appendingPathComponent("sessions"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("archived_sessions"), withIntermediateDirectories: true)
    return root
}

private func makeTemporaryCacheURL() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CodexUsageMonitorCacheTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.appendingPathComponent("usage-cache.json")
}

private func buildCodexFixture() throws -> URL {
    let root = try makeTemporaryCodexHome()
    let sessionID = "019parser-test-session"
    let archiveID = "019parser-archive-session"
    let oldID = "019parser-old-session"
    try writeJSONL(root.appendingPathComponent("session_index.jsonl"), [
        ["id": sessionID, "thread_name": "Parser fixture"],
        ["id": archiveID, "thread_name": "Archived parser fixture"],
        ["id": oldID, "thread_name": "Old parser fixture"]
    ])

    try writeJSONL(root.appendingPathComponent("sessions/rollout-\(currentDayString(daysAgo: 1))-\(sessionID).jsonl"), [
        [
            "type": "session_meta",
            "session_id": sessionID,
            "cwd": "/tmp/Parser Project",
            "model": "gpt-5.5"
        ],
        tokenEvent(
            timestamp: isoString(daysAgo: 1, secondsOffset: 10),
            info: [
                "total_token_usage": tokenUsage(input: 1_000, cached: 200, output: 100, reasoning: 10, total: 1_100)
            ],
            limits: [
                "plan_type": "pro",
                "primary": [
                    "used_percent": 25.0,
                    "window_minutes": 300,
                    "resets_at": Int(Date().addingTimeInterval(3_600).timeIntervalSince1970)
                ],
                "secondary": [
                    "used_percent": 40.0,
                    "window_minutes": 10_080,
                    "resets_at": Int(Date().addingTimeInterval(86_400).timeIntervalSince1970)
                ],
                "credits": [
                    "available": 2,
                    "items": [
                        [
                            "id": "reset-credit-1",
                            "label": "Reset Credit 1",
                            "expires_at": Int(Date().addingTimeInterval(7_200).timeIntervalSince1970)
                        ],
                        [
                            "id": "reset-credit-2",
                            "label": "Reset Credit 2",
                            "expires_at": Int(Date().addingTimeInterval(86_400).timeIntervalSince1970)
                        ]
                    ]
                ]
            ]
        ),
        [
            "type": "turn_context",
            "cwd": "/tmp/Parser Project",
            "model": "gpt-5.5"
        ],
        tokenEvent(
            timestamp: isoString(daysAgo: 1, secondsOffset: 20),
            info: [
                "total_token_usage": tokenUsage(input: 1_600, cached: 300, output: 180, reasoning: 20, total: 1_780)
            ]
        )
    ])

    try writeJSONL(root.appendingPathComponent("archived_sessions/rollout-\(currentDayString(daysAgo: 2))-\(archiveID).jsonl"), [
        [
            "type": "session_meta",
            "session_id": archiveID,
            "cwd": "/tmp/Archived Project",
            "model": "gpt-5.3-codex"
        ],
        tokenEvent(
            timestamp: isoString(daysAgo: 2),
            info: [
                "last_token_usage": tokenUsage(input: 300, cached: 100, output: 80, reasoning: 5, total: 380)
            ]
        )
    ])

    let oldSessionURL = root.appendingPathComponent("sessions/rollout-\(currentDayString(daysAgo: 20))-\(oldID).jsonl")
    try writeJSONL(oldSessionURL, [
        [
            "type": "session_meta",
            "session_id": oldID,
            "cwd": "/tmp/Old Parser Project",
            "model": "gpt-5.5"
        ],
        tokenEvent(
            timestamp: isoString(daysAgo: 20),
            info: [
                "last_token_usage": tokenUsage(input: 999, cached: 0, output: 1, reasoning: 0, total: 1_000)
            ]
        )
    ])
    try FileManager.default.setAttributes(
        [.modificationDate: makeDate(daysAgo: 20)],
        ofItemAtPath: oldSessionURL.path
    )

    return root
}

private func currentDayString(daysAgo: Int) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.string(from: makeDate(daysAgo: daysAgo))
}

@MainActor
private func configuredStore() -> UsageStore {
    let store = UsageStore(preferences: isolatedPreferences())
    store.rates = [
        ModelRate(model: "gpt-5.5", inputPerMillion: 10.0, cachedInputPerMillion: 1.0, outputPerMillion: 20.0),
        ModelRate(model: "gpt-5.3-codex", inputPerMillion: 2.0, cachedInputPerMillion: 0.5, outputPerMillion: 8.0)
    ]
    store.entries = [
        makeEntry(
            id: "recent-1",
            daysAgo: 2,
            sessionID: "session-a",
            chatTitle: "Alpha, \"Chat\"",
            projectPath: "/tmp/Project One",
            model: "gpt-5.5",
            tokens: UsageTokens(input: 1_000, cachedInput: 400, output: 200, reasoningOutput: 50, total: 1_200)
        ),
        makeEntry(
            id: "recent-2",
            daysAgo: 1,
            sessionID: "session-a",
            chatTitle: "Alpha, \"Chat\"",
            projectPath: "/tmp/Project One",
            model: "gpt-5.3-codex",
            tokens: UsageTokens(input: 500, cachedInput: 100, output: 100, reasoningOutput: 20, total: 600)
        ),
        makeEntry(
            id: "old",
            daysAgo: 20,
            sessionID: "session-b",
            chatTitle: "Old chat",
            projectPath: "/tmp/Project Two",
            model: "gpt-5.5",
            tokens: UsageTokens(input: 0, cachedInput: 0, output: 0, reasoningOutput: 0, total: 1_000)
        )
    ]
    store.dateWindow = .sevenDays
    store.scopeMode = .all
    store.selectedScopeID = ""
    store.recompute()
    return store
}

private func isolatedPreferences() -> UserDefaults {
    let suite = "CodexUsageMonitorTests-\(UUID().uuidString)"
    let preferences = UserDefaults(suiteName: suite) ?? .standard
    preferences.removePersistentDomain(forName: suite)
    return preferences
}

@MainActor
private func testSevenDaySummaryAndCost() throws {
    let store = configuredStore()
    try requireEqual(store.summary.eventCount, 2, "7-day event count")
    try requireEqual(store.summary.sessionCount, 1, "7-day session count")
    try requireEqual(store.summary.tokens.total, 1_800, "7-day total tokens")
    try requireEqual(store.summary.tokens.cachedInput, 500, "cached input total")
    try requireEqual(store.summary.tokens.reasoningOutput, 70, "reasoning total")
    try requireApprox(store.summary.cost, 0.01205, "7-day cost")
    try requireApprox(store.averageCostPerMillion, 6.694_444_444, "average cost per million")
    try requireApprox(store.thirtyDayCostPace, 0.051_642_857, "30-day cost pace")
    try requireEqual(store.projectRows.first?.label, "Project One", "project label")
    try requireEqual(store.projectRows.first?.tokens.total, 1_800, "project token total")
    try requireEqual(store.chatRows.first?.label, "Alpha, \"Chat\"", "chat label")
    try requireEqual(store.modelRows.count, 2, "model breakdown count")
    try requireEqual(store.dailyRows.count, 7, "daily trend covers seven calendar days")
    try requireEqual(store.dailyRows.filter { $0.tokens.total == 0 }.count, 5, "daily trend fills inactive days")
    try requireEqual(store.dailyRows.map { $0.tokens.total }.filter { $0 > 0 }.sorted(), [600, 1_200], "daily trend preserves active-day totals")
    try requireApprox(store.dailyRows.reduce(0) { $0 + $1.cost }, store.summary.cost, "daily trend cost matches summary")
    try requireEqual(store.costRows.map(\.id), ["input", "cached", "output"], "cost row order")
    try requireEqual(store.costRows[0].tokens, 1_000, "non-cached input cost tokens")
    try requireEqual(store.costRows[1].tokens, 500, "cached input cost tokens")
    try requireEqual(store.costRows[2].tokens, 300, "output cost tokens")
    try requireApprox(store.costRows[0].cost, 0.0068, "input cost component")
    try requireApprox(store.costRows[1].cost, 0.00045, "cached cost component")
    try requireApprox(store.costRows[2].cost, 0.0048, "output cost component")
    try requireApprox(store.costRows.reduce(0) { $0 + $1.cost }, store.summary.cost, "cost components sum to summary cost")
    try requireEqual(store.recentRows.count, 2, "recent activity row count")
    try requireEqual(store.recentRows.first?.title, "Alpha, \"Chat\"", "recent activity title")
    try requireEqual(store.recentRows.first?.detail, "Project One / gpt-5.3-codex", "recent activity detail")
    try requireEqual(store.recentRows.first?.tokens.total, 600, "recent activity tokens")
    try requireApprox(store.recentRows.first?.cost ?? -1, 0.00165, "recent activity cost")
}

@MainActor
private func testTodayWindowFiltersCurrentCalendarDay() throws {
    let preferences = isolatedPreferences()
    let store = UsageStore(preferences: preferences)
    store.rates = [
        ModelRate(model: "gpt-5.5", inputPerMillion: 10.0, cachedInputPerMillion: 1.0, outputPerMillion: 20.0)
    ]
    store.entries = [
        makeEntry(
            id: "today",
            daysAgo: 0,
            sessionID: "session-today",
            chatTitle: "Today chat",
            projectPath: "/tmp/Today Project",
            model: "gpt-5.5",
            tokens: UsageTokens(input: 1_000, cachedInput: 100, output: 200, reasoningOutput: 10, total: 1_200)
        ),
        makeEntry(
            id: "yesterday",
            daysAgo: 1,
            sessionID: "session-yesterday",
            chatTitle: "Yesterday chat",
            projectPath: "/tmp/Yesterday Project",
            model: "gpt-5.5",
            tokens: UsageTokens(input: 2_000, cachedInput: 0, output: 500, reasoningOutput: 20, total: 2_500)
        )
    ]
    store.dateWindow = .today
    store.recompute()

    try requireEqual(DateWindow.today.title, "Today", "today window title")
    try requireEqual(DateWindow.today.days, 1, "today scan-day coverage")
    try requireEqual(DateWindow.today.historyDays, 2, "today comparison history coverage")
    try requireEqual(store.summary.eventCount, 1, "today event count")
    try requireEqual(store.summary.tokens.total, 1_200, "today token total")
    try requireEqual(store.comparison.label, "yesterday", "today comparison label")
    try requireEqual(store.comparison.previousTokens, 2_500, "today previous token total")
    try requireEqual(store.comparison.tokenDelta, -1_300, "today token delta")
    try requireApprox(store.comparison.tokenDeltaPercent ?? 0, -0.52, "today token delta percent")
    try requireEqual(store.projectRows.first?.label, "Today Project", "today project label")
    try requireEqual(store.dailyRows.count, 1, "today daily trend row count")

    store.setDateWindow(.today)
    let reloaded = UsageStore(preferences: preferences)
    try requireEqual(reloaded.dateWindow, .today, "today window preference persists")
}

@MainActor
private func testCalendarWindowBoundaries() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Kuala_Lumpur") ?? .current
    let now = try requireDate(calendar.date(from: DateComponents(
        year: 2026,
        month: 7,
        day: 10,
        hour: 15,
        minute: 30
    )), "calendar fixture now")
    let today = try requireDate(calendar.date(from: DateComponents(year: 2026, month: 7, day: 10)), "calendar fixture today")
    let sevenDayStart = try requireDate(calendar.date(byAdding: .day, value: -6, to: today), "seven-day start fixture")
    let thirtyDayStart = try requireDate(calendar.date(byAdding: .day, value: -29, to: today), "thirty-day start fixture")

    try requireEqual(DateWindow.today.startDate(now: now, calendar: calendar), today, "today starts at local midnight")
    try requireEqual(DateWindow.sevenDays.startDate(now: now, calendar: calendar), sevenDayStart, "seven-day window includes seven calendar days")
    try requireEqual(DateWindow.thirtyDays.startDate(now: now, calendar: calendar), thirtyDayStart, "thirty-day window includes thirty calendar days")
    try require(DateWindow.lifetime.startDate(now: now, calendar: calendar) == nil, "lifetime has no start boundary")
}

@MainActor
private func testComparisonUsesSelectedScope() throws {
    let store = UsageStore(preferences: isolatedPreferences())
    store.rates = [
        ModelRate(model: "gpt-5.5", inputPerMillion: 10.0, cachedInputPerMillion: 1.0, outputPerMillion: 20.0)
    ]
    store.entries = [
        makeEntry(
            id: "current-a",
            daysAgo: 1,
            sessionID: "session-current-a",
            chatTitle: "Current A",
            projectPath: "/tmp/Project A",
            model: "gpt-5.5",
            tokens: UsageTokens(input: 1_000, cachedInput: 0, output: 0, reasoningOutput: 0, total: 1_000)
        ),
        makeEntry(
            id: "current-b",
            daysAgo: 1,
            sessionID: "session-current-b",
            chatTitle: "Current B",
            projectPath: "/tmp/Project B",
            model: "gpt-5.5",
            tokens: UsageTokens(input: 3_000, cachedInput: 0, output: 0, reasoningOutput: 0, total: 3_000)
        ),
        makeEntry(
            id: "previous-a",
            daysAgo: 10,
            sessionID: "session-previous-a",
            chatTitle: "Previous A",
            projectPath: "/tmp/Project A",
            model: "gpt-5.5",
            tokens: UsageTokens(input: 400, cachedInput: 0, output: 0, reasoningOutput: 0, total: 400)
        ),
        makeEntry(
            id: "previous-b",
            daysAgo: 10,
            sessionID: "session-previous-b",
            chatTitle: "Previous B",
            projectPath: "/tmp/Project B",
            model: "gpt-5.5",
            tokens: UsageTokens(input: 9_000, cachedInput: 0, output: 0, reasoningOutput: 0, total: 9_000)
        )
    ]
    store.dateWindow = .sevenDays
    store.scopeMode = .project
    store.selectedScopeID = "/tmp/Project A"
    store.recompute()

    try requireEqual(DateWindow.sevenDays.historyDays, 14, "7-day comparison history coverage")
    try requireEqual(DateWindow.thirtyDays.historyDays, 60, "30-day comparison history coverage")
    try requireEqual(store.summary.tokens.total, 1_000, "scoped current comparison tokens")
    try requireEqual(store.comparison.label, "previous 7d", "7-day comparison label")
    try requireEqual(store.comparison.previousTokens, 400, "scoped previous comparison tokens")
    try requireEqual(store.comparison.tokenDelta, 600, "scoped comparison token delta")
    try requireApprox(store.comparison.tokenDeltaPercent ?? 0, 1.5, "scoped comparison token delta percent")
}

@MainActor
private func testScopeFiltering() throws {
    let store = configuredStore()
    store.setScopeMode(.project)
    store.setSelectedScope("/tmp/Project One")
    try requireEqual(store.summary.eventCount, 2, "selected project event count")
    try requireEqual(store.summary.tokens.total, 1_800, "selected project tokens")

    store.setSelectedScope("/tmp/Missing")
    try requireEqual(store.summary.eventCount, 0, "missing project event count")
    try requireEqual(store.summary.tokens.total, 0, "missing project tokens")
    try requireEqual(store.recentRows.count, 0, "missing project recent activity rows")

    store.setScopeMode(.chat)
    store.setSelectedScope("session-a")
    try requireEqual(store.summary.eventCount, 2, "selected chat event count")

    store.setScopeMode(.model)
    store.setSelectedScope("gpt-5.3-codex")
    try requireEqual(store.summary.eventCount, 1, "selected model event count")
    try requireEqual(store.summary.tokens.total, 600, "selected model tokens")
    try requireApprox(store.summary.cost, 0.00165, "selected model cost")
}

@MainActor
private func testScopeOptionsIncludeAllProjectsChatsAndModels() throws {
    let store = UsageStore(preferences: isolatedPreferences())
    store.rates = [
        ModelRate(model: "gpt-5.5", inputPerMillion: 10.0, cachedInputPerMillion: 1.0, outputPerMillion: 20.0)
    ]
    store.entries = (1...10).map { index in
        makeEntry(
            id: "scope-option-\(index)",
            daysAgo: 1,
            sessionID: "session-\(index)",
            chatTitle: "Chat \(index)",
            projectPath: "/tmp/Project \(index)",
            model: "model-\(index)",
            tokens: UsageTokens(input: index * 100, cachedInput: 0, output: 10, reasoningOutput: 0, total: index * 100 + 10)
        )
    }
    store.dateWindow = .sevenDays
    store.scopeMode = .all
    store.selectedScopeID = ""
    store.recompute()

    try requireEqual(store.projectRows.count, 8, "display project breakdown stays capped")
    try requireEqual(store.chatRows.count, 8, "display chat breakdown stays capped")
    try requireEqual(store.modelRows.count, 8, "display model breakdown stays capped")
    try requireEqual(store.projectOptionRows.count, 10, "project filter options include all projects")
    try requireEqual(store.chatOptionRows.count, 10, "chat filter options include all chats")
    try requireEqual(store.modelOptionRows.count, 10, "model filter options include all models")
    try require(store.projectOptionRows.contains { $0.id == "/tmp/Project 1" }, "low-usage project is selectable")
    try require(store.chatOptionRows.contains { $0.id == "session-1" }, "low-usage chat is selectable")
    try require(store.modelOptionRows.contains { $0.id == "model-1" }, "low-usage model is selectable")

    store.setScopeMode(.project)
    store.setSelectedScope("/tmp/Project 1")
    try requireEqual(store.summary.eventCount, 1, "low-usage project filter event count")
    try requireEqual(store.summary.tokens.total, 110, "low-usage project filter tokens")

    store.setScopeMode(.model)
    store.setSelectedScope("model-1")
    try requireEqual(store.summary.eventCount, 1, "low-usage model filter event count")
    try requireEqual(store.summary.tokens.total, 110, "low-usage model filter tokens")
}

@MainActor
private func testCSVExportEscaping() throws {
    let store = configuredStore()
    let csv = store.csvString()
    let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)
    try requireEqual(lines.count, 4, "CSV line count including trailing blank")
    try require(csv.hasPrefix("timestamp,project,chat,model,input_tokens"), "CSV header")
    try require(csv.contains("\"Alpha, \"\"Chat\"\"\""), "CSV escapes comma and quotes in chat title")
    try require(csv.contains("0.010400"), "CSV includes first row cost")
    try require(csv.contains("0.001650"), "CSV includes second row cost")
    try require(!csv.contains("Old chat"), "CSV respects current date window")
}

@MainActor
private func testLifetimeIncludesOlderRowsAndTotalOnlyCost() throws {
    let store = configuredStore()
    store.dateWindow = .lifetime
    store.scopeMode = .all
    store.selectedScopeID = ""
    store.recompute()

    try requireEqual(store.summary.eventCount, 3, "lifetime event count")
    try requireEqual(store.summary.sessionCount, 2, "lifetime session count")
    try requireEqual(store.summary.tokens.total, 2_800, "lifetime total tokens")
    try requireApprox(store.summary.cost, 0.02205, "lifetime cost includes total-only fallback")
    try require(store.costRows.contains { $0.id == "total" && $0.tokens == 1_000 }, "lifetime shows total-only cost component")
    try require(!store.comparison.isVisible, "lifetime comparison hidden")
}

@MainActor
private func testSummaryText() throws {
    let store = configuredStore()
    let summary = store.summaryText()
    try require(summary.contains("Codex Usage Monitor"), "summary title")
    try require(summary.contains("Window: 7 days"), "summary window")
    try require(summary.contains("Scope: All activity"), "summary scope")
    try require(summary.contains("Status: Ready"), "summary health status")
    try require(summary.contains("Tokens: 1.8K"), "summary token compact number")
    try require(summary.contains("Estimated cost: $0.01"), "summary cost")
    try require(summary.contains("Pricing coverage: 100% (1.8K of 1.8K logged tokens)"), "summary pricing coverage")
    try require(summary.contains("Average cost / 1M tokens: $6.69"), "summary average cost")
    try require(summary.contains("30-day cost pace: $0.05"), "summary cost pace")
    try require(summary.contains("Compared with previous 7d: +1.8K tokens"), "summary comparison")
    try require(summary.contains("Cost mix: Input $0.01, Cached $0.00, Output $0.00"), "summary cost mix")
    try require(summary.contains("Pricing limits: \(UsageStore.defaultRateLimitations)"), "summary pricing limitations")
}

@MainActor
private func testTouchBarSummaryText() throws {
    let store = configuredStore()
    try requireEqual(store.touchBarSummary, "7d 1.8K tokens $0.01", "touch bar seven-day summary")

    store.dateWindow = .lifetime
    store.recompute()
    try requireEqual(store.touchBarSummary, "Life 2.8K tokens $0.02", "touch bar lifetime summary")
}

@MainActor
private func testUsageHealthStatus() throws {
    let freshStore = UsageStore(preferences: isolatedPreferences())
    freshStore.recompute()
    try requireEqual(freshStore.healthStatus.title, "Waiting for first scan", "first-scan health title")
    try requireEqual(freshStore.healthStatus.action, .refresh, "first-scan health action")

    let wrongFolder = FileManager.default.temporaryDirectory.appendingPathComponent("CodexUsageMonitorWrongFolder-\(UUID().uuidString)")
    defer {
        try? FileManager.default.removeItem(at: wrongFolder)
    }
    try FileManager.default.createDirectory(at: wrongFolder, withIntermediateDirectories: true)
    let wrongFolderStore = UsageStore(codexHome: wrongFolder, preferences: isolatedPreferences())
    wrongFolderStore.loadFromDiskSynchronously()
    try requireEqual(wrongFolderStore.healthStatus.title, "Not a Codex log folder", "wrong-folder health title")
    try requireEqual(wrongFolderStore.healthStatus.level, .warning, "wrong-folder health level")
    try requireEqual(wrongFolderStore.healthStatus.action, .chooseLogs, "wrong-folder health action")

    let emptyCodexHome = try makeTemporaryCodexHome()
    defer {
        try? FileManager.default.removeItem(at: emptyCodexHome)
    }
    let emptyStore = UsageStore(codexHome: emptyCodexHome, preferences: isolatedPreferences())
    emptyStore.loadFromDiskSynchronously()
    try requireEqual(emptyStore.healthStatus.title, "No Codex logs found", "empty-log health title")
    try requireEqual(emptyStore.healthStatus.level, .warning, "empty-log health level")
    try requireEqual(emptyStore.healthStatus.action, .openLogs, "empty-log health action")

    let metadataOnlyHome = try makeTemporaryCodexHome()
    defer {
        try? FileManager.default.removeItem(at: metadataOnlyHome)
    }
    try writeJSONL(metadataOnlyHome.appendingPathComponent("sessions/rollout-\(currentDayString(daysAgo: 0))-019metadata-only.jsonl"), [
        [
            "type": "session_meta",
            "session_id": "019metadata-only",
            "cwd": "/tmp/Metadata Only",
            "model": "gpt-5.5"
        ]
    ])
    let metadataOnlyStore = UsageStore(codexHome: metadataOnlyHome, preferences: isolatedPreferences())
    metadataOnlyStore.loadFromDiskSynchronously()
    try requireEqual(metadataOnlyStore.healthStatus.title, "No token events loaded", "metadata-only health title")
    try requireEqual(metadataOnlyStore.healthStatus.action, .openLogs, "metadata-only health action")

    let filteredStore = configuredStore()
    filteredStore.setScopeMode(.project)
    filteredStore.setSelectedScope("/tmp/Missing")
    try requireEqual(filteredStore.healthStatus.title, "Filter has no matches", "empty-filter health title")
    try requireEqual(filteredStore.healthStatus.action, .clearFilter, "empty-filter health action")

    let unpricedStore = configuredStore()
    unpricedStore.entries.append(
        makeEntry(
            id: "health-unknown-model",
            daysAgo: 1,
            sessionID: "session-health",
            chatTitle: "Health unknown model",
            projectPath: "/tmp/Health",
            model: "gpt-future-health",
            tokens: UsageTokens(input: 900, cachedInput: 0, output: 100, reasoningOutput: 0, total: 1_000)
        )
    )
    unpricedStore.recompute()
    try requireEqual(unpricedStore.healthStatus.title, "Cost estimate incomplete", "unpriced health title")
    try requireEqual(unpricedStore.healthStatus.detail, "1 model needs rates. 64.2% of logged tokens are priced.", "unpriced health detail grammar")
    try requireEqual(unpricedStore.healthStatus.level, .warning, "unpriced health level")
    try requireEqual(unpricedStore.healthStatus.action, .addRates, "unpriced health action")
}

@MainActor
private func testPreferencesPersistFiltersAndRates() throws {
    let preferences = isolatedPreferences()
    let firstStore = UsageStore(preferences: preferences)
    firstStore.rates = [
        ModelRate(model: "custom-model", inputPerMillion: 3.0, cachedInputPerMillion: 0.3, outputPerMillion: 9.0)
    ]
    firstStore.setDateWindow(.thirtyDays)
    firstStore.setScopeMode(.project)
    firstStore.setSelectedScope("/tmp/Saved Project")
    firstStore.saveRates()

    let secondStore = UsageStore(preferences: preferences)
    try requireEqual(secondStore.dateWindow, .thirtyDays, "saved date window")
    try requireEqual(secondStore.scopeMode, .project, "saved scope mode")
    try requireEqual(secondStore.selectedScopeID, "/tmp/Saved Project", "saved selected scope")
    try requireEqual(secondStore.rates.first?.model, "custom-model", "saved rate model")
    try requireApprox(secondStore.rates.first?.inputPerMillion ?? -1, 3.0, "saved input rate")

    secondStore.setScopeMode(.model)
    secondStore.setSelectedScope("custom-model")
    let thirdStore = UsageStore(preferences: preferences)
    try requireEqual(thirdStore.scopeMode, .model, "model scope mode saved")
    try requireEqual(thirdStore.selectedScopeID, "custom-model", "model selected scope saved")

    thirdStore.setScopeMode(.all)
    let fourthStore = UsageStore(preferences: preferences)
    try requireEqual(fourthStore.scopeMode, .all, "scope mode reset saved")
    try requireEqual(fourthStore.selectedScopeID, "", "selected scope cleared")
}

@MainActor
private func testCodexHomePreferenceCanBeChangedAndReset() throws {
    let preferences = isolatedPreferences()
    let customHome = FileManager.default.temporaryDirectory
        .appendingPathComponent("CodexUsageMonitorCustomHome-\(UUID().uuidString)")
        .appendingPathComponent(".codex")
    defer {
        try? FileManager.default.removeItem(at: customHome.deletingLastPathComponent())
    }
    try FileManager.default.createDirectory(at: customHome.appendingPathComponent("sessions"), withIntermediateDirectories: true)

    let store = UsageStore(preferences: preferences)
    try require(store.usesDefaultCodexHome, "default codex home starts enabled")
    try requireEqual(store.codexHomeDisplayPath, "~/.codex", "default codex home display path")

    store.setCodexHome(customHome)
    try require(!store.usesDefaultCodexHome, "custom codex home enabled")
    try requireEqual(store.codexHomeURL.path, customHome.standardizedFileURL.path, "custom codex home path")
    try requireEqual(store.scanDiagnostics.codexHomePath, customHome.standardizedFileURL.path, "custom codex home diagnostics path")
    try require(store.codexHomeDisplayPath.contains(customHome.deletingLastPathComponent().lastPathComponent), "custom codex home display path")

    let reloaded = UsageStore(preferences: preferences)
    try requireEqual(reloaded.codexHomeURL.path, customHome.standardizedFileURL.path, "custom codex home persists")

    reloaded.resetCodexHome()
    try require(reloaded.usesDefaultCodexHome, "codex home reset to default")
    let afterReset = UsageStore(preferences: preferences)
    try require(afterReset.usesDefaultCodexHome, "reset codex home persists")
    try requireEqual(afterReset.codexHomeURL.path, UsageStore.defaultCodexHomeURL.path, "reset codex home path")
}

@MainActor
private func testUnpricedModelsCanBeAddedToRates() throws {
    let store = configuredStore()
    store.entries.append(
        makeEntry(
            id: "unknown-model",
            daysAgo: 1,
            sessionID: "session-c",
            chatTitle: "Unknown model chat",
            projectPath: "/tmp/Project Three",
            model: "gpt-future-codex-special",
            tokens: UsageTokens(input: 1_000, cachedInput: 0, output: 100, reasoningOutput: 0, total: 1_100)
        )
    )
    store.recompute()

    try requireEqual(store.unpricedModelNames, ["gpt-future-codex-special"], "unpriced model detection")
    try requireEqual(store.pricingCoverage.pricedTokens, 1_800, "unpriced coverage priced tokens")
    try requireEqual(store.pricingCoverage.observedTokens, 2_900, "unpriced coverage observed tokens")
    try requireEqual(store.pricingCoverage.percentText, "62%", "unpriced coverage percent")
    try require(store.touchBarSummary.contains("62% priced"), "Touch Bar marks incomplete pricing")
    try requireApprox(store.summary.cost, 0.01205, "unpriced model does not silently add cost")

    store.addMissingRateRows()
    try require(store.rates.contains { $0.model == "gpt-future-codex-special" }, "missing rate row added")
    try requireEqual(store.unpricedModelNames, ["gpt-future-codex-special"], "zero placeholder still needs rate")

    guard let index = store.rates.firstIndex(where: { $0.model == "gpt-future-codex-special" }) else {
        throw TestFailure(description: "missing added rate row")
    }
    store.rates[index].inputPerMillion = 4.0
    store.rates[index].cachedInputPerMillion = 0.4
    store.rates[index].outputPerMillion = 8.0
    store.saveRates()

    try requireEqual(store.unpricedModelNames, [], "priced model warning clears")
    try requireEqual(store.pricingCoverage.percentText, "100%", "priced model restores complete coverage")
    try requireApprox(store.summary.cost, 0.01685, "custom model rate contributes cost")

    let unknownStore = UsageStore(preferences: isolatedPreferences())
    unknownStore.entries = [
        makeEntry(
            id: "unknown-model-id",
            daysAgo: 1,
            sessionID: "unknown-model-id",
            chatTitle: "Missing model metadata",
            projectPath: "/tmp/Unknown",
            model: "",
            tokens: UsageTokens(input: 100, cachedInput: 0, output: 10, reasoningOutput: 0, total: 110)
        )
    ]
    unknownStore.recompute()
    try requireEqual(unknownStore.unpricedModelNames, ["unknown"], "missing model metadata has a stable rate name")
    unknownStore.addMissingRateRows()
    try require(unknownStore.rates.contains { $0.model == "unknown" }, "missing model metadata receives an editable rate row")
}

@MainActor
private func testPricingCoverageAndSnapshotAliases() throws {
    let store = UsageStore(preferences: isolatedPreferences())
    store.rates = [
        ModelRate(model: "gpt-5.5", inputPerMillion: 10.0, cachedInputPerMillion: 1.0, outputPerMillion: 20.0),
        ModelRate(model: "gpt-5.4-pro", inputPerMillion: 30.0, cachedInputPerMillion: 0, outputPerMillion: 180.0)
    ]
    store.entries = [
        makeEntry(
            id: "snapshot-base",
            daysAgo: 1,
            sessionID: "snapshot-base",
            chatTitle: "Base snapshot",
            projectPath: "/tmp/Pricing",
            model: "gpt-5.5-2026-04-23",
            tokens: UsageTokens(input: 1_000, cachedInput: 400, output: 200, reasoningOutput: 0, total: 1_200)
        ),
        makeEntry(
            id: "snapshot-provider",
            daysAgo: 1,
            sessionID: "snapshot-provider",
            chatTitle: "Provider snapshot",
            projectPath: "/tmp/Pricing",
            model: "openai/gpt-5.4-pro-2026-03-05",
            tokens: UsageTokens(input: 1_000, cachedInput: 0, output: 100, reasoningOutput: 0, total: 1_100)
        ),
        makeEntry(
            id: "similar-name",
            daysAgo: 1,
            sessionID: "similar-name",
            chatTitle: "Similar name",
            projectPath: "/tmp/Pricing",
            model: "gpt-5.5-prototype",
            tokens: UsageTokens(input: 1_000, cachedInput: 0, output: 0, reasoningOutput: 0, total: 1_000)
        ),
        makeEntry(
            id: "partial-pro",
            daysAgo: 1,
            sessionID: "partial-pro",
            chatTitle: "Partial Pro coverage",
            projectPath: "/tmp/Pricing",
            model: "openai/gpt-5.4-pro-2026-03-05",
            tokens: UsageTokens(input: 1_000, cachedInput: 400, output: 0, reasoningOutput: 0, total: 1_000)
        )
    ]
    store.dateWindow = .sevenDays
    store.recompute()

    try requireApprox(store.summary.cost, 0.0764, "snapshot aliases use canonical rates")
    try requireEqual(store.pricingCoverage.pricedTokens, 2_900, "partial rates count only priced components")
    try requireEqual(store.pricingCoverage.observedTokens, 4_300, "pricing coverage counts all observed components")
    try requireEqual(store.pricingCoverage.percentText, "67.4%", "pricing coverage percentage")
    try requireEqual(
        store.unpricedModelNames,
        ["gpt-5.5-prototype", "openai/gpt-5.4-pro-2026-03-05"],
        "safe aliases do not price semantic lookalikes and partial rows stay visible"
    )
    let rateCountBeforeAdding = store.rates.count
    store.addMissingRateRows()
    try requireEqual(store.rates.count, rateCountBeforeAdding + 1, "add rates creates only the truly missing row")
    try require(store.rates.contains { $0.model == "gpt-5.5-prototype" }, "lookalike model receives an editable row")
    try require(!store.rates.contains { $0.model == "openai/gpt-5.4-pro-2026-03-05" }, "partial snapshot does not shadow its canonical rate")

    store.entries = [
        makeEntry(
            id: "invalid-snapshot-date",
            daysAgo: 1,
            sessionID: "invalid-snapshot-date",
            chatTitle: "Invalid snapshot date",
            projectPath: "/tmp/Pricing",
            model: "gpt-5.5-2026-02-31",
            tokens: UsageTokens(input: 500, cachedInput: 0, output: 0, reasoningOutput: 0, total: 500)
        )
    ]
    store.recompute()
    try requireApprox(store.summary.cost, 0, "invalid snapshot dates do not inherit a rate")
    try requireEqual(store.unpricedModelNames, ["gpt-5.5-2026-02-31"], "invalid snapshot dates stay unpriced")
}

@MainActor
private func testCustomRateRowsCanBeEditedAndSanitized() throws {
    let preferences = isolatedPreferences()
    let store = UsageStore(preferences: preferences)
    store.rates = [
        ModelRate(model: "base-model", inputPerMillion: 1.0, cachedInputPerMillion: 0.1, outputPerMillion: 2.0)
    ]

    store.addCustomRateRow()
    try requireEqual(store.rates.count, 2, "custom rate row added")
    try requireEqual(store.rates.last?.model, "custom-model", "custom rate default name")

    store.rates[1].model = " custom-priced-model "
    store.rates[1].inputPerMillion = 4.0
    store.rates[1].cachedInputPerMillion = -1.0
    store.rates[1].outputPerMillion = 8.0
    store.rates.append(ModelRate(model: "custom-priced-model", inputPerMillion: 99.0, cachedInputPerMillion: 99.0, outputPerMillion: 99.0))
    store.rates.append(ModelRate(model: "   ", inputPerMillion: 99.0, cachedInputPerMillion: 99.0, outputPerMillion: 99.0))
    store.saveRates()

    try requireEqual(store.rates.count, 2, "saved rates drop duplicate and blank model rows")
    try requireEqual(store.rates[1].model, "custom-priced-model", "saved rate trims model name")
    try requireApprox(store.rates[1].cachedInputPerMillion, 0, "negative cached rate clamps")

    let reloaded = UsageStore(preferences: preferences)
    try requireEqual(reloaded.rates.count, 2, "sanitized rates persist")
    try requireEqual(reloaded.rates[1].model, "custom-priced-model", "custom model persists")

    reloaded.removeRate(at: 1)
    try requireEqual(reloaded.rates.count, 1, "custom rate row removed")
    reloaded.saveRates()
    let afterRemove = UsageStore(preferences: preferences)
    try requireEqual(afterRemove.rates.count, 1, "removed rate persists")

    afterRemove.removeRate(at: 12)
    try requireEqual(afterRemove.rates.count, 1, "invalid remove ignored")
}

@MainActor
private func testRateDraftsStayTransactionalUntilApplied() throws {
    let store = configuredStore()
    let originalRates = store.rates
    let originalCost = store.summary.cost

    var draft = store.ratesByAddingCustomRow(to: store.rates)
    draft[0].inputPerMillion = 20.0

    try requireEqual(store.rates, originalRates, "draft changes do not mutate live rates")
    try requireApprox(store.summary.cost, originalCost, "draft changes do not alter live estimates")
    try requireEqual(draft.count, originalRates.count + 1, "draft can add a custom rate row")
    try requireEqual(draft.last?.model, "custom-model", "draft custom row gets a stable name")

    store.applyRates(draft)

    try requireEqual(store.rates.count, originalRates.count + 1, "apply commits the draft")
    try requireApprox(store.rates[0].inputPerMillion, 20.0, "apply commits edited rate values")
    try require(store.summary.cost > originalCost, "apply recomputes the cost estimate")
}

@MainActor
private func testDefaultRateSourceAndReset() throws {
    try require(UsageStore.defaultRateSourceSummary.contains("OpenAI API standard short-context rates"), "default rate source profile")
    try require(UsageStore.defaultRateSourceSummary.contains("2026-07-10"), "default rate source date")
    try requireEqual(UsageStore.defaultRateSourceURL.absoluteString, "https://developers.openai.com/api/docs/pricing", "default rate source URL")
    try require(UsageStore.defaultRateLimitations.contains("cache writes"), "default rate limitations disclose missing cache writes")
    try require(UsageStore.defaultRateLimitations.contains("total-only rows use the input rate"), "default rate limitations disclose total-only estimate basis")
    try requireEqual(UsageStore.defaultRates.first?.model, "gpt-5.6-sol", "latest default model is first")
    try requireApprox(UsageStore.defaultRates.first?.inputPerMillion ?? -1, 5.0, "GPT-5.6 Sol input rate")
    try requireApprox(UsageStore.defaultRates.first?.cachedInputPerMillion ?? -1, 0.5, "GPT-5.6 Sol cached rate")
    try requireApprox(UsageStore.defaultRates.first?.outputPerMillion ?? -1, 30.0, "GPT-5.6 Sol output rate")
    try requireApprox(UsageStore.defaultRates.first { $0.model == "gpt-5.5-pro" }?.cachedInputPerMillion ?? -1, 0, "Pro cached rate remains unconfigured")

    let preferences = isolatedPreferences()
    let store = UsageStore(preferences: preferences)
    store.rates = [
        ModelRate(model: "custom-only", inputPerMillion: 9.0, cachedInputPerMillion: 1.0, outputPerMillion: 18.0)
    ]
    store.saveRates()
    store.resetRates()
    try requireEqual(store.rates, UsageStore.defaultRates, "reset restores official default rates")

    let reloaded = UsageStore(preferences: preferences)
    try requireEqual(reloaded.rates, UsageStore.defaultRates, "reset default rates persist")
}

@MainActor
private func testDefaultRateCatalogMigration() throws {
    let preferences = isolatedPreferences()
    let legacyRates = [
        ModelRate(model: "gpt-5.6-sol", inputPerMillion: 0, cachedInputPerMillion: 0, outputPerMillion: 0),
        ModelRate(model: "gpt-5.5", inputPerMillion: 7.0, cachedInputPerMillion: 0.50, outputPerMillion: 30.0),
        ModelRate(model: "gpt-5.5-pro", inputPerMillion: 30.0, cachedInputPerMillion: 30.0, outputPerMillion: 180.0),
        ModelRate(model: "custom-model", inputPerMillion: 4.0, cachedInputPerMillion: 0.4, outputPerMillion: 8.0)
    ]
    preferences.set(try JSONEncoder().encode(legacyRates), forKey: "modelRates.v1")

    let migrated = UsageStore(preferences: preferences)
    try requireEqual(preferences.integer(forKey: "modelRateCatalogVersion.v1"), 3, "rate catalog migration version")
    try requireEqual(migrated.rates.count, UsageStore.defaultRates.count + 1, "migration merges missing defaults once")
    try requireEqual(migrated.rates.first?.model, "gpt-5.6-sol", "migration uses current catalog order")
    try requireEqual(migrated.rates.last?.model, "custom-model", "migration keeps custom rows after built-ins")
    try requireApprox(migrated.rates.first { $0.model == "gpt-5.5" }?.inputPerMillion ?? -1, 7.0, "migration preserves edited rows")
    try requireApprox(migrated.rates.first { $0.model == "gpt-5.5-pro" }?.cachedInputPerMillion ?? -1, 0, "migration corrects untouched legacy Pro row")
    try requireApprox(migrated.rates.first { $0.model == "gpt-5.6-sol" }?.inputPerMillion ?? -1, 5.0, "migration replaces GPT-5.6 placeholder")
    try require(migrated.rates.contains { $0.model == "gpt-5.6-terra" }, "migration adds GPT-5.6 Terra")
    try require(migrated.rates.contains { $0.model == "gpt-5.6-luna" }, "migration adds GPT-5.6 Luna")
    try require(migrated.rates.contains { $0.model == "custom-model" }, "migration preserves custom rows")

    guard let lunaIndex = migrated.rates.firstIndex(where: { $0.model == "gpt-5.6-luna" }) else {
        throw TestFailure(description: "missing migrated GPT-5.6 Luna row")
    }
    migrated.removeRate(at: lunaIndex)
    migrated.saveRates()
    let reloaded = UsageStore(preferences: preferences)
    try require(!reloaded.rates.contains { $0.model == "gpt-5.6-luna" }, "saved removals stay authoritative after migration")

    let versionTwoPreferences = isolatedPreferences()
    var versionTwoRates = UsageStore.defaultRates.filter { $0.model != "gpt-5.6-luna" }
    versionTwoRates.insert(
        ModelRate(model: "custom-first", inputPerMillion: 3.0, cachedInputPerMillion: 0.3, outputPerMillion: 6.0),
        at: 0
    )
    versionTwoPreferences.set(try JSONEncoder().encode(versionTwoRates), forKey: "modelRates.v1")
    versionTwoPreferences.set(2, forKey: "modelRateCatalogVersion.v1")
    let reordered = UsageStore(preferences: versionTwoPreferences)
    try requireEqual(versionTwoPreferences.integer(forKey: "modelRateCatalogVersion.v1"), 3, "version two rates advance to version three")
    try requireEqual(reordered.rates.first?.model, "gpt-5.6-sol", "version three reorders built-in rows")
    try requireEqual(reordered.rates.last?.model, "custom-first", "version three preserves custom row ordering")
    try require(!reordered.rates.contains { $0.model == "gpt-5.6-luna" }, "version three does not resurrect removed rows")
}

@MainActor
private func testRefreshGuardPreventsDuplicateStartupScan() throws {
    let store = UsageStore(preferences: isolatedPreferences())
    try require(store.shouldRefreshOnAppear, "empty idle store should refresh on appear")
    try require(store.isLoadingSelectedWindow, "new store has no loaded window coverage")

    let now = Date(timeIntervalSince1970: 10_000)
    try require(UsageStore.shouldStartBackgroundRefresh(
        isRefreshing: false,
        lastRefreshStartedAt: nil,
        minimumInterval: 60,
        now: now
    ), "first background refresh is allowed")
    try require(!UsageStore.shouldStartBackgroundRefresh(
        isRefreshing: false,
        lastRefreshStartedAt: now.addingTimeInterval(-59),
        minimumInterval: 60,
        now: now
    ), "background refresh is throttled before one minute")
    try require(UsageStore.shouldStartBackgroundRefresh(
        isRefreshing: false,
        lastRefreshStartedAt: now.addingTimeInterval(-60),
        minimumInterval: 60,
        now: now
    ), "background refresh is allowed after one minute")
    try require(UsageStore.shouldApplyScanResult(requestedRevision: 4, currentRevision: 4), "current scan source result is applied")
    try require(!UsageStore.shouldApplyScanResult(requestedRevision: 4, currentRevision: 5), "stale scan source result is rejected")

    store.isRefreshing = true
    try require(!store.shouldRefreshOnAppear, "refreshing empty store should not start duplicate scan")
    try requireEqual(store.refreshInBackgroundIfIdle(), false, "background refresh drops changes while a scan is active")
    try requireEqual(store.refresh(), false, "active refresh should be queued instead of starting another scan")
    try require(store.isRefreshing, "queued refresh keeps current refresh active")
    store.clearParseCache()
    try requireEqual(store.loadMessage, "Wait for the current scan to finish", "cache clear waits for active scan")

    store.isRefreshing = false
    store.entries = [
        makeEntry(
            id: "loaded",
            daysAgo: 0,
            sessionID: "session-loaded",
            chatTitle: "Loaded chat",
            projectPath: "/tmp/Loaded",
            model: "gpt-5.5",
            tokens: UsageTokens(input: 1, cachedInput: 0, output: 1, reasoningOutput: 0, total: 2)
        )
    ]
    try require(!store.shouldRefreshOnAppear, "loaded idle store should not refresh on appear")
}

@MainActor
private func testChangingCodexHomeRejectsStaleScanResults() throws {
    let firstHome = try makeTemporaryCodexHome()
    let secondHome = try makeTemporaryCodexHome()
    let cacheURL = try makeTemporaryCacheURL()
    defer {
        try? FileManager.default.removeItem(at: firstHome)
        try? FileManager.default.removeItem(at: secondHome)
        try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent())
    }

    let firstSessionID = "019stale-source-session"
    let firstSessionFile = firstHome.appendingPathComponent(
        "sessions/rollout-\(currentDayString(daysAgo: 0))-\(firstSessionID).jsonl"
    )
    var firstRows: [[String: Any]] = [[
        "type": "session_meta",
        "session_id": firstSessionID,
        "cwd": "/tmp/Stale Source",
        "model": "gpt-5.5"
    ]]
    for index in 1...5_000 {
        firstRows.append(tokenEvent(
            timestamp: isoString(daysAgo: 0, secondsOffset: Double(index) / 1_000),
            info: [
                "total_token_usage": tokenUsage(
                    input: index * 10,
                    cached: index * 2,
                    output: index,
                    reasoning: 0,
                    total: index * 11
                )
            ]
        ))
    }
    try writeJSONL(firstSessionFile, firstRows)

    let secondSessionID = "019current-source-session"
    try writeJSONL(secondHome.appendingPathComponent("session_index.jsonl"), [
        ["id": secondSessionID, "thread_name": "Current source"]
    ])
    try writeJSONL(
        secondHome.appendingPathComponent("sessions/rollout-\(currentDayString(daysAgo: 0))-\(secondSessionID).jsonl"),
        [
            [
                "type": "session_meta",
                "session_id": secondSessionID,
                "cwd": "/tmp/Current Source",
                "model": "gpt-5.5"
            ],
            tokenEvent(
                timestamp: isoString(daysAgo: 0),
                info: [
                    "total_token_usage": tokenUsage(input: 200, cached: 20, output: 22, reasoning: 2, total: 222)
                ]
            )
        ]
    )

    let store = UsageStore(codexHome: firstHome, preferences: isolatedPreferences(), cacheURL: cacheURL)
    store.dateWindow = .sevenDays
    try require(store.refresh(), "first source scan starts")
    store.setCodexHome(secondHome)
    try requireEqual(store.refresh(), false, "second source scan queues while first scan is active")

    try require(waitUntil(timeout: 10) {
        !store.isRefreshing
            && store.scanDiagnostics.codexHomePath == secondHome.standardizedFileURL.path
            && store.summary.eventCount == 1
    }, "current source scan completes")
    try requireEqual(store.summary.tokens.total, 222, "stale source tokens never reach summary")
    try requireEqual(store.recentRows.first?.title, "Current source", "current source metadata reaches dashboard")
    try requireEqual(store.scanDiagnostics.scannedFileCount, 1, "diagnostics describe current source only")
}

@MainActor
private func testResetCreditDisplay() throws {
    let now = Date(timeIntervalSince1970: 1_000_000)
    try requireEqual(
        UsageStore.resetCreditDisplay(nil, now: now),
        ResetCreditDisplay(value: "No data", detail: "No local snapshot"),
        "nil reset-credit display"
    )
    try requireEqual(
        UsageStore.resetCreditDisplay(RateLimitSnapshot(seenAt: now, planType: "pro", primary: nil, secondary: nil, resetCreditsDescription: "No reset credits in latest local snapshot"), now: now),
        ResetCreditDisplay(value: "None", detail: "No reset credits in latest local snapshot"),
        "no reset-credit display"
    )
    try requireEqual(
        UsageStore.resetCreditDisplay(RateLimitSnapshot(seenAt: now, planType: "pro", primary: nil, secondary: nil, resetCreditsDescription: "3 reset credits available"), now: now),
        ResetCreditDisplay(value: "3", detail: "3 reset credits available"),
        "numeric reset-credit display"
    )

    let partlyExpired = RateLimitSnapshot(
        seenAt: now,
        planType: "pro",
        primary: nil,
        secondary: nil,
        resetCreditsDescription: "2 reset credits with expiry",
        resetCredits: [
            ResetCredit(id: "expired", label: "Expired", expiresAt: now.addingTimeInterval(-1)),
            ResetCredit(id: "active", label: "Active", expiresAt: now.addingTimeInterval(3_600))
        ]
    )
    try requireEqual(
        UsageStore.resetCreditDisplay(partlyExpired, now: now),
        ResetCreditDisplay(value: "1", detail: "1 not expired in latest snapshot"),
        "expired reset credits are not counted as active"
    )

    var fullyExpired = partlyExpired
    fullyExpired.resetCredits[1].expiresAt = now.addingTimeInterval(-10)
    try requireEqual(
        UsageStore.resetCreditDisplay(fullyExpired, now: now),
        ResetCreditDisplay(value: "Expired", detail: "New Codex activity needed", isExpired: true),
        "fully expired reset-credit display"
    )

    try requireEqual(UsageStore.expiryText(nil, now: now), "Expiry unknown", "nil reset-credit expiry")
    try requireEqual(UsageStore.expiryText(now.addingTimeInterval(-1), now: now), "expired", "expired reset-credit expiry")
}

@MainActor
private func testWindowLimitExpiryDisplay() throws {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let active = WindowLimit(usedPercent: 38, windowMinutes: 300, resetsAt: now.addingTimeInterval(9_000))
    try requireEqual(
        UsageStore.windowLimitDisplay(active, snapshotSeenAt: now, now: now),
        WindowLimitDisplay(value: "62% left", detail: "2h 30m left", isExpired: false),
        "active window limit display"
    )

    let passed = WindowLimit(usedPercent: 38, windowMinutes: 300, resetsAt: now.addingTimeInterval(-1))
    try requireEqual(
        UsageStore.windowLimitDisplay(passed, snapshotSeenAt: now.addingTimeInterval(-3_600), now: now),
        WindowLimitDisplay(value: "Expired", detail: "New Codex activity needed", isExpired: true),
        "passed reset does not show a stale percentage"
    )

    let inferredExpired = WindowLimit(usedPercent: 75, windowMinutes: 300, resetsAt: nil)
    try requireEqual(
        UsageStore.windowLimitDisplay(inferredExpired, snapshotSeenAt: now.addingTimeInterval(-18_001), now: now),
        WindowLimitDisplay(value: "Expired", detail: "New Codex activity needed", isExpired: true),
        "window age expires a snapshot without a reset timestamp"
    )
    try requireEqual(
        UsageStore.windowLimitDisplay(inferredExpired, snapshotSeenAt: now, now: now),
        WindowLimitDisplay(value: "25% left", detail: "Reset time unknown", isExpired: false),
        "recent snapshot without reset timestamp"
    )

    let outOfRange = WindowLimit(usedPercent: -20, windowMinutes: 0, resetsAt: nil)
    try requireEqual(UsageStore.percentLeft(outOfRange), "100% left", "percentage left is clamped")
}

@MainActor
private func testAppSettingsPersistStartupPreference() throws {
    let preferences = isolatedPreferences()
    try requireEqual(AppSettings.loadShowWindowOnLaunch(preferences: preferences), true, "default startup window setting")

    let firstSettings = AppSettings(preferences: preferences, refreshLoginStatus: false)
    try requireEqual(firstSettings.showWindowOnLaunch, true, "initial startup window setting")
    try requireEqual(firstSettings.showWindowOnLaunchDetail, "Window opens when the app starts", "initial startup detail")
    try requireEqual(firstSettings.trendMetric, .tokens, "default trend metric")

    firstSettings.setShowWindowOnLaunch(false)
    try requireEqual(AppSettings.loadShowWindowOnLaunch(preferences: preferences), false, "saved quiet startup setting")
    try requireEqual(firstSettings.showWindowOnLaunchDetail, "Starts quietly in the menu bar", "quiet startup detail")

    let secondSettings = AppSettings(preferences: preferences, refreshLoginStatus: false)
    try requireEqual(secondSettings.showWindowOnLaunch, false, "reloaded quiet startup setting")
    secondSettings.setTrendMetric(.cost)
    try requireEqual(AppSettings.loadTrendMetric(preferences: preferences), .cost, "saved cost trend metric")

    secondSettings.setShowWindowOnLaunch(true)
    let thirdSettings = AppSettings(preferences: preferences, refreshLoginStatus: false)
    try requireEqual(thirdSettings.showWindowOnLaunch, true, "reloaded visible startup setting")
    try requireEqual(thirdSettings.trendMetric, .cost, "reloaded cost trend metric")

    let summary = UsageSummary(
        tokens: UsageTokens(input: 100_000, cachedInput: 20_000, output: 23_456, reasoningOutput: 1_000, total: 123_456),
        cost: 12.34,
        sessionCount: 2,
        eventCount: 3
    )

    try requireEqual(thirdSettings.menuBarDisplayMode, .tokens, "default menu bar display mode")
    try requireEqual(thirdSettings.menuBarTitle(summary: summary, pricingCoverage: .empty), "CX 123.5K", "token menu bar title")

    thirdSettings.setMenuBarDisplayMode(.cost)
    try requireEqual(thirdSettings.menuBarTitle(summary: summary, pricingCoverage: .empty), "CX $12.34", "cost menu bar title")

    let fourthSettings = AppSettings(preferences: preferences, refreshLoginStatus: false)
    try requireEqual(fourthSettings.menuBarDisplayMode, .cost, "saved menu bar display mode")

    fourthSettings.setMenuBarDisplayMode(.tokensAndCost)
    try requireEqual(fourthSettings.menuBarTitle(summary: summary, pricingCoverage: .empty), "CX 123.5K / $12.34", "token and cost menu bar title")
    let partialCoverage = PricingCoverage(pricedTokens: 75_000, observedTokens: 123_456)
    try requireEqual(fourthSettings.menuBarTitle(summary: summary, pricingCoverage: partialCoverage), "CX 123.5K / ~$12.34", "menu bar marks incomplete cost")

    try requireEqual(fourthSettings.autoRefreshInterval, .oneMinute, "default auto-refresh interval")
    try requireApprox(fourthSettings.autoRefreshInterval.seconds ?? -1, 60, "default auto-refresh seconds")
    try requireEqual(fourthSettings.autoRefreshInterval.detail, "Watches logs and refreshes every minute", "default auto-refresh detail")

    fourthSettings.setAutoRefreshInterval(.off)
    try require(fourthSettings.autoRefreshInterval.seconds == nil, "off auto-refresh seconds")
    try requireEqual(AppSettings.loadAutoRefreshInterval(preferences: preferences), .off, "saved off auto-refresh interval")

    let fifthSettings = AppSettings(preferences: preferences, refreshLoginStatus: false)
    try requireEqual(fifthSettings.autoRefreshInterval, .off, "reloaded off auto-refresh interval")

    fifthSettings.setAutoRefreshInterval(.fiveMinutes)
    let sixthSettings = AppSettings(preferences: preferences, refreshLoginStatus: false)
    try requireEqual(sixthSettings.autoRefreshInterval, .fiveMinutes, "reloaded five-minute auto-refresh interval")
    try requireEqual(sixthSettings.autoRefreshInterval.menuTitle, "Every 5 Minutes", "five-minute auto-refresh menu title")

    try requireEqual(sixthSettings.budgetNotificationsEnabled, false, "default budget notifications")
    sixthSettings.setBudgetNotificationsEnabled(true)
    try requireEqual(AppSettings.loadBudgetNotificationsEnabled(preferences: preferences), true, "saved budget notifications")
    let seventhSettings = AppSettings(preferences: preferences, refreshLoginStatus: false)
    try requireEqual(seventhSettings.budgetNotificationsEnabled, true, "reloaded budget notifications")
    seventhSettings.setBudgetNotificationsEnabled(false)
    let eighthSettings = AppSettings(preferences: preferences, refreshLoginStatus: false)
    try requireEqual(eighthSettings.budgetNotificationsEnabled, false, "disabled budget notifications")
}

@MainActor
private func testBudgetSettingsAndStatus() throws {
    let preferences = isolatedPreferences()
    let settings = AppSettings(preferences: preferences, refreshLoginStatus: false)
    let summary = UsageSummary(
        tokens: UsageTokens(input: 1_400, cachedInput: 100, output: 500, reasoningOutput: 25, total: 2_000),
        cost: 3.25,
        sessionCount: 1,
        eventCount: 2
    )

    try require(!settings.hasBudgetLimits, "default budget limits off")
    try requireEqual(settings.tokenBudgetStatus(summary: summary).value, "Off", "default token budget status")
    try requireEqual(settings.costBudgetStatus(summary: summary).detail, "Not set", "default cost budget detail")
    try require(!settings.budgetAlert(summary: summary).isVisible, "default budget alert hidden")

    settings.setTokenBudgetLimit(4_000)
    settings.setCostBudgetLimit(6.50)
    try require(settings.hasBudgetLimits, "budget limits enabled")

    let tokenStatus = settings.tokenBudgetStatus(summary: summary)
    try requireEqual(tokenStatus.value, "50%", "token budget percent")
    try requireEqual(tokenStatus.detail, "2.0K of 4.0K tokens", "token budget detail")
    try requireApprox(tokenStatus.fraction, 0.5, "token budget fraction")
    try require(!tokenStatus.isExceeded, "token budget not exceeded")

    let costStatus = settings.costBudgetStatus(summary: summary)
    try requireEqual(costStatus.value, "50%", "cost budget percent")
    try requireEqual(costStatus.detail, "$3.25 of $6.50", "cost budget detail")
    try requireApprox(costStatus.fraction, 0.5, "cost budget fraction")
    try require(!costStatus.isExceeded, "cost budget not exceeded")
    try require(!settings.budgetAlert(summary: summary).isVisible, "half-used budgets do not alert")

    let reloaded = AppSettings(preferences: preferences, refreshLoginStatus: false)
    try requireEqual(reloaded.tokenBudgetLimit, 4_000, "saved token budget")
    try requireApprox(reloaded.costBudgetLimit, 6.50, "saved cost budget")

    let alertSettings = AppSettings(preferences: isolatedPreferences(), refreshLoginStatus: false)
    alertSettings.setTokenBudgetLimit(2_500)
    let warningAlert = alertSettings.budgetAlert(summary: summary)
    try requireEqual(warningAlert.level, .warning, "budget warning level")
    try requireEqual(warningAlert.marker, "!", "budget warning marker")
    try requireEqual(warningAlert.title, "Budget near limit", "budget warning title")
    try requireEqual(warningAlert.detail, "Token budget 80% - 2.0K of 2.5K tokens", "budget warning detail")
    try requireEqual(alertSettings.menuBarTitle(summary: summary, pricingCoverage: .empty), "CX 2.0K !", "warning marker in menu bar title")

    alertSettings.setTokenBudgetLimit(1_000)
    let exceededAlert = alertSettings.budgetAlert(summary: summary)
    try requireEqual(exceededAlert.level, .exceeded, "budget exceeded level")
    try requireEqual(exceededAlert.marker, "!!", "budget exceeded marker")
    try requireEqual(exceededAlert.detail, "Token budget 200% - 2.0K of 1.0K tokens", "budget exceeded detail")
    try requireEqual(alertSettings.menuBarTitle(summary: summary, pricingCoverage: .empty), "CX 2.0K !!", "exceeded marker in menu bar title")

    reloaded.setTokenBudgetLimit(1_000)
    reloaded.setCostBudgetLimit(1.0)
    try requireEqual(reloaded.tokenBudgetStatus(summary: summary).value, "200%", "over token budget percent")
    try requireEqual(reloaded.tokenBudgetStatus(summary: summary).fraction, 1.0, "over token budget fraction clamps")
    try require(reloaded.tokenBudgetStatus(summary: summary).isExceeded, "token budget exceeded")
    try require(reloaded.costBudgetStatus(summary: summary).isExceeded, "cost budget exceeded")

    reloaded.setTokenBudgetLimit(-1)
    reloaded.setCostBudgetLimit(-1)
    try requireEqual(reloaded.tokenBudgetLimit, 0, "negative token budget clamps")
    try requireApprox(reloaded.costBudgetLimit, 0, "negative cost budget clamps")
}

@MainActor
private func testSettingsConfigurationImportExport() throws {
    let sourcePreferences = isolatedPreferences()
    let sourceCodexHome = try makeTemporaryCodexHome()
    let sourceStore = UsageStore(codexHome: sourceCodexHome, preferences: sourcePreferences, cacheURL: try makeTemporaryCacheURL())
    sourceStore.dateWindow = .today
    sourceStore.scopeMode = .model
    sourceStore.selectedScopeID = "gpt-custom"
    sourceStore.rates = [
        ModelRate(model: "gpt-custom", inputPerMillion: 9.0, cachedInputPerMillion: 0.9, outputPerMillion: 18.0),
        ModelRate(model: "gpt-5.4-mini", inputPerMillion: 0.75, cachedInputPerMillion: 0.075, outputPerMillion: 4.50)
    ]
    sourceStore.saveRates()

    let sourceSettings = AppSettings(preferences: sourcePreferences, refreshLoginStatus: false)
    sourceSettings.setShowWindowOnLaunch(false)
    sourceSettings.setMenuBarDisplayMode(.tokensAndCost)
    sourceSettings.setTrendMetric(.cost)
    sourceSettings.setAutoRefreshInterval(.fifteenMinutes)
    sourceSettings.setBudgetNotificationsEnabled(true)
    sourceSettings.setTokenBudgetLimit(12_345)
    sourceSettings.setCostBudgetLimit(67.89)

    let exportedAt = Date(timeIntervalSince1970: 1_800_000_000)
    let configuration = sourceSettings.exportConfiguration(store: sourceStore, exportedAt: exportedAt)
    try requireEqual(configuration.schemaVersion, AppConfiguration.currentSchemaVersion, "settings export schema")
    try requireEqual(configuration.codexHomePath, sourceCodexHome.standardizedFileURL.path, "settings export codex home")
    try requireEqual(configuration.dateWindow, DateWindow.today.rawValue, "settings export window")
    try requireEqual(configuration.scopeMode, ScopeMode.model.rawValue, "settings export scope")
    try requireEqual(configuration.trendMetric, TrendMetric.cost.rawValue, "settings export trend metric")
    try requireEqual(configuration.budgetNotificationsEnabled, true, "settings export budget notifications")
    try requireEqual(configuration.modelRates.count, 2, "settings export rates")

    let data = try AppConfiguration.encode(configuration)
    let decoded = try AppConfiguration.decode(from: data)
    try requireEqual(decoded, configuration, "settings JSON round trip")

    let targetPreferences = isolatedPreferences()
    let targetStore = UsageStore(preferences: targetPreferences, cacheURL: try makeTemporaryCacheURL())
    let targetSettings = AppSettings(preferences: targetPreferences, refreshLoginStatus: false)
    try targetSettings.applyConfiguration(decoded, to: targetStore, refreshAfterImport: false)

    try requireEqual(targetSettings.showWindowOnLaunch, false, "import startup setting")
    try requireEqual(targetSettings.menuBarDisplayMode, .tokensAndCost, "import menu bar display")
    try requireEqual(targetSettings.trendMetric, .cost, "import trend metric")
    try requireEqual(targetSettings.autoRefreshInterval, .fifteenMinutes, "import auto refresh")
    try requireEqual(targetSettings.budgetNotificationsEnabled, true, "import budget notifications")
    try requireEqual(targetSettings.tokenBudgetLimit, 12_345, "import token budget")
    try requireApprox(targetSettings.costBudgetLimit, 67.89, "import cost budget")
    try requireEqual(targetStore.codexHomeURL.path, sourceCodexHome.standardizedFileURL.path, "import codex home")
    try requireEqual(targetStore.dateWindow, .today, "import date window")
    try requireEqual(targetStore.scopeMode, .model, "import scope mode")
    try requireEqual(targetStore.selectedScopeID, "gpt-custom", "import selected scope")
    try requireEqual(targetStore.rates.first?.model, "gpt-custom", "import first rate model")
    try requireApprox(targetStore.rates.first?.inputPerMillion ?? -1, 9.0, "import first rate input")

    let reloadedSettings = AppSettings(preferences: targetPreferences, refreshLoginStatus: false)
    let reloadedStore = UsageStore(preferences: targetPreferences, cacheURL: try makeTemporaryCacheURL())
    try requireEqual(reloadedSettings.menuBarDisplayMode, .tokensAndCost, "persisted imported display mode")
    try requireEqual(reloadedSettings.trendMetric, .cost, "persisted imported trend metric")
    try requireEqual(reloadedSettings.autoRefreshInterval, .fifteenMinutes, "persisted imported auto refresh")
    try requireEqual(reloadedSettings.budgetNotificationsEnabled, true, "persisted imported budget notifications")
    try requireEqual(reloadedSettings.tokenBudgetLimit, 12_345, "persisted imported token budget")
    try requireApprox(reloadedSettings.costBudgetLimit, 67.89, "persisted imported cost budget")
    try requireEqual(reloadedStore.codexHomeURL.path, sourceCodexHome.standardizedFileURL.path, "persisted imported codex home")
    try requireEqual(reloadedStore.dateWindow, .today, "persisted imported date window")
    try requireEqual(reloadedStore.scopeMode, .model, "persisted imported scope mode")
    try requireEqual(reloadedStore.selectedScopeID, "gpt-custom", "persisted imported selected scope")
    try requireEqual(reloadedStore.rates.first?.model, "gpt-custom", "persisted imported rates")

    var unsupported = configuration
    unsupported.schemaVersion = 999
    do {
        _ = try AppConfiguration.decode(from: try AppConfiguration.encode(unsupported))
        throw TestFailure(description: "unsupported settings schema should fail")
    } catch AppConfigurationError.unsupportedVersion(let version) {
        try requireEqual(version, 999, "unsupported schema version")
    }

    var invalidMode = configuration
    invalidMode.menuBarDisplayMode = "Huge Neon Menu Bar"
    do {
        try targetSettings.applyConfiguration(invalidMode, to: targetStore, refreshAfterImport: false)
        throw TestFailure(description: "invalid settings value should fail")
    } catch AppConfigurationError.invalidValue(let field, let value) {
        try requireEqual(field, "menu bar display mode", "invalid settings field")
        try requireEqual(value, "Huge Neon Menu Bar", "invalid settings value")
    }

    var invalidTrend = configuration
    invalidTrend.trendMetric = "Confetti"
    do {
        try targetSettings.applyConfiguration(invalidTrend, to: targetStore, refreshAfterImport: false)
        throw TestFailure(description: "invalid trend metric should fail")
    } catch AppConfigurationError.invalidValue(let field, let value) {
        try requireEqual(field, "trend metric", "invalid trend metric field")
        try requireEqual(value, "Confetti", "invalid trend metric value")
    }

    var legacyConfiguration = configuration
    legacyConfiguration.trendMetric = nil
    let legacyDecoded = try AppConfiguration.decode(from: AppConfiguration.encode(legacyConfiguration))
    try targetSettings.applyConfiguration(legacyDecoded, to: targetStore, refreshAfterImport: false)
    try requireEqual(targetSettings.trendMetric, .tokens, "legacy settings default trend metric")
}

@MainActor
private func testStatusMenuSnapshotLines() throws {
    let store = configuredStore()
    let settings = AppSettings(preferences: isolatedPreferences(), refreshLoginStatus: false)
    settings.setTokenBudgetLimit(3_600)
    settings.setCostBudgetLimit(1.0)

    let lines = settings.statusMenuSnapshotLines(
        summary: store.summary,
        pricingCoverage: store.pricingCoverage,
        windowTitle: store.dateWindow.title,
        scopeDescription: store.activeScopeDescription,
        healthStatus: store.healthStatus
    )

    try requireEqual(lines[0], "Filter: 7 days / All activity", "status menu filter line")
    try require(lines.contains("Tokens: 1.8K"), "status menu token line")
    try require(lines.contains("Estimated cost: $0.01"), "status menu cost line")
    try require(lines.contains("Pricing coverage: 100%"), "status menu pricing coverage line")
    try require(lines.contains("Events: 2 / Chats: 1"), "status menu count line")
    try require(lines.contains("Token budget: 50% - 1.8K of 3.6K tokens"), "status menu token budget line")
    try require(lines.contains("Estimated cost budget: 1% - $0.01 of $1.00"), "status menu cost budget line")
    try requireEqual(lines.last, "Status: Ready", "status menu health line")

    settings.setTokenBudgetLimit(1_000)
    let alertLines = settings.statusMenuSnapshotLines(
        summary: store.summary,
        pricingCoverage: store.pricingCoverage,
        windowTitle: store.dateWindow.title,
        scopeDescription: store.activeScopeDescription,
        healthStatus: store.healthStatus
    )
    try require(alertLines.contains("Budget alert: Budget exceeded - Token budget 180% - 1.8K of 1.0K tokens"), "status menu budget alert line")
    try requireEqual(alertLines.last, "Status: Ready", "status menu health line stays last")
}

@MainActor
private func testDiagnosticReportIncludesSupportContext() throws {
    let store = configuredStore()
    let privateProjectName = store.projectOptionRows[0].label
    store.scopeMode = .project
    store.selectedScopeID = store.projectOptionRows[0].id
    store.recompute()
    store.scanDiagnostics = UsageScanDiagnostics(
        codexHomePath: "/tmp/.codex",
        loadedWindowTitle: "7 days",
        scannedFileCount: 3,
        cachedFileCount: 2,
        cacheSizeBytes: 2_048,
        eventCount: store.summary.eventCount,
        latestEventAt: makeDate(daysAgo: 1),
        latestLimitAt: makeDate(daysAgo: 0),
        completedAt: makeDate(daysAgo: 0)
    )

    let settings = AppSettings(preferences: isolatedPreferences(), refreshLoginStatus: false)
    settings.setTokenBudgetLimit(3_600)
    settings.setCostBudgetLimit(1.0)

    let report = settings.diagnosticReport(
        store: store,
        appVersion: "1.2.3",
        build: "45",
        generatedAt: Date(timeIntervalSince1970: 0)
    )

    try require(report.contains("Codex Usage Monitor Diagnostics"), "diagnostic report title")
    try require(report.contains("Version: 1.2.3 (45)"), "diagnostic report version")
    try require(report.contains("[Summary]"), "diagnostic report summary section")
    try require(report.contains("Scope: Project filter"), "diagnostic report redacts selected scope label")
    try require(!report.contains(privateProjectName), "diagnostic report omits private project name")
    try require(report.contains("[Health]"), "diagnostic report health section")
    try require(report.contains("Ready"), "diagnostic report health status")
    try require(report.contains("[Display]"), "diagnostic report display section")
    try require(report.contains("Menu bar: Tokens"), "diagnostic report menu bar mode")
    try require(report.contains("Auto refresh: 1 min"), "diagnostic report refresh interval")
    try require(report.contains("Token: 50% - 1.8K of 3.6K tokens"), "diagnostic report token budget")
    try require(report.contains("Cost: 1% - $0.01 of $1.00"), "diagnostic report cost budget")
    try require(report.contains("Alert: None"), "diagnostic report budget alert")
    try require(report.contains("Notifications: Off"), "diagnostic report budget notifications")
    try require(report.contains("Trend metric: Tokens"), "diagnostic report trend metric")
    try require(report.contains("Codex home: <custom>/.codex"), "diagnostic report redacts custom codex home")
    try require(!report.contains("/tmp/.codex"), "diagnostic report omits full custom path")
    try require(report.contains("Files scanned: 3"), "diagnostic report file count")
    try require(report.contains("Files from cache: 2"), "diagnostic report cache count")
    try require(report.contains("Cache size: 2 KB"), "diagnostic report cache size")
    try require(report.contains("Parse issues: 0"), "diagnostic report parse issue count")
    try require(report.contains("Latest parse issue: None"), "diagnostic report latest parse issue")
    try require(report.contains("Configured rates: 2"), "diagnostic report configured rates")
    try require(report.contains("Default source: \(UsageStore.defaultRateSourceSummary)"), "diagnostic report rate source")
    try require(report.contains("Pricing URL: \(UsageStore.defaultRateSourceURL.absoluteString)"), "diagnostic report rate URL")
    try require(report.contains("Pricing coverage: 100% (1.8K of 1.8K logged tokens)"), "diagnostic report pricing coverage")
    try require(report.contains("Unpriced models: None"), "diagnostic report unpriced models")
    try require(report.contains("Limitations: \(UsageStore.defaultRateLimitations)"), "diagnostic report pricing limitations")
    try require(report.contains("Reads selected local Codex log folder only."), "diagnostic report local source detail")
    try require(report.contains("Auth files: not read"), "diagnostic report privacy detail")
    try require(report.contains(store.diagnosticSummary), "diagnostic report machine summary")
}

@MainActor
private func testParseCacheReusesAndInvalidatesFiles() throws {
    let codexHome = try buildCodexFixture()
    let cacheURL = try makeTemporaryCacheURL()
    defer {
        try? FileManager.default.removeItem(at: codexHome)
        try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent())
    }

    let firstStore = UsageStore(codexHome: codexHome, preferences: isolatedPreferences(), cacheURL: cacheURL)
    firstStore.dateWindow = .sevenDays
    firstStore.loadFromDiskSynchronously()
    try requireEqual(firstStore.summary.eventCount, 3, "first parse-cache scan event count")
    try requireEqual(firstStore.scanDiagnostics.cachedFileCount, 0, "first parse-cache scan has no cache hits")
    try require(firstStore.scanDiagnostics.cacheSizeBytes > 0, "first parse-cache scan records cache size")
    try require(FileManager.default.fileExists(atPath: cacheURL.path), "parse cache file created")

    let secondStore = UsageStore(codexHome: codexHome, preferences: isolatedPreferences(), cacheURL: cacheURL)
    secondStore.dateWindow = .sevenDays
    secondStore.loadFromDiskSynchronously()
    try requireEqual(secondStore.summary.eventCount, 3, "second parse-cache scan event count")
    try requireEqual(secondStore.scanDiagnostics.cachedFileCount, 2, "second parse-cache scan reuses both files")
    try require(secondStore.scanDiagnostics.cacheSizeBytes > 0, "second parse-cache scan records cache size")

    let sessionFile = codexHome.appendingPathComponent("sessions/rollout-\(currentDayString(daysAgo: 1))-019parser-test-session.jsonl")
    let archivedFile = codexHome.appendingPathComponent("archived_sessions/rollout-\(currentDayString(daysAgo: 2))-019parser-archive-session.jsonl")
    try appendJSONL(
        sessionFile,
        tokenEvent(
            timestamp: isoString(daysAgo: 1, secondsOffset: 30),
            info: [
                "total_token_usage": tokenUsage(input: 1_800, cached: 400, output: 200, reasoning: 25, total: 2_000)
            ]
        )
    )

    let invalidatedStore = UsageStore(codexHome: codexHome, preferences: isolatedPreferences(), cacheURL: cacheURL)
    invalidatedStore.dateWindow = .sevenDays
    invalidatedStore.loadFromDiskSynchronously()
    try requireEqual(invalidatedStore.summary.eventCount, 4, "changed file is reparsed after cache invalidation")
    try requireEqual(invalidatedStore.summary.tokens.total, 2_380, "changed file contributes new token delta")
    try requireEqual(invalidatedStore.scanDiagnostics.cachedFileCount, 1, "unchanged file still comes from cache")

    try FileManager.default.removeItem(at: archivedFile)
    let prunedStore = UsageStore(codexHome: codexHome, preferences: isolatedPreferences(), cacheURL: cacheURL)
    prunedStore.dateWindow = .sevenDays
    prunedStore.loadFromDiskSynchronously()
    try requireEqual(prunedStore.scanDiagnostics.scannedFileCount, 1, "deleted session file no longer scanned")
    try requireEqual(prunedStore.scanDiagnostics.cachedFileCount, 1, "remaining file still comes from cache after prune")
    let prunedCache = try String(contentsOf: cacheURL, encoding: .utf8)
    try require(!prunedCache.contains("019parser-archive-session"), "deleted session file pruned from cache")

    prunedStore.clearParseCache()
    try requireEqual(prunedStore.scanDiagnostics.cachedFileCount, 0, "clear cache resets cache hit count")
    try requireEqual(prunedStore.scanDiagnostics.cacheSizeBytes, 0, "clear cache resets cache size")
    try requireEqual(prunedStore.loadMessage, "Cleared local parse caches", "clear cache status message")
    try require(!FileManager.default.fileExists(atPath: cacheURL.path), "clear cache removes cache file")
}

@MainActor
private func testParseDiagnosticsReportMalformedTokenLines() throws {
    let codexHome = try makeTemporaryCodexHome()
    let cacheURL = try makeTemporaryCacheURL()
    defer {
        try? FileManager.default.removeItem(at: codexHome)
        try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent())
    }

    let sessionID = "019parser-malformed-session"
    try writeJSONL(codexHome.appendingPathComponent("session_index.jsonl"), [
        ["id": sessionID, "thread_name": "Malformed parser fixture"]
    ])

    let sessionFile = codexHome.appendingPathComponent("sessions/rollout-\(currentDayString(daysAgo: 1))-\(sessionID).jsonl")
    let malformedTokenLine = "{\"timestamp\":\"\(isoString(daysAgo: 1))\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"total_tokens\":100}"
    let validLines = try [
        jsonLine([
            "type": "session_meta",
            "session_id": sessionID,
            "cwd": "/tmp/Malformed Parser Project",
            "model": "gpt-5.5"
        ]),
        malformedTokenLine,
        jsonLine(tokenEvent(
            timestamp: isoString(daysAgo: 1, secondsOffset: 10),
            info: [
                "total_token_usage": tokenUsage(input: 400, cached: 100, output: 40, reasoning: 5, total: 440)
            ]
        ))
    ]
    try FileManager.default.createDirectory(at: sessionFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    try (validLines.joined(separator: "\n") + "\n").write(to: sessionFile, atomically: true, encoding: .utf8)

    let store = UsageStore(codexHome: codexHome, preferences: isolatedPreferences(), cacheURL: cacheURL)
    store.dateWindow = .sevenDays
    store.loadFromDiskSynchronously()

    try requireEqual(store.summary.eventCount, 1, "malformed parser keeps valid token event")
    try requireEqual(store.summary.tokens.total, 440, "malformed parser valid token total")
    try requireEqual(store.scanDiagnostics.parseIssueCount, 1, "malformed parser parse issue count")
    try require(store.scanDiagnostics.latestParseIssue?.contains("invalid token JSON") == true, "malformed parser latest issue text")
    try requireEqual(store.healthStatus.title, "Some log lines were skipped", "malformed parser health title")
    try requireEqual(store.healthStatus.level, .warning, "malformed parser health level")
    try require(store.diagnosticSummary.contains("parseIssues=1"), "malformed parser diagnostic summary")

    let report = AppSettings(preferences: isolatedPreferences(), refreshLoginStatus: false).diagnosticReport(store: store)
    try require(report.contains("Parse issues: 1"), "malformed parser diagnostic report parse count")
    try require(report.contains("Latest parse issue:"), "malformed parser diagnostic report latest issue")

    let cachedStore = UsageStore(codexHome: codexHome, preferences: isolatedPreferences(), cacheURL: cacheURL)
    cachedStore.dateWindow = .sevenDays
    cachedStore.loadFromDiskSynchronously()
    try requireEqual(cachedStore.scanDiagnostics.cachedFileCount, 1, "malformed parser cached file count")
    try requireEqual(cachedStore.scanDiagnostics.parseIssueCount, 1, "malformed parser cached parse issue count")
    try requireEqual(cachedStore.healthStatus.title, "Some log lines were skipped", "malformed parser cached health title")
}

@MainActor
private func testParserHandlesCounterResetsAndFallbackRepeats() throws {
    let codexHome = try makeTemporaryCodexHome()
    let cacheURL = try makeTemporaryCacheURL()
    defer {
        try? FileManager.default.removeItem(at: codexHome)
        try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent())
    }

    let sessionID = "019parser-reset-session"
    try writeJSONL(codexHome.appendingPathComponent("session_index.jsonl"), [
        ["id": sessionID, "thread_name": "Counter reset fixture"]
    ])

    let fallbackA = tokenUsage(input: 30, cached: 0, output: 10, reasoning: 0, total: 40)
    let fallbackB = tokenUsage(input: 20, cached: 0, output: 5, reasoning: 0, total: 25)
    let sessionFile = codexHome.appendingPathComponent("sessions/rollout-\(currentDayString(daysAgo: 1))-\(sessionID).jsonl")
    try writeJSONL(sessionFile, [
        [
            "type": "session_meta",
            "session_id": sessionID,
            "cwd": "/tmp/Counter Reset Project",
            "model": "gpt-5.6-luna"
        ],
        tokenEvent(timestamp: isoString(daysAgo: 1), info: [
            "total_token_usage": tokenUsage(input: 80, cached: 0, output: 20, reasoning: 0, total: 100)
        ]),
        tokenEvent(timestamp: isoString(daysAgo: 1, secondsOffset: 1), info: [
            "total_token_usage": tokenUsage(input: 10, cached: 0, output: 10, reasoning: 0, total: 20)
        ]),
        tokenEvent(timestamp: isoString(daysAgo: 1, secondsOffset: 2), info: [
            "total_token_usage": tokenUsage(input: 30, cached: 0, output: 20, reasoning: 0, total: 50)
        ]),
        tokenEvent(timestamp: isoString(daysAgo: 1, secondsOffset: 3), info: ["last_token_usage": fallbackA]),
        tokenEvent(timestamp: isoString(daysAgo: 1, secondsOffset: 4), info: ["last_token_usage": fallbackA]),
        tokenEvent(timestamp: isoString(daysAgo: 1, secondsOffset: 5), info: ["last_token_usage": fallbackB]),
        tokenEvent(timestamp: isoString(daysAgo: 1, secondsOffset: 6), info: ["last_token_usage": fallbackA])
    ])

    let store = UsageStore(codexHome: codexHome, preferences: isolatedPreferences(), cacheURL: cacheURL)
    store.dateWindow = .sevenDays
    store.loadFromDiskSynchronously()

    try requireEqual(store.summary.eventCount, 6, "counter reset and fallback event count")
    try requireEqual(store.summary.tokens.input, 190, "counter reset and fallback input total")
    try requireEqual(store.summary.tokens.output, 65, "counter reset and fallback output total")
    try requireEqual(store.summary.tokens.total, 255, "counter reset and fallback total")
}

@MainActor
private func testParserBoundsOversizedRelevantLines() throws {
    let codexHome = try makeTemporaryCodexHome()
    let cacheURL = try makeTemporaryCacheURL()
    defer {
        try? FileManager.default.removeItem(at: codexHome)
        try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent())
    }

    let sessionID = "019parser-oversized-session"
    try writeJSONL(codexHome.appendingPathComponent("session_index.jsonl"), [
        ["id": sessionID, "thread_name": "Oversized line fixture"]
    ])

    let sessionMeta = try jsonLine([
        "type": "session_meta",
        "session_id": sessionID,
        "cwd": "/tmp/Oversized Line Project",
        "model": "gpt-5.5"
    ])
    let oversizedTokenLine = "{\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"padding\":\"" + String(repeating: "x", count: 8 * 1024 * 1024) + "\"}}"
    let validTokenLine = try jsonLine(tokenEvent(
        timestamp: isoString(daysAgo: 1),
        info: [
            "total_token_usage": tokenUsage(input: 400, cached: 100, output: 40, reasoning: 5, total: 440)
        ]
    ))

    let sessionFile = codexHome.appendingPathComponent("sessions/rollout-\(currentDayString(daysAgo: 1))-\(sessionID).jsonl")
    try FileManager.default.createDirectory(at: sessionFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "\(sessionMeta)\n\(oversizedTokenLine)\n\(validTokenLine)\n".write(to: sessionFile, atomically: true, encoding: .utf8)

    let store = UsageStore(codexHome: codexHome, preferences: isolatedPreferences(), cacheURL: cacheURL)
    store.dateWindow = .sevenDays
    store.loadFromDiskSynchronously()

    try requireEqual(store.summary.eventCount, 1, "oversized parser keeps following valid event")
    try requireEqual(store.summary.tokens.total, 440, "oversized parser valid token total")
    try requireEqual(store.scanDiagnostics.parseIssueCount, 1, "oversized parser issue count")
    try require(store.scanDiagnostics.latestParseIssue?.contains("8 MB safety limit") == true, "oversized parser issue detail")
}

@MainActor
private func testCodexJSONLParsing() throws {
    let codexHome = try buildCodexFixture()
    let cacheURL = try makeTemporaryCacheURL()
    defer {
        try? FileManager.default.removeItem(at: codexHome)
        try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent())
    }

    let store = UsageStore(codexHome: codexHome, cacheURL: cacheURL)
    store.rates = [
        ModelRate(model: "gpt-5.5", inputPerMillion: 10.0, cachedInputPerMillion: 1.0, outputPerMillion: 20.0),
        ModelRate(model: "gpt-5.3-codex", inputPerMillion: 2.0, cachedInputPerMillion: 0.5, outputPerMillion: 8.0)
    ]
    store.dateWindow = .sevenDays
    store.loadFromDiskSynchronously()

    try requireEqual(store.summary.eventCount, 3, "parser event count")
    try requireEqual(store.summary.sessionCount, 2, "parser session count")
    try requireEqual(store.summary.tokens.total, 2_160, "parser total token count")
    try requireEqual(store.summary.tokens.input, 1_900, "parser input token count")
    try requireEqual(store.summary.tokens.cachedInput, 400, "parser cached token count")
    try requireEqual(store.summary.tokens.output, 260, "parser output token count")
    try requireEqual(store.summary.tokens.reasoningOutput, 25, "parser reasoning token count")
    try requireApprox(store.summary.cost, 0.017_99, "parser estimated cost")
    try requireEqual(store.loadMessage, "Loaded 3 token events", "parser load message")
    try requireEqual(store.scanDiagnostics.codexHomePath, codexHome.path, "scan diagnostic codex home path")
    try requireEqual(store.scanDiagnostics.loadedWindowTitle, "14 days", "scan diagnostic loaded window")
    try requireEqual(store.scanDiagnostics.scannedFileCount, 2, "scan diagnostic scanned file count")
    try requireEqual(store.scanDiagnostics.cachedFileCount, 0, "scan diagnostic cached file count")
    try require(store.scanDiagnostics.cacheSizeBytes > 0, "scan diagnostic cache size")
    try requireEqual(store.scanDiagnostics.eventCount, 3, "scan diagnostic event count")
    try require(store.scanDiagnostics.latestEventAt != nil, "scan diagnostic latest event date")
    try require(store.scanDiagnostics.latestLimitAt != nil, "scan diagnostic latest limits date")
    try require(store.scanDiagnostics.completedAt != nil, "scan diagnostic completion date")
    try requireEqual(store.formattedDiagnosticDate(nil), "No data", "nil diagnostic date")
    try require(store.diagnosticSummary.contains("files=2"), "diagnostic summary file count")
    try require(store.diagnosticSummary.contains("cachedFiles=0"), "diagnostic summary cached file count")
    try require(store.diagnosticSummary.contains("cacheBytes="), "diagnostic summary cache size")
    try require(store.diagnosticSummary.contains("parseIssues=0"), "diagnostic summary parse issue count")
    try requireEqual(store.projectRows.count, 2, "parser project row count")
    try require(store.chatRows.contains { $0.label == "Parser fixture" }, "parser session index title")
    try require(store.chatRows.contains { $0.label == "Archived parser fixture" }, "parser archived title")
    try requireEqual(store.latestLimits?.planType, "pro", "parser rate limit plan")
    try requireEqual(store.latestLimits?.resetCreditsDescription, "2 reset credits with expiry", "parser reset credits")
    try requireEqual(store.latestLimits?.resetCredits.count, 2, "parser reset-credit expiry count")
    try requireEqual(store.latestLimits?.resetCredits.first?.label, "Reset Credit 1", "parser reset-credit label")
    try require(store.latestLimits?.resetCredits.first?.expiresAt != nil, "parser reset-credit expiry date")

    let csv = store.csvString()
    try require(csv.contains("Parser fixture"), "parser CSV chat title")
    try require(csv.contains("Archived parser fixture"), "parser CSV archived title")
    try require(!csv.contains("Old parser fixture"), "parser excludes old file from 7-day scan")
}

@MainActor
private func testLongRunningSessionIncludesRecentEvents() throws {
    let codexHome = try makeTemporaryCodexHome()
    let cacheURL = try makeTemporaryCacheURL()
    defer {
        try? FileManager.default.removeItem(at: codexHome)
        try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent())
    }

    let sessionID = "019long-running-session"
    try writeJSONL(codexHome.appendingPathComponent("session_index.jsonl"), [
        ["id": sessionID, "thread_name": "Long-running fixture"]
    ])

    let sessionFile = codexHome.appendingPathComponent(
        "sessions/rollout-\(currentDayString(daysAgo: 45))-\(sessionID).jsonl"
    )
    try writeJSONL(sessionFile, [
        [
            "type": "session_meta",
            "session_id": sessionID,
            "cwd": "/tmp/Long Running Project",
            "model": "gpt-5.5"
        ],
        tokenEvent(
            timestamp: isoString(daysAgo: 45),
            info: [
                "total_token_usage": tokenUsage(input: 900, cached: 100, output: 100, reasoning: 10, total: 1_000)
            ]
        ),
        tokenEvent(
            timestamp: isoString(daysAgo: 1),
            info: [
                "total_token_usage": tokenUsage(input: 1_400, cached: 200, output: 200, reasoning: 20, total: 1_600)
            ]
        )
    ])

    let store = UsageStore(codexHome: codexHome, preferences: isolatedPreferences(), cacheURL: cacheURL)
    store.dateWindow = .sevenDays
    store.loadFromDiskSynchronously()

    try requireEqual(store.scanDiagnostics.scannedFileCount, 1, "long-running session file scanned")
    try requireEqual(store.scanDiagnostics.eventCount, 1, "long-running session clips old events")
    try requireEqual(store.summary.eventCount, 1, "long-running session recent event count")
    try requireEqual(store.summary.sessionCount, 1, "long-running session count")
    try requireEqual(store.summary.tokens.total, 600, "long-running session recent token delta")
    try requireEqual(store.summary.tokens.input, 500, "long-running session recent input delta")
    try requireEqual(store.summary.tokens.cachedInput, 100, "long-running session recent cached delta")
    try requireEqual(store.summary.tokens.output, 100, "long-running session recent output delta")
    try require(!store.isLoadingSelectedWindow, "loaded seven-day window has coverage")

    store.dateWindow = .thirtyDays
    try require(store.isLoadingSelectedWindow, "wider window waits for additional coverage")
}

@MainActor
private func testExtremeNumericLogValuesAreContained() throws {
    let root = try makeTemporaryCodexHome()
    defer { try? FileManager.default.removeItem(at: root) }
    let sessionID = "019extreme-numeric-session"
    try writeJSONL(root.appendingPathComponent("session_index.jsonl"), [
        ["id": sessionID, "thread_name": "Extreme numeric fixture"]
    ])
    try writeJSONL(root.appendingPathComponent("sessions/rollout-\(currentDayString(daysAgo: 0))-\(sessionID).jsonl"), [
        [
            "type": "session_meta",
            "session_id": sessionID,
            "cwd": "/tmp/Numeric Fixture",
            "model": "gpt-5.5"
        ],
        tokenEvent(
            timestamp: isoString(daysAgo: 0),
            info: [
                "total_token_usage": [
                    "input_tokens": 1e100,
                    "cached_input_tokens": -50,
                    "output_tokens": "NaN",
                    "reasoning_output_tokens": -10,
                    "total_tokens": 42
                ]
            ],
            limits: [
                "plan_type": "pro",
                "primary": [
                    "used_percent": "Infinity",
                    "window_minutes": 1e100,
                    "resets_at": 1e100
                ]
            ]
        )
    ])

    let store = UsageStore(codexHome: root, preferences: isolatedPreferences(), cacheURL: try makeTemporaryCacheURL())
    store.dateWindow = .lifetime
    store.loadFromDiskSynchronously()

    try requireEqual(store.summary.tokens, UsageTokens(input: 0, cachedInput: 0, output: 0, reasoningOutput: 0, total: 42), "extreme and negative token fields are contained")
    try requireEqual(store.latestLimits?.primary?.usedPercent, 0, "non-finite limit percentage falls back safely")
    try requireEqual(store.latestLimits?.primary?.windowMinutes, 0, "out-of-range limit window falls back safely")
    try requireEqual(store.latestLimits?.primary?.resetsAt, nil, "out-of-range reset timestamp is ignored")
}

@MainActor
private func testPrivacyManifestDeclaresRequiredReasonAPIs() throws {
    let url = URL(fileURLWithPath: "Resources/PrivacyInfo.xcprivacy")
    let data = try Data(contentsOf: url)
    guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
        throw TestFailure(description: "privacy manifest is not a dictionary")
    }

    try requireEqual(plist["NSPrivacyTracking"] as? Bool, false, "privacy manifest tracking disabled")
    try requireEqual((plist["NSPrivacyCollectedDataTypes"] as? [Any])?.count, 0, "privacy manifest collected data empty")

    guard let accessedTypes = plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]],
          let userDefaults = accessedTypes.first(where: { $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults" }),
          let reasons = userDefaults["NSPrivacyAccessedAPITypeReasons"] as? [String] else {
        throw TestFailure(description: "privacy manifest missing UserDefaults required-reason API entry")
    }
    try require(reasons.contains("CA92.1"), "privacy manifest UserDefaults reason")
}

@main
private struct RunTests {
    @MainActor
    static func main() {
        let tests: [(String, @MainActor () throws -> Void)] = [
            ("seven-day summary and cost", testSevenDaySummaryAndCost),
            ("today window", testTodayWindowFiltersCurrentCalendarDay),
            ("calendar window boundaries", testCalendarWindowBoundaries),
            ("period comparison scope", testComparisonUsesSelectedScope),
            ("scope filtering", testScopeFiltering),
            ("complete scope option lists", testScopeOptionsIncludeAllProjectsChatsAndModels),
            ("CSV export escaping", testCSVExportEscaping),
            ("lifetime total-only cost", testLifetimeIncludesOlderRowsAndTotalOnlyCost),
            ("summary text", testSummaryText),
            ("Touch Bar summary", testTouchBarSummaryText),
            ("usage health status", testUsageHealthStatus),
            ("preference persistence", testPreferencesPersistFiltersAndRates),
            ("Codex home preference", testCodexHomePreferenceCanBeChangedAndReset),
            ("unpriced model rates", testUnpricedModelsCanBeAddedToRates),
            ("pricing coverage and aliases", testPricingCoverageAndSnapshotAliases),
            ("custom rate rows", testCustomRateRowsCanBeEditedAndSanitized),
            ("transactional rate drafts", testRateDraftsStayTransactionalUntilApplied),
            ("default rate source", testDefaultRateSourceAndReset),
            ("default rate catalog migration", testDefaultRateCatalogMigration),
            ("startup refresh guard", testRefreshGuardPreventsDuplicateStartupScan),
            ("scan source consistency", testChangingCodexHomeRejectsStaleScanResults),
            ("reset-credit display", testResetCreditDisplay),
            ("window limit expiry display", testWindowLimitExpiryDisplay),
            ("app startup preference", testAppSettingsPersistStartupPreference),
            ("budget settings", testBudgetSettingsAndStatus),
            ("settings import export", testSettingsConfigurationImportExport),
            ("status menu snapshot", testStatusMenuSnapshotLines),
            ("diagnostic report", testDiagnosticReportIncludesSupportContext),
            ("parse cache", testParseCacheReusesAndInvalidatesFiles),
            ("parse diagnostics", testParseDiagnosticsReportMalformedTokenLines),
            ("counter reset and fallback parsing", testParserHandlesCounterResetsAndFallbackRepeats),
            ("oversized log line bounds", testParserBoundsOversizedRelevantLines),
            ("Codex JSONL parsing", testCodexJSONLParsing),
            ("long-running session parsing", testLongRunningSessionIncludesRecentEvents),
            ("extreme numeric log values", testExtremeNumericLogValuesAreContained),
            ("privacy manifest", testPrivacyManifestDeclaresRequiredReasonAPIs)
        ]

        var failures: [String] = []
        for (name, test) in tests {
            do {
                try test()
                print("PASS \(name)")
            } catch {
                let message = "FAIL \(name): \(error)"
                failures.append(message)
                print(message)
            }
        }

        if failures.isEmpty {
            print("All \(tests.count) tests passed.")
        } else {
            exit(1)
        }
    }
}
