import Darwin
import Foundation
import SwiftUI

struct UsageTokens: Codable, Hashable {
    var input: Int
    var cachedInput: Int
    var output: Int
    var reasoningOutput: Int
    var total: Int

    static let zero = UsageTokens(input: 0, cachedInput: 0, output: 0, reasoningOutput: 0, total: 0)

    static func +(lhs: UsageTokens, rhs: UsageTokens) -> UsageTokens {
        UsageTokens(
            input: lhs.input + rhs.input,
            cachedInput: lhs.cachedInput + rhs.cachedInput,
            output: lhs.output + rhs.output,
            reasoningOutput: lhs.reasoningOutput + rhs.reasoningOutput,
            total: lhs.total + rhs.total
        )
    }

    static func -(lhs: UsageTokens, rhs: UsageTokens) -> UsageTokens {
        UsageTokens(
            input: max(lhs.input - rhs.input, 0),
            cachedInput: max(lhs.cachedInput - rhs.cachedInput, 0),
            output: max(lhs.output - rhs.output, 0),
            reasoningOutput: max(lhs.reasoningOutput - rhs.reasoningOutput, 0),
            total: max(lhs.total - rhs.total, 0)
        )
    }
}

struct UsageEntry: Codable, Identifiable, Hashable {
    let id: String
    let timestamp: Date
    let sessionID: String
    let chatTitle: String
    let projectPath: String
    let model: String
    let tokens: UsageTokens
    let sourceFile: String
}

struct WindowLimit: Codable {
    var usedPercent: Double
    var windowMinutes: Int
    var resetsAt: Date?
}

struct RateLimitSnapshot: Codable {
    var seenAt: Date
    var planType: String
    var primary: WindowLimit?
    var secondary: WindowLimit?
    var resetCreditsDescription: String
    var resetCredits: [ResetCredit] = []
}

struct ResetCredit: Codable, Hashable, Identifiable {
    var id: String
    var label: String
    var expiresAt: Date?
}

struct ModelRate: Codable, Hashable, Identifiable {
    var model: String
    var inputPerMillion: Double
    var cachedInputPerMillion: Double
    var outputPerMillion: Double

    var id: String { model }
}

struct UsageSummary {
    var tokens: UsageTokens
    var cost: Double
    var sessionCount: Int
    var eventCount: Int

    static let empty = UsageSummary(tokens: .zero, cost: 0, sessionCount: 0, eventCount: 0)
}

struct PricingCoverage: Equatable {
    var pricedTokens: Int
    var observedTokens: Int

    static let empty = PricingCoverage(pricedTokens: 0, observedTokens: 0)

    var unpricedTokens: Int {
        max(observedTokens - pricedTokens, 0)
    }

    var fraction: Double {
        guard observedTokens > 0 else {
            return 1
        }
        return min(max(Double(pricedTokens) / Double(observedTokens), 0), 1)
    }

    var isComplete: Bool {
        unpricedTokens == 0
    }

    var percentText: String {
        guard !isComplete else {
            return "100%"
        }
        let percent = floor(fraction * 1_000) / 10
        if percent.rounded(.down) == percent {
            return String(format: "%.0f%%", percent)
        }
        return String(format: "%.1f%%", percent)
    }

    static func +(lhs: PricingCoverage, rhs: PricingCoverage) -> PricingCoverage {
        PricingCoverage(
            pricedTokens: lhs.pricedTokens + rhs.pricedTokens,
            observedTokens: lhs.observedTokens + rhs.observedTokens
        )
    }
}

struct UsageComparison {
    var label: String
    var previousTokens: Int
    var previousCost: Double
    var tokenDelta: Int
    var costDelta: Double
    var tokenDeltaPercent: Double?
    var costDeltaPercent: Double?

    var isVisible: Bool {
        !label.isEmpty
    }

    var hasPreviousActivity: Bool {
        previousTokens > 0 || previousCost > 0
    }

    static let unavailable = UsageComparison(
        label: "",
        previousTokens: 0,
        previousCost: 0,
        tokenDelta: 0,
        costDelta: 0,
        tokenDeltaPercent: nil,
        costDeltaPercent: nil
    )
}

struct BreakdownRow: Identifiable {
    var id: String
    var label: String
    var detail: String
    var tokens: UsageTokens
    var cost: Double
}

struct DailyUsageRow: Identifiable {
    var id: String
    var label: String
    var tokens: UsageTokens
    var cost: Double
}

struct CostComponentRow: Identifiable, Equatable {
    var id: String
    var label: String
    var detail: String
    var tokens: Int
    var cost: Double
    var fraction: Double
}

struct RecentActivityRow: Identifiable {
    var id: String
    var time: String
    var title: String
    var detail: String
    var tokens: UsageTokens
    var cost: Double
}

struct ResetCreditDisplay: Equatable {
    var value: String
    var detail: String
    var isExpired: Bool = false
}

struct WindowLimitDisplay: Equatable {
    var value: String
    var detail: String
    var isExpired: Bool
}

struct UsageScanDiagnostics: Equatable {
    var codexHomePath: String
    var loadedWindowTitle: String
    var scannedFileCount: Int
    var cachedFileCount: Int
    var cacheSizeBytes: UInt64
    var eventCount: Int
    var parseIssueCount: Int = 0
    var latestParseIssue: String?
    var latestEventAt: Date?
    var latestLimitAt: Date?
    var completedAt: Date?

    static func empty(codexHomePath: String) -> UsageScanDiagnostics {
        UsageScanDiagnostics(
            codexHomePath: codexHomePath,
            loadedWindowTitle: "Not loaded",
            scannedFileCount: 0,
            cachedFileCount: 0,
            cacheSizeBytes: 0,
            eventCount: 0,
            parseIssueCount: 0,
            latestParseIssue: nil,
            latestEventAt: nil,
            latestLimitAt: nil,
            completedAt: nil
        )
    }
}

enum UsageHealthLevel: Equatable {
    case info
    case warning
}

enum UsageHealthAction: String, Equatable {
    case refresh = "Refresh"
    case openLogs = "Open Logs"
    case chooseLogs = "Choose Folder"
    case clearFilter = "Clear Filter"
    case addRates = "Add Rates"
}

struct UsageHealthStatus: Equatable {
    var level: UsageHealthLevel
    var title: String
    var detail: String
    var action: UsageHealthAction?

    var isVisible: Bool {
        !title.isEmpty
    }

    static let hidden = UsageHealthStatus(level: .info, title: "", detail: "", action: nil)
}

enum DateWindow: String, CaseIterable, Identifiable {
    case today = "Today"
    case sevenDays = "7d"
    case thirtyDays = "30d"
    case lifetime = "Life"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .sevenDays: return "7 days"
        case .thirtyDays: return "30 days"
        case .lifetime: return "Lifetime"
        }
    }

    var days: Int? {
        switch self {
        case .today: return 1
        case .sevenDays: return 7
        case .thirtyDays: return 30
        case .lifetime: return nil
        }
    }

    var historyDays: Int? {
        guard let days else {
            return nil
        }
        return max(days * 2, 2)
    }

    var comparisonLabel: String {
        switch self {
        case .today: return "yesterday"
        case .sevenDays: return "previous 7d"
        case .thirtyDays: return "previous 30d"
        case .lifetime: return ""
        }
    }

    func startDate(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        switch self {
        case .today:
            return calendar.startOfDay(for: now)
        case .sevenDays, .thirtyDays:
            guard let days else { return nil }
            let today = calendar.startOfDay(for: now)
            return calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? Date.distantPast
        case .lifetime:
            return nil
        }
    }

    func previousRange(now: Date = Date(), calendar: Calendar = .current) -> Range<Date>? {
        guard let days, let currentStart = startDate(now: now, calendar: calendar) else {
            return nil
        }
        guard let previousStart = calendar.date(byAdding: .day, value: -days, to: currentStart) else {
            return nil
        }
        return previousStart..<currentStart
    }
}

enum ScopeMode: String, CaseIterable, Identifiable {
    case all = "All"
    case project = "Project"
    case chat = "Chat"
    case model = "Model"

    var id: String { rawValue }
}

@MainActor
final class UsageStore: ObservableObject {
    @Published var entries: [UsageEntry] = []
    @Published var dateWindow: DateWindow = .sevenDays
    @Published var scopeMode: ScopeMode = .all
    @Published var selectedScopeID: String = ""
    @Published var summary: UsageSummary = .empty
    @Published var projectRows: [BreakdownRow] = []
    @Published var chatRows: [BreakdownRow] = []
    @Published var modelRows: [BreakdownRow] = []
    @Published var dailyRows: [DailyUsageRow] = []
    @Published var costRows: [CostComponentRow] = []
    @Published var recentRows: [RecentActivityRow] = []
    @Published var projectOptionRows: [BreakdownRow] = []
    @Published var chatOptionRows: [BreakdownRow] = []
    @Published var modelOptionRows: [BreakdownRow] = []
    @Published var averageCostPerMillion: Double = 0
    @Published var thirtyDayCostPace: Double = 0
    @Published var comparison: UsageComparison = .unavailable
    @Published var pricingCoverage: PricingCoverage = .empty
    @Published var unpricedModelNames: [String] = []
    @Published var healthStatus: UsageHealthStatus = .hidden
    @Published var latestLimits: RateLimitSnapshot?
    @Published var lastRefreshText: String = "Never"
    @Published var isRefreshing: Bool = false
    @Published var rates: [ModelRate] = UsageStore.defaultRates
    @Published var loadMessage: String = "Reading local Codex logs"
    @Published var scanDiagnostics: UsageScanDiagnostics = .empty(codexHomePath: "~/.codex")

    var statusChanged: ((String) -> Void)?
    var codexHomeChanged: ((URL) -> Void)?

    private var codexHome: URL
    private let cacheURLOverride: URL?
    private let preferences: UserDefaults
    private var loadedDays: Int? = 0
    private var refreshPending = false
    private var lastRefreshStartedAt: Date?
    private var dataSourceRevision: UInt64 = 0

    init(
        codexHome: URL? = nil,
        preferences: UserDefaults = .standard,
        cacheURL: URL? = nil
    ) {
        self.preferences = preferences
        self.codexHome = (codexHome ?? Self.loadSavedCodexHome(preferences: preferences)).standardizedFileURL
        self.cacheURLOverride = cacheURL
        self.dateWindow = Self.loadSavedDateWindow(preferences: preferences)
        self.scopeMode = Self.loadSavedScopeMode(preferences: preferences)
        self.selectedScopeID = preferences.string(forKey: Self.selectedScopeKey) ?? ""
        self.rates = Self.loadSavedRates(preferences: preferences)
        self.scanDiagnostics = .empty(codexHomePath: self.codexHome.path)
    }

    @discardableResult
    func refresh() -> Bool {
        guard !isRefreshing else {
            refreshPending = true
            return false
        }

        isRefreshing = true
        lastRefreshStartedAt = Date()
        loadMessage = "Scanning local Codex sessions"
        let scanDays = dateWindow.historyDays
        let source = makeScanSource()
        let sourceRevision = dataSourceRevision

        DispatchQueue.global(qos: .userInitiated).async {
            let parsed = Self.loadLocalUsage(scanDays: scanDays, source: source)
            DispatchQueue.main.async {
                let sourceIsCurrent = Self.shouldApplyScanResult(
                    requestedRevision: sourceRevision,
                    currentRevision: self.dataSourceRevision
                )
                if sourceIsCurrent {
                    self.applyParsedUsage(parsed, scanDays: scanDays)
                }
                self.isRefreshing = false

                if self.refreshPending || !sourceIsCurrent {
                    self.refreshPending = false
                    self.refresh()
                }
            }
        }
        return true
    }

    @discardableResult
    func refreshIfNeeded() -> Bool {
        guard shouldRefreshOnAppear else {
            return false
        }
        return refresh()
    }

    @discardableResult
    func refreshInBackgroundIfIdle(minimumInterval: TimeInterval = 60) -> Bool {
        guard Self.shouldStartBackgroundRefresh(
            isRefreshing: isRefreshing,
            lastRefreshStartedAt: lastRefreshStartedAt,
            minimumInterval: minimumInterval,
            now: Date()
        ) else {
            return false
        }
        return refresh()
    }

    static func shouldStartBackgroundRefresh(
        isRefreshing: Bool,
        lastRefreshStartedAt: Date?,
        minimumInterval: TimeInterval,
        now: Date
    ) -> Bool {
        guard !isRefreshing else {
            return false
        }
        guard let lastRefreshStartedAt else {
            return true
        }
        return now.timeIntervalSince(lastRefreshStartedAt) >= max(minimumInterval, 1)
    }

    static func shouldApplyScanResult(requestedRevision: UInt64, currentRevision: UInt64) -> Bool {
        requestedRevision == currentRevision
    }

    var shouldRefreshOnAppear: Bool {
        entries.isEmpty && !isRefreshing
    }

    var isLoadingSelectedWindow: Bool {
        !hasCoverage(for: dateWindow) || (entries.isEmpty && isRefreshing)
    }

    func loadFromDiskSynchronously() {
        let parsed = Self.loadLocalUsage(scanDays: dateWindow.historyDays, source: makeScanSource())
        applyParsedUsage(parsed, scanDays: dateWindow.historyDays)
    }

    private var cacheURL: URL? {
        cacheURLOverride ?? Self.defaultCacheURL(codexHome: codexHome)
    }

    private func makeScanSource() -> UsageScanSource {
        UsageScanSource(codexHome: codexHome, cacheURL: cacheURL)
    }

    func recompute() {
        let now = Date()
        let windowed = entriesInSelectedWindow(now: now)
        projectOptionRows = makeBreakdown(entries: windowed, by: { $0.projectPath }, label: { Self.shortProjectName($0.projectPath) }, limit: nil)
        chatOptionRows = makeBreakdown(entries: windowed, by: { $0.sessionID }, label: { $0.chatTitle }, limit: nil)
        modelOptionRows = makeBreakdown(entries: windowed, by: { $0.model }, label: { $0.model.isEmpty ? "unknown" : $0.model }, limit: nil)

        let visible = applyScope(to: windowed)
        let visibleSummary = makeSummary(entries: visible)
        summary = visibleSummary
        averageCostPerMillion = Self.averageCostPerMillion(tokens: visibleSummary.tokens.total, cost: visibleSummary.cost)
        thirtyDayCostPace = makeThirtyDayCostPace(entries: visible, cost: visibleSummary.cost)
        comparison = makeComparison(current: visibleSummary, now: now)
        costRows = makeCostRows(entries: visible, totalCost: visibleSummary.cost)
        projectRows = makeBreakdown(entries: visible, by: { $0.projectPath }, label: { Self.shortProjectName($0.projectPath) })
        chatRows = makeBreakdown(entries: visible, by: { $0.sessionID }, label: { $0.chatTitle })
        modelRows = makeBreakdown(entries: visible, by: { $0.model }, label: { $0.model.isEmpty ? "unknown" : $0.model })
        dailyRows = makeDailyRows(entries: visible, now: now)
        recentRows = makeRecentRows(entries: visible)
        pricingCoverage = makePricingCoverage(entries: visible)
        unpricedModelNames = makeUnpricedModelNames(entries: visible)
        healthStatus = makeHealthStatus(windowed: windowed, visible: visible)
        statusChanged?(menuTitle)
    }

    func setDateWindow(_ value: DateWindow) {
        dateWindow = value
        preferences.set(value.rawValue, forKey: Self.dateWindowKey)
        if hasCoverage(for: value) {
            recompute()
        } else {
            refresh()
        }
    }

    func setScopeMode(_ value: ScopeMode) {
        scopeMode = value
        selectedScopeID = ""
        preferences.set(value.rawValue, forKey: Self.scopeModeKey)
        preferences.removeObject(forKey: Self.selectedScopeKey)
        recompute()
    }

    func setSelectedScope(_ value: String) {
        selectedScopeID = value
        if value.isEmpty {
            preferences.removeObject(forKey: Self.selectedScopeKey)
        } else {
            preferences.set(value, forKey: Self.selectedScopeKey)
        }
        recompute()
    }

    func saveRates() {
        rates = Self.sanitizedRates(rates)
        Self.persistRates(rates, preferences: preferences)
        recompute()
    }

    func applyRates(_ values: [ModelRate]) {
        rates = values
        saveRates()
    }

    func resetRates() {
        rates = Self.defaultRates
        saveRates()
    }

    func addMissingRateRows() {
        let updatedRates = ratesByAddingMissingRows(to: rates)
        guard updatedRates != rates else {
            return
        }
        applyRates(updatedRates)
    }

    func ratesByAddingMissingRows(to values: [ModelRate]) -> [ModelRate] {
        var updatedRates = values
        var knownModels = Set(values.map { Self.normalizedModelIdentifier($0.model) })
        let additions = unpricedModelNames
            .compactMap { missingRateRowModel(for: $0) }
            .filter { knownModels.insert(Self.normalizedModelIdentifier($0)).inserted }
            .map(Self.zeroRate)
        updatedRates.append(contentsOf: additions)
        return updatedRates
    }

    func addCustomRateRow() {
        rates = ratesByAddingCustomRow(to: rates)
        recompute()
    }

    func ratesByAddingCustomRow(to values: [ModelRate]) -> [ModelRate] {
        var updatedRates = values
        updatedRates.append(Self.zeroRate(Self.nextCustomModelName(existing: values.map(\.model))))
        return updatedRates
    }

    func removeRate(at index: Int) {
        guard rates.indices.contains(index) else {
            return
        }
        rates.remove(at: index)
        recompute()
    }

    func clearParseCache() {
        guard !isRefreshing else {
            loadMessage = "Wait for the current scan to finish"
            return
        }
        guard let cacheURL else {
            loadMessage = "No parse cache configured"
            return
        }

        let removalURL = cacheURLOverride == nil ? cacheURL.deletingLastPathComponent() : cacheURL
        do {
            if FileManager.default.fileExists(atPath: removalURL.path) {
                try FileManager.default.removeItem(at: removalURL)
            }
            var diagnostics = scanDiagnostics
            diagnostics.cachedFileCount = 0
            diagnostics.cacheSizeBytes = 0
            scanDiagnostics = diagnostics
            loadMessage = "Cleared local parse caches"
        } catch {
            loadMessage = "Could not clear parse caches"
        }
    }

    var codexHomeURL: URL {
        codexHome
    }

    var codexHomeDisplayPath: String {
        Self.displayPath(codexHome)
    }

    var configurationCodexHomePath: String? {
        usesDefaultCodexHome ? nil : codexHome.path
    }

    var usesDefaultCodexHome: Bool {
        codexHome.standardizedFileURL.path == Self.defaultCodexHome.standardizedFileURL.path
    }

    func setCodexHome(_ url: URL) {
        let newCodexHome = url.standardizedFileURL
        guard newCodexHome.path != codexHome.path else {
            return
        }
        codexHome = newCodexHome
        dataSourceRevision &+= 1
        preferences.set(codexHome.path, forKey: Self.codexHomePathKey)
        resetLoadedUsage(message: "Codex log folder changed")
        codexHomeChanged?(codexHome)
    }

    func resetCodexHome() {
        guard codexHome.path != Self.defaultCodexHome.path else {
            return
        }
        codexHome = Self.defaultCodexHome
        dataSourceRevision &+= 1
        preferences.removeObject(forKey: Self.codexHomePathKey)
        resetLoadedUsage(message: "Using default Codex log folder")
        codexHomeChanged?(codexHome)
    }

    func applyConfiguration(
        codexHomePath: String?,
        dateWindow importedDateWindow: DateWindow,
        scopeMode importedScopeMode: ScopeMode,
        selectedScopeID importedScopeID: String,
        rates importedRates: [ModelRate]
    ) -> Bool {
        let newCodexHome = Self.codexHomeURL(fromConfigurationPath: codexHomePath)
        let codexHomeChanged = newCodexHome.path != codexHome.standardizedFileURL.path

        codexHome = newCodexHome
        if codexHomeChanged {
            dataSourceRevision &+= 1
        }
        if newCodexHome.path == Self.defaultCodexHome.path {
            preferences.removeObject(forKey: Self.codexHomePathKey)
        } else {
            preferences.set(newCodexHome.path, forKey: Self.codexHomePathKey)
        }

        dateWindow = importedDateWindow
        preferences.set(dateWindow.rawValue, forKey: Self.dateWindowKey)
        scopeMode = importedScopeMode
        preferences.set(scopeMode.rawValue, forKey: Self.scopeModeKey)
        selectedScopeID = importedScopeID.trimmingCharacters(in: .whitespacesAndNewlines)
        if selectedScopeID.isEmpty {
            preferences.removeObject(forKey: Self.selectedScopeKey)
        } else {
            preferences.set(selectedScopeID, forKey: Self.selectedScopeKey)
        }

        rates = Self.sanitizedRates(importedRates)
        Self.persistRates(rates, preferences: preferences)

        if codexHomeChanged {
            resetLoadedUsage(message: "Imported settings")
            self.codexHomeChanged?(codexHome)
            return true
        }

        if hasCoverage(for: dateWindow) {
            recompute()
            return false
        }

        loadMessage = "Imported settings"
        return true
    }

    var menuTitle: String {
        let tokens = Self.compactNumber(summary.tokens.total)
        return "CX \(tokens)"
    }

    var touchBarSummary: String {
        let base = "\(dateWindow.rawValue) \(Self.compactNumber(summary.tokens.total)) tokens \(Self.currency(summary.cost))"
        guard pricingCoverage.observedTokens > 0, !pricingCoverage.isComplete else {
            return base
        }
        return "\(base) / \(pricingCoverage.percentText) priced"
    }

    var activeScopeDescription: String {
        scopeDescription
    }

    var diagnosticSummary: String {
        [
            "events=\(summary.eventCount)",
            "sessions=\(summary.sessionCount)",
            "tokens=\(summary.tokens.total)",
            "input=\(summary.tokens.input)",
            "cached=\(summary.tokens.cachedInput)",
            "output=\(summary.tokens.output)",
            "cost=\(Self.currency(summary.cost))",
            "pricedTokens=\(pricingCoverage.pricedTokens)",
            "priceableTokens=\(pricingCoverage.observedTokens)",
            "unpricedModels=\(unpricedModelNames.count)",
            "window=\(dateWindow.title)",
            "loadedWindow=\(scanDiagnostics.loadedWindowTitle)",
            "files=\(scanDiagnostics.scannedFileCount)",
            "cachedFiles=\(scanDiagnostics.cachedFileCount)",
            "cacheBytes=\(scanDiagnostics.cacheSizeBytes)",
            "parseIssues=\(scanDiagnostics.parseIssueCount)"
        ].joined(separator: " ")
    }

    func formattedDiagnosticDate(_ date: Date?) -> String {
        guard let date else {
            return "No data"
        }
        return Self.diagnosticDateFormatter.string(from: date)
    }

    var scopeOptions: [BreakdownRow] {
        switch scopeMode {
        case .all: return []
        case .project: return projectOptionRows
        case .chat: return chatOptionRows
        case .model: return modelOptionRows
        }
    }

    func filteredEntries() -> [UsageEntry] {
        applyScope(to: entriesInSelectedWindow())
    }

    func summaryText(redactScope: Bool = false) -> String {
        var lines = [
            "Codex Usage Monitor",
            "Window: \(dateWindow.title)",
            "Scope: \(redactScope ? diagnosticScopeDescription : scopeDescription)",
            "Status: \(healthStatus.isVisible ? healthStatus.title : "Ready")",
            "Tokens: \(Self.compactNumber(summary.tokens.total))",
            "Estimated cost: \(Self.currency(summary.cost))",
            "Pricing coverage: \(pricingCoverageDescription)",
            "Average cost / 1M tokens: \(Self.currency(averageCostPerMillion))",
            "30-day cost pace: \(Self.currency(thirtyDayCostPace))",
            "Events: \(summary.eventCount)",
            "Chats: \(summary.sessionCount)"
        ]

        if comparison.isVisible {
            lines.append("Compared with \(comparison.label): \(Self.signedCompactNumber(comparison.tokenDelta)) tokens, \(Self.signedCurrency(comparison.costDelta))")
        }
        if !costRows.isEmpty {
            let mix = costRows.map { "\($0.label) \(Self.currency($0.cost))" }.joined(separator: ", ")
            lines.append("Cost mix: \(mix)")
        }
        lines.append("Pricing limits: \(Self.defaultRateLimitations)")

        return lines.joined(separator: "\n")
    }

    var pricingCoverageDescription: String {
        "\(pricingCoverage.percentText) (\(Self.compactNumber(pricingCoverage.pricedTokens)) of \(Self.compactNumber(pricingCoverage.observedTokens)) logged tokens)"
    }

    func csvString() -> String {
        let header = [
            "timestamp",
            "project",
            "chat",
            "model",
            "input_tokens",
            "cached_input_tokens",
            "output_tokens",
            "reasoning_tokens",
            "total_tokens",
            "estimated_cost_usd",
            "source"
        ].joined(separator: ",")

        let rows = filteredEntries()
            .sorted { $0.timestamp < $1.timestamp }
            .map { entry in
                [
                    Self.csvEscape(entry.timestamp.formatted(Self.fractionalISOFormatStyle)),
                    Self.csvEscape(entry.projectPath),
                    Self.csvEscape(entry.chatTitle),
                    Self.csvEscape(entry.model),
                    "\(entry.tokens.input)",
                    "\(entry.tokens.cachedInput)",
                    "\(entry.tokens.output)",
                    "\(entry.tokens.reasoningOutput)",
                    "\(entry.tokens.total)",
                    String(format: "%.6f", cost(for: entry)),
                    Self.csvEscape(entry.sourceFile)
                ].joined(separator: ",")
            }

        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    private func entriesInSelectedWindow(now: Date = Date()) -> [UsageEntry] {
        let cutoff = dateWindow.startDate(now: now)
        return entries.filter { entry in
            if let cutoff, entry.timestamp < cutoff { return false }
            return true
        }
    }

    private func entries(in range: Range<Date>) -> [UsageEntry] {
        entries.filter { entry in
            range.contains(entry.timestamp)
        }
    }

    private func applyScope(to entries: [UsageEntry]) -> [UsageEntry] {
        entries.filter { entry in
            switch scopeMode {
            case .all:
                return true
            case .project:
                return selectedScopeID.isEmpty || entry.projectPath == selectedScopeID
            case .chat:
                return selectedScopeID.isEmpty || entry.sessionID == selectedScopeID
            case .model:
                return selectedScopeID.isEmpty || entry.model == selectedScopeID
            }
        }
    }

    private func makeSummary(entries: [UsageEntry]) -> UsageSummary {
        let totalTokens = entries.reduce(UsageTokens.zero) { $0 + $1.tokens }
        let totalCost = entries.reduce(0) { $0 + cost(for: $1) }
        let sessions = Set(entries.map(\.sessionID)).count
        return UsageSummary(tokens: totalTokens, cost: totalCost, sessionCount: sessions, eventCount: entries.count)
    }

    private func makeComparison(current: UsageSummary, now: Date) -> UsageComparison {
        guard let previousRange = dateWindow.previousRange(now: now) else {
            return .unavailable
        }

        let previous = makeSummary(entries: applyScope(to: entries(in: previousRange)))
        return UsageComparison(
            label: dateWindow.comparisonLabel,
            previousTokens: previous.tokens.total,
            previousCost: previous.cost,
            tokenDelta: current.tokens.total - previous.tokens.total,
            costDelta: current.cost - previous.cost,
            tokenDeltaPercent: Self.deltaPercent(current: Double(current.tokens.total), previous: Double(previous.tokens.total)),
            costDeltaPercent: Self.deltaPercent(current: current.cost, previous: previous.cost)
        )
    }

    private func makeBreakdown(entries: [UsageEntry], by key: (UsageEntry) -> String, label: (UsageEntry) -> String, limit: Int? = 8) -> [BreakdownRow] {
        var grouped: [String: (label: String, tokens: UsageTokens, cost: Double, count: Int)] = [:]
        for entry in entries {
            let id = key(entry).isEmpty ? "unknown" : key(entry)
            let name = label(entry).isEmpty ? "Unknown" : label(entry)
            let existing = grouped[id] ?? (name, .zero, 0, 0)
            grouped[id] = (
                label: existing.label,
                tokens: existing.tokens + entry.tokens,
                cost: existing.cost + cost(for: entry),
                count: existing.count + 1
            )
        }
        let rows = grouped.map { key, value in
            BreakdownRow(
                id: key,
                label: value.label,
                detail: "\(value.count) events",
                tokens: value.tokens,
                cost: value.cost
            )
        }
        .sorted { $0.tokens.total > $1.tokens.total }
        guard let limit else {
            return rows
        }
        return rows.prefix(limit).map { $0 }
    }

    private func makeDailyRows(entries: [UsageEntry], now: Date) -> [DailyUsageRow] {
        guard !entries.isEmpty else {
            return []
        }

        let calendar = Calendar.current
        var grouped: [Date: (tokens: UsageTokens, cost: Double)] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.timestamp)
            let existing = grouped[day] ?? (.zero, 0)
            grouped[day] = (
                tokens: existing.tokens + entry.tokens,
                cost: existing.cost + cost(for: entry)
            )
        }

        let visibleDayCount: Int
        let endDay: Date
        switch dateWindow {
        case .today:
            visibleDayCount = 1
            endDay = calendar.startOfDay(for: now)
        case .sevenDays:
            visibleDayCount = 7
            endDay = calendar.startOfDay(for: now)
        case .thirtyDays:
            visibleDayCount = 14
            endDay = calendar.startOfDay(for: now)
        case .lifetime:
            visibleDayCount = 14
            endDay = grouped.keys.max() ?? calendar.startOfDay(for: now)
        }

        guard let startDay = calendar.date(byAdding: .day, value: -(visibleDayCount - 1), to: endDay) else {
            return []
        }

        return (0..<visibleDayCount).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDay) else {
                return nil
            }
            let value = grouped[day] ?? (.zero, 0)
            return DailyUsageRow(
                id: Self.dayIDFormatter.string(from: day),
                label: Self.shortDayFormatter.string(from: day),
                tokens: value.tokens,
                cost: value.cost
            )
        }
    }

    private func makeThirtyDayCostPace(entries: [UsageEntry], cost: Double) -> Double {
        guard cost > 0 else {
            return 0
        }
        let days: Double
        if let windowDays = dateWindow.days {
            days = Double(max(windowDays, 1))
        } else {
            days = Self.activeDayCount(entries: entries)
        }
        return cost / max(days, 1) * 30
    }

    private func makeCostRows(entries: [UsageEntry], totalCost: Double) -> [CostComponentRow] {
        let components = entries.reduce(CostComponents.zero) { partial, entry in
            partial + costComponents(for: entry)
        }
        let specs: [(id: String, label: String, detail: String, tokens: Int, cost: Double)] = [
            ("input", "Input", "Non-cached input", components.inputTokens, components.inputCost),
            ("cached", "Cached", "Cached input", components.cachedInputTokens, components.cachedInputCost),
            ("output", "Output", "Output tokens", components.outputTokens, components.outputCost),
            ("total", "Total-only", "Older log totals", components.totalOnlyTokens, components.totalOnlyCost)
        ]

        return specs.compactMap { spec in
            guard spec.tokens > 0 || spec.cost > 0 else {
                return nil
            }
            let rawFraction = totalCost > 0 ? spec.cost / totalCost : 0
            return CostComponentRow(
                id: spec.id,
                label: spec.label,
                detail: spec.detail,
                tokens: spec.tokens,
                cost: spec.cost,
                fraction: min(max(rawFraction, 0), 1)
            )
        }
    }

    private func makeRecentRows(entries: [UsageEntry]) -> [RecentActivityRow] {
        entries
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(6)
            .map { entry in
                RecentActivityRow(
                    id: entry.id,
                    time: Self.activityTimeFormatter.string(from: entry.timestamp),
                    title: entry.chatTitle.isEmpty ? "Untitled chat" : entry.chatTitle,
                    detail: "\(Self.shortProjectName(entry.projectPath)) / \(entry.model.isEmpty ? "unknown" : entry.model)",
                    tokens: entry.tokens,
                    cost: cost(for: entry)
                )
            }
    }

    private func cost(for entry: UsageEntry) -> Double {
        costComponents(for: entry).totalCost
    }

    private func costComponents(for entry: UsageEntry) -> CostComponents {
        let rate = rateForModel(entry.model)
        let components = BillableTokenComponents(tokens: entry.tokens)
        return CostComponents(
            inputTokens: components.inputTokens,
            cachedInputTokens: components.cachedInputTokens,
            outputTokens: components.outputTokens,
            totalOnlyTokens: components.totalOnlyTokens,
            inputCost: Double(components.inputTokens) * rate.inputPerMillion / 1_000_000,
            cachedInputCost: Double(components.cachedInputTokens) * rate.cachedInputPerMillion / 1_000_000,
            outputCost: Double(components.outputTokens) * rate.outputPerMillion / 1_000_000,
            totalOnlyCost: Double(components.totalOnlyTokens) * rate.inputPerMillion / 1_000_000
        )
    }

    private func rateForModel(_ model: String) -> ModelRate {
        configuredRateForModel(model) ?? Self.zeroRate(model)
    }

    private func configuredRateForModel(_ model: String) -> ModelRate? {
        let normalized = Self.normalizedModelIdentifier(model)
        if let exact = rates.first(where: { Self.normalizedModelIdentifier($0.model) == normalized }) {
            return exact
        }

        guard let canonicalModel = Self.canonicalBuiltInModel(for: normalized) else {
            return nil
        }
        return rates.first { Self.normalizedModelIdentifier($0.model) == canonicalModel }
    }

    private static func normalizedModelIdentifier(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? "unknown" : normalized
    }

    private func missingRateRowModel(for model: String) -> String? {
        let normalized = Self.normalizedModelIdentifier(model)
        if rates.contains(where: { Self.normalizedModelIdentifier($0.model) == normalized }) {
            return nil
        }
        guard let canonicalModel = Self.canonicalBuiltInModel(for: normalized) else {
            return model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "unknown" : model
        }
        if rates.contains(where: { Self.normalizedModelIdentifier($0.model) == canonicalModel }) {
            return nil
        }
        return Self.defaultRates.first {
            Self.normalizedModelIdentifier($0.model) == canonicalModel
        }?.model ?? canonicalModel
    }

    private static func canonicalBuiltInModel(for normalizedModel: String) -> String? {
        let leaf = normalizedModel.split(separator: "/").last.map(String.init) ?? normalizedModel
        let builtInModels = defaultRates
            .map { normalizedModelIdentifier($0.model) }
            .sorted { $0.count > $1.count }

        return builtInModels.first { baseModel in
            leaf == baseModel || isDateSnapshot(leaf, of: baseModel)
        }
    }

    private static func isDateSnapshot(_ candidate: String, of baseModel: String) -> Bool {
        let prefix = baseModel + "-"
        guard candidate.hasPrefix(prefix) else {
            return false
        }
        let parts = candidate.dropFirst(prefix.count).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return false
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            return false
        }
        let validated = calendar.dateComponents([.year, .month, .day], from: date)
        return (2_000...2_999).contains(year)
            && validated.year == year
            && validated.month == month
            && validated.day == day
    }

    private func makePricingCoverage(entries: [UsageEntry]) -> PricingCoverage {
        entries.reduce(.empty) { partial, entry in
            partial + pricingCoverage(for: entry)
        }
    }

    private func pricingCoverage(for entry: UsageEntry) -> PricingCoverage {
        let components = BillableTokenComponents(tokens: entry.tokens)
        guard components.totalTokens > 0,
              let rate = configuredRateForModel(entry.model) else {
            return PricingCoverage(pricedTokens: 0, observedTokens: components.totalTokens)
        }

        var pricedTokens = 0
        if rate.inputPerMillion > 0 {
            pricedTokens += components.inputTokens + components.totalOnlyTokens
        }
        if rate.cachedInputPerMillion > 0 {
            pricedTokens += components.cachedInputTokens
        }
        if rate.outputPerMillion > 0 {
            pricedTokens += components.outputTokens
        }
        return PricingCoverage(pricedTokens: pricedTokens, observedTokens: components.totalTokens)
    }

    private func makeUnpricedModelNames(entries: [UsageEntry]) -> [String] {
        var grouped: [String: Int] = [:]
        for entry in entries {
            let coverage = pricingCoverage(for: entry)
            guard coverage.unpricedTokens > 0 else {
                continue
            }
            let model = entry.model.isEmpty ? "unknown" : entry.model
            grouped[model, default: 0] += coverage.unpricedTokens
        }
        return grouped
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .map(\.key)
    }

    private func makeHealthStatus(windowed: [UsageEntry], visible: [UsageEntry]) -> UsageHealthStatus {
        if entries.isEmpty && scanDiagnostics.completedAt == nil {
            return UsageHealthStatus(
                level: .info,
                title: "Waiting for first scan",
                detail: "Refresh to read local Codex session logs.",
                action: .refresh
            )
        }

        if entries.isEmpty && scanDiagnostics.scannedFileCount == 0 && !codexHomeHasExpectedShape() {
            return UsageHealthStatus(
                level: .warning,
                title: "Not a Codex log folder",
                detail: "Choose the folder that contains sessions, archived_sessions, or session_index.jsonl.",
                action: .chooseLogs
            )
        }

        if entries.isEmpty && scanDiagnostics.scannedFileCount == 0 {
            return UsageHealthStatus(
                level: .warning,
                title: "No Codex logs found",
                detail: "No session JSONL files were found under \(codexHome.path).",
                action: .openLogs
            )
        }

        if scanDiagnostics.parseIssueCount > 0 {
            return UsageHealthStatus(
                level: .warning,
                title: "Some log lines were skipped",
                detail: "\(scanDiagnostics.parseIssueCount) malformed or unreadable line\(scanDiagnostics.parseIssueCount == 1 ? "" : "s") found in the latest scan.",
                action: .openLogs
            )
        }

        if entries.isEmpty {
            return UsageHealthStatus(
                level: .info,
                title: "No token events loaded",
                detail: "Scanned \(scanDiagnostics.scannedFileCount) file\(scanDiagnostics.scannedFileCount == 1 ? "" : "s") but found no token usage events.",
                action: .openLogs
            )
        }

        if windowed.isEmpty {
            return UsageHealthStatus(
                level: .info,
                title: "No activity in \(dateWindow.title)",
                detail: "Switch to Lifetime or refresh after new Codex work.",
                action: .refresh
            )
        }

        if visible.isEmpty && scopeMode != .all {
            return UsageHealthStatus(
                level: .info,
                title: "Filter has no matches",
                detail: "Clear the current \(scopeMode.rawValue.lowercased()) target or choose another one.",
                action: .clearFilter
            )
        }

        if !unpricedModelNames.isEmpty {
            let count = unpricedModelNames.count
            return UsageHealthStatus(
                level: .warning,
                title: "Cost estimate incomplete",
                detail: "\(count) model\(count == 1 ? "" : "s") \(count == 1 ? "needs" : "need") rates. \(pricingCoverage.percentText) of logged tokens are priced.",
                action: .addRates
            )
        }

        return .hidden
    }

    private func codexHomeHasExpectedShape() -> Bool {
        let fileManager = FileManager.default
        let expectedPaths = [
            codexHome.appendingPathComponent("sessions").path,
            codexHome.appendingPathComponent("archived_sessions").path,
            codexHome.appendingPathComponent("session_index.jsonl").path
        ]
        return expectedPaths.contains { fileManager.fileExists(atPath: $0) }
    }

    private var scopeDescription: String {
        switch scopeMode {
        case .all:
            return "All activity"
        case .project:
            if selectedScopeID.isEmpty { return "Any project" }
            return projectOptionRows.first { $0.id == selectedScopeID }?.label ?? "Selected project"
        case .chat:
            if selectedScopeID.isEmpty { return "Any chat" }
            return chatOptionRows.first { $0.id == selectedScopeID }?.label ?? "Selected chat"
        case .model:
            if selectedScopeID.isEmpty { return "Any model" }
            return modelOptionRows.first { $0.id == selectedScopeID }?.label ?? "Selected model"
        }
    }

    private var diagnosticScopeDescription: String {
        switch scopeMode {
        case .all: return "All activity"
        case .project: return "Project filter"
        case .chat: return "Chat filter"
        case .model: return "Model filter"
        }
    }

    private func hasCoverage(for window: DateWindow) -> Bool {
        guard let neededDays = window.historyDays else {
            return loadedDays == nil
        }
        guard let loadedDays else {
            return true
        }
        return loadedDays >= neededDays
    }

    private func applyParsedUsage(_ parsed: LocalUsageParseResult, scanDays: Int?) {
        let sortedEntries = parsed.entries.sorted { $0.timestamp > $1.timestamp }
        entries = sortedEntries
        latestLimits = parsed.latestLimit
        loadedDays = scanDays
        lastRefreshText = Self.timeFormatter.string(from: Date())
        loadMessage = sortedEntries.isEmpty ? "No token events found yet" : "Loaded \(sortedEntries.count) token events"
        scanDiagnostics = UsageScanDiagnostics(
            codexHomePath: codexHome.path,
            loadedWindowTitle: Self.windowTitle(forDays: scanDays),
            scannedFileCount: parsed.scannedFileCount,
            cachedFileCount: parsed.cachedFileCount,
            cacheSizeBytes: parsed.cacheSizeBytes,
            eventCount: sortedEntries.count,
            parseIssueCount: parsed.parseIssueCount,
            latestParseIssue: parsed.latestParseIssue,
            latestEventAt: sortedEntries.first?.timestamp,
            latestLimitAt: parsed.latestLimit?.seenAt,
            completedAt: Date()
        )
        recompute()
    }

    private func resetLoadedUsage(message: String) {
        entries = []
        latestLimits = nil
        loadedDays = 0
        lastRefreshText = "Never"
        loadMessage = message
        scanDiagnostics = .empty(codexHomePath: codexHome.path)
        recompute()
    }

    nonisolated private static func loadLocalUsage(scanDays: Int?, source: UsageScanSource) -> LocalUsageParseResult {
        let index = loadSessionIndex(codexHome: source.codexHome)
        let loadedCache = loadParseCache(
            index: index,
            indexSignature: sessionIndexSignature(codexHome: source.codexHome),
            source: source
        )
        var cache = loadedCache.cache
        var cacheChanged = loadedCache.needsRewrite
        var cachedFileCount = 0
        let cutoff = Self.scanCutoff(forDays: scanDays)
        let files = sessionFiles(cutoff: cutoff, codexHome: source.codexHome)
        var allEntries: [UsageEntry] = []
        var latestLimit: RateLimitSnapshot?
        var seenEntryIDs = Set<String>()
        var parseIssueCount = 0
        var latestParseIssue: String?

        if pruneMissingCacheFiles(in: &cache) {
            cacheChanged = true
        }

        for file in files {
            let parsed = cachedOrParsedSessionFile(
                file,
                index: index,
                cache: &cache,
                cacheChanged: &cacheChanged,
                cachedFileCount: &cachedFileCount
            )
            for entry in parsed.entries where cutoff.map({ entry.timestamp >= $0 }) ?? true {
                guard seenEntryIDs.insert(entry.id).inserted else {
                    continue
                }
                allEntries.append(entry)
            }
            parseIssueCount += parsed.parseIssueCount
            if let issue = parsed.latestParseIssue {
                latestParseIssue = issue
            }
            if let limit = parsed.latestLimit {
                let isWithinLoadedWindow = cutoff.map { limit.seenAt >= $0 } ?? true
                if isWithinLoadedWindow && (latestLimit == nil || limit.seenAt > latestLimit!.seenAt) {
                    latestLimit = limit
                }
            }
        }

        if cacheChanged {
            saveParseCache(cache, index: index, cacheURL: source.cacheURL)
        }

        return LocalUsageParseResult(
            entries: allEntries,
            latestLimit: latestLimit,
            scannedFileCount: files.count,
            cachedFileCount: cachedFileCount,
            cacheSizeBytes: cacheFileSize(cacheURL: source.cacheURL),
            parseIssueCount: parseIssueCount,
            latestParseIssue: latestParseIssue
        )
    }

    nonisolated private static func loadSessionIndex(codexHome: URL) -> [String: String] {
        let indexURL = codexHome.appendingPathComponent("session_index.jsonl")
        guard let content = try? String(contentsOf: indexURL, encoding: .utf8) else {
            return [:]
        }
        var result: [String: String] = [:]
        for rawLine in content.split(separator: "\n") {
            guard let object = jsonObject(String(rawLine)),
                  let id = object["id"] as? String else {
                continue
            }
            result[id] = object["thread_name"] as? String ?? id
        }
        return result
    }

    nonisolated private static func sessionIndexSignature(codexHome: URL) -> String {
        fileSignature(for: codexHome.appendingPathComponent("session_index.jsonl"))?.cacheKey ?? "missing"
    }

    nonisolated private static func cachedOrParsedSessionFile(
        _ url: URL,
        index: [String: String],
        cache: inout UsageParseCache,
        cacheChanged: inout Bool,
        cachedFileCount: inout Int
    ) -> CachedSessionParse {
        guard let signature = fileSignature(for: url) else {
            return CachedSessionParse(entries: [], latestLimit: nil, parseIssueCount: 1, latestParseIssue: "Could not inspect \(url.lastPathComponent)")
        }

        let key = url.path
        if let cached = cache.files[key],
           cached.size == signature.size,
           cached.modifiedAt == signature.modifiedAt {
            cachedFileCount += 1
            return CachedSessionParse(
                entries: cached.entries,
                latestLimit: cached.latestLimit,
                parseIssueCount: cached.parseIssueCount,
                latestParseIssue: cached.latestParseIssue
            )
        }

        let parsed = parseSessionFile(url, index: index)
        cache.files[key] = CachedSessionFile(
            size: signature.size,
            modifiedAt: signature.modifiedAt,
            entries: parsed.entries,
            latestLimit: parsed.latestLimit,
            parseIssueCount: parsed.parseIssueCount,
            latestParseIssue: parsed.latestParseIssue
        )
        cacheChanged = true
        return CachedSessionParse(
            entries: parsed.entries,
            latestLimit: parsed.latestLimit,
            parseIssueCount: parsed.parseIssueCount,
            latestParseIssue: parsed.latestParseIssue
        )
    }

    nonisolated private static func loadParseCache(
        index: [String: String],
        indexSignature: String,
        source: UsageScanSource
    ) -> (cache: UsageParseCache, needsRewrite: Bool) {
        let empty = UsageParseCache(
            version: Self.parseCacheVersion,
            codexHomePath: source.codexHome.path,
            indexSignature: indexSignature,
            files: [:]
        )
        guard let cacheURL = source.cacheURL else {
            return (empty, false)
        }
        guard let data = try? Data(contentsOf: cacheURL) else {
            return (empty, false)
        }
        guard var cache = try? JSONDecoder().decode(UsageParseCache.self, from: data),
              cache.version == Self.parseCacheVersion,
              cache.codexHomePath == source.codexHome.path else {
            return (empty, true)
        }
        guard cache.indexSignature != indexSignature else {
            return (cache, false)
        }
        cache = retitledParseCache(cache, index: index, indexSignature: indexSignature)
        return (cache, true)
    }

    nonisolated private static func retitledParseCache(
        _ cache: UsageParseCache,
        index: [String: String],
        indexSignature: String
    ) -> UsageParseCache {
        var updated = cache
        updated.indexSignature = indexSignature
        updated.files = cache.files.mapValues { cachedFile in
            var updatedFile = cachedFile
            updatedFile.entries = cachedFile.entries.map { entry in
                let chatTitle = index[entry.sessionID] ?? entry.sessionID
                guard chatTitle != entry.chatTitle else {
                    return entry
                }
                return UsageEntry(
                    id: entry.id,
                    timestamp: entry.timestamp,
                    sessionID: entry.sessionID,
                    chatTitle: chatTitle,
                    projectPath: entry.projectPath,
                    model: entry.model,
                    tokens: entry.tokens,
                    sourceFile: entry.sourceFile
                )
            }
            return updatedFile
        }
        return updated
    }

    nonisolated private static func pruneMissingCacheFiles(in cache: inout UsageParseCache) -> Bool {
        let existingFiles = cache.files.filter { key, _ in
            FileManager.default.fileExists(atPath: key)
        }
        guard existingFiles.count != cache.files.count else {
            return false
        }
        cache.files = existingFiles
        return true
    }

    nonisolated private static func saveParseCache(
        _ cache: UsageParseCache,
        index: [String: String],
        cacheURL: URL?
    ) {
        guard let cacheURL else {
            return
        }
        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let lockURL = cacheURL.appendingPathExtension("lock")
            let lockDescriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, mode_t(S_IRUSR | S_IWUSR))
            guard lockDescriptor >= 0 else {
                return
            }
            defer { Darwin.close(lockDescriptor) }
            guard Darwin.lockf(lockDescriptor, F_LOCK, 0) == 0 else {
                return
            }
            defer { Darwin.lockf(lockDescriptor, F_ULOCK, 0) }

            var cacheToSave = cache
            if let existingData = try? Data(contentsOf: cacheURL),
               let existingCache = try? JSONDecoder().decode(UsageParseCache.self, from: existingData),
               existingCache.version == cache.version,
               existingCache.codexHomePath == cache.codexHomePath {
                cacheToSave = mergedParseCache(cache, existingCache: existingCache, index: index)
            }
            let data = try JSONEncoder().encode(cacheToSave)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            return
        }
    }

    nonisolated private static func mergedParseCache(
        _ cache: UsageParseCache,
        existingCache: UsageParseCache,
        index: [String: String]
    ) -> UsageParseCache {
        let existing = retitledParseCache(
            existingCache,
            index: index,
            indexSignature: cache.indexSignature
        )
        let paths = Set(cache.files.keys).union(existing.files.keys)
        var merged = cache
        merged.files = [:]

        for path in paths {
            guard let signature = fileSignature(for: URL(fileURLWithPath: path)) else {
                continue
            }
            if let candidate = cache.files[path], cachedFile(candidate, matches: signature) {
                merged.files[path] = candidate
            } else if let candidate = existing.files[path], cachedFile(candidate, matches: signature) {
                merged.files[path] = candidate
            }
        }
        return merged
    }

    nonisolated private static func cachedFile(_ cachedFile: CachedSessionFile, matches signature: FileSignature) -> Bool {
        cachedFile.size == signature.size && cachedFile.modifiedAt == signature.modifiedAt
    }

    nonisolated private static func cacheFileSize(cacheURL: URL?) -> UInt64 {
        guard let cacheURL,
              let attributes = try? FileManager.default.attributesOfItem(atPath: cacheURL.path) else {
            return 0
        }
        return (attributes[.size] as? NSNumber)?.uint64Value ?? 0
    }

    nonisolated private static func fileSignature(for url: URL) -> FileSignature? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let modifiedAt = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return FileSignature(size: size, modifiedAt: modifiedAt)
    }

    nonisolated private static func scanCutoff(forDays days: Int?, now: Date = Date()) -> Date? {
        guard let days else {
            return nil
        }
        return Calendar.current.date(byAdding: .day, value: -(days + 1), to: now)
    }

    nonisolated private static func sessionFiles(cutoff: Date?, codexHome: URL) -> [URL] {
        let folders = [
            codexHome.appendingPathComponent("sessions"),
            codexHome.appendingPathComponent("archived_sessions")
        ]
        let resourceKeys: [URLResourceKey] = [.contentModificationDateKey]
        var urls: [URL] = []
        for folder in folders {
            guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: resourceKeys) else {
                continue
            }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                if let cutoff, !fileMayContainEvents(url, since: cutoff) {
                    continue
                }
                urls.append(url)
            }
        }
        return urls.sorted { $0.path > $1.path }
    }

    nonisolated private static func fileMayContainEvents(_ url: URL, since cutoff: Date) -> Bool {
        let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let newestKnownDate = [sessionDate(from: url), modifiedAt].compactMap { $0 }.max()
        return newestKnownDate.map { $0 >= cutoff } ?? true
    }

    nonisolated private static func sessionDate(from url: URL) -> Date? {
        let name = url.deletingPathExtension().lastPathComponent
        guard let rolloutRange = name.range(of: "rollout-") else {
            return nil
        }
        let start = rolloutRange.upperBound
        guard name.distance(from: start, to: name.endIndex) >= 10 else {
            return nil
        }
        let end = name.index(start, offsetBy: 10)
        let components = name[start..<end].split(separator: "-")
        guard components.count == 3,
              let year = Int(components[0]),
              let month = Int(components[1]),
              let day = Int(components[2]) else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    nonisolated private static func parseSessionFile(_ url: URL, index: [String: String]) -> CachedSessionParse {
        var sessionID = sessionIDFromFilename(url) ?? url.deletingPathExtension().lastPathComponent
        var chatTitle = index[sessionID] ?? sessionID
        var currentProject = ""
        var currentModel = "unknown"
        var previousTotal: UsageTokens?
        var previousFallbackUsage: UsageTokens?
        var entries: [UsageEntry] = []
        var latestLimit: RateLimitSnapshot?
        var parseIssueCount = 0
        var latestParseIssue: String?

        func recordParseIssue(_ message: String, lineNumber: Int? = nil) {
            parseIssueCount += 1
            if let lineNumber {
                latestParseIssue = "\(url.lastPathComponent):\(lineNumber + 1) \(message)"
            } else {
                latestParseIssue = "\(url.lastPathComponent) \(message)"
            }
        }

        let lineDiagnostics = forEachLine(in: url) { line, lineNumber in
            if line.contains("\"type\":\"session_meta\"") {
                if let id = extractStringField("session_id", from: line) ?? extractStringField("id", from: line) {
                    sessionID = id
                    chatTitle = index[id] ?? chatTitle
                }
                if let cwd = extractStringField("cwd", from: line) {
                    currentProject = cwd
                }
                if let model = extractStringField("model", from: line) {
                    currentModel = model
                }
                return
            }

            if line.contains("\"type\":\"turn_context\"") {
                if let cwd = extractStringField("cwd", from: line) {
                    currentProject = cwd
                }
                if let model = extractStringField("model", from: line) {
                    currentModel = model
                }
                return
            }

            guard line.contains("\"type\":\"token_count\"") else {
                return
            }

            guard let object = jsonObject(line) else {
                recordParseIssue("invalid token JSON", lineNumber: lineNumber)
                return
            }

            guard let timestamp = parseDate(object["timestamp"] as? String) else {
                recordParseIssue("missing token timestamp", lineNumber: lineNumber)
                return
            }

            guard let type = object["type"] as? String,
                  let payload = object["payload"] as? [String: Any] else {
                recordParseIssue("missing token payload", lineNumber: lineNumber)
                return
            }

            guard type == "event_msg",
                  let eventType = payload["type"] as? String,
                  eventType == "token_count" else {
                return
            }

            if let limit = parseRateLimit(payload: payload, seenAt: timestamp) {
                latestLimit = limit
            }

            guard let info = payload["info"] as? [String: Any] else {
                return
            }

            if let totalDict = info["total_token_usage"] as? [String: Any] {
                let total = tokens(from: totalDict)
                if total.total > 0 {
                    let usage: UsageTokens
                    if let previousTotal {
                        usage = total.total < previousTotal.total ? total : total - previousTotal
                    } else {
                        usage = total
                    }
                    if usage.total > 0 {
                        entries.append(makeEntry(timestamp: timestamp, sessionID: sessionID, chatTitle: chatTitle, project: currentProject, model: currentModel, tokens: usage, file: url, line: lineNumber))
                    }
                    previousTotal = total
                    previousFallbackUsage = nil
                    return
                }
            }

            if let lastDict = info["last_token_usage"] as? [String: Any] {
                let fallback = tokens(from: lastDict)
                if fallback.total > 0 && fallback != previousFallbackUsage {
                    entries.append(makeEntry(timestamp: timestamp, sessionID: sessionID, chatTitle: chatTitle, project: currentProject, model: currentModel, tokens: fallback, file: url, line: lineNumber))
                }
                previousFallbackUsage = fallback
            }
        }

        parseIssueCount += lineDiagnostics.issueCount
        if let latestIssue = lineDiagnostics.latestIssue {
            latestParseIssue = "\(url.lastPathComponent) \(latestIssue)"
        }

        return CachedSessionParse(
            entries: entries,
            latestLimit: latestLimit,
            parseIssueCount: parseIssueCount,
            latestParseIssue: latestParseIssue
        )
    }

    nonisolated private static func forEachLine(in url: URL, _ body: (String, Int) -> Void) -> LineReadDiagnostics {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return LineReadDiagnostics(issueCount: 1, latestIssue: "could not open for reading")
        }
        defer {
            try? handle.close()
        }

        var buffer = Data()
        var lineNumber = 0
        var issueCount = 0
        var latestIssue: String?
        var discardingOversizedLine = false
        let newline = Data([10])

        func recordLineIssue(_ message: String) {
            issueCount += 1
            latestIssue = "line \(lineNumber + 1) \(message)"
        }

        func processLine(_ lineData: Data) {
            defer { lineNumber += 1 }
            guard shouldDecodeLine(lineData) else {
                return
            }
            guard lineData.count <= Self.maximumLogLineBytes else {
                recordLineIssue("exceeds the 8 MB safety limit")
                return
            }
            let dataForString = lineData.range(of: Self.tokenCountMarker) == nil ? lineData.prefix(8192) : lineData[...]
            if let line = String(data: Data(dataForString), encoding: .utf8) {
                body(line, lineNumber)
            } else {
                recordLineIssue("is not valid UTF-8")
            }
        }

        while true {
            let chunk: Data?
            do {
                chunk = try handle.read(upToCount: 64 * 1024)
            } catch {
                issueCount += 1
                latestIssue = "read failed"
                break
            }
            guard let chunk, !chunk.isEmpty else {
                break
            }
            buffer.append(chunk)

            while let range = buffer.range(of: newline) {
                let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                if discardingOversizedLine {
                    discardingOversizedLine = false
                    lineNumber += 1
                    continue
                }
                processLine(lineData)
            }

            if buffer.count > Self.maximumLogLineBytes {
                if !discardingOversizedLine && shouldDecodeLine(buffer) {
                    recordLineIssue("exceeds the 8 MB safety limit")
                }
                buffer.removeAll(keepingCapacity: true)
                discardingOversizedLine = true
            }
        }

        if !buffer.isEmpty, !discardingOversizedLine {
            processLine(buffer)
        }

        return LineReadDiagnostics(issueCount: issueCount, latestIssue: latestIssue)
    }

    nonisolated private static func shouldDecodeLine(_ data: Data) -> Bool {
        data.range(of: Self.sessionMetaMarker) != nil ||
            data.range(of: Self.turnContextMarker) != nil ||
            data.range(of: Self.tokenCountMarker) != nil
    }

    nonisolated private static func extractStringField(_ field: String, from line: String) -> String? {
        let key = "\"\(field)\":\""
        guard let start = line.range(of: key)?.upperBound else {
            return nil
        }

        var result = ""
        var escaped = false
        for character in line[start...] {
            if escaped {
                switch character {
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                case "/": result.append("/")
                case "n": result.append("\n")
                case "t": result.append("\t")
                default: result.append(character)
                }
                escaped = false
                continue
            }
            if character == "\\" {
                escaped = true
                continue
            }
            if character == "\"" {
                return result
            }
            result.append(character)
        }
        return nil
    }

    nonisolated private static func makeEntry(timestamp: Date, sessionID: String, chatTitle: String, project: String, model: String, tokens: UsageTokens, file: URL, line: Int) -> UsageEntry {
        let key = [
            sessionID,
            timestamp.formatted(Self.fractionalISOFormatStyle),
            String(tokens.input),
            String(tokens.cachedInput),
            String(tokens.output),
            String(tokens.reasoningOutput),
            String(tokens.total)
        ].joined(separator: ":")
        return UsageEntry(
            id: key,
            timestamp: timestamp,
            sessionID: sessionID,
            chatTitle: chatTitle,
            projectPath: project.isEmpty ? "Unknown project" : project,
            model: model.isEmpty ? "unknown" : model,
            tokens: tokens,
            sourceFile: "\(file.lastPathComponent):\(line + 1)"
        )
    }

    nonisolated private static func parseRateLimit(payload: [String: Any], seenAt: Date) -> RateLimitSnapshot? {
        guard let limits = payload["rate_limits"] as? [String: Any] else {
            return nil
        }
        let plan = limits["plan_type"] as? String ?? "unknown"
        let resetCredits = parseResetCredits(limits["credits"])
        let credits = resetCreditsDescription(limits["credits"], parsedCredits: resetCredits)
        return RateLimitSnapshot(
            seenAt: seenAt,
            planType: plan,
            primary: parseWindowLimit(limits["primary"]),
            secondary: parseWindowLimit(limits["secondary"]),
            resetCreditsDescription: credits,
            resetCredits: resetCredits
        )
    }

    nonisolated private static func parseWindowLimit(_ value: Any?) -> WindowLimit? {
        guard let dict = value as? [String: Any] else {
            return nil
        }
        let used = doubleValue(dict["used_percent"]) ?? 0
        let minutes = intValue(dict["window_minutes"]) ?? 0
        let resetDate = intValue(dict["resets_at"]).map { Date(timeIntervalSince1970: TimeInterval($0)) }
        return WindowLimit(usedPercent: used, windowMinutes: minutes, resetsAt: resetDate)
    }

    nonisolated private static func resetCreditsDescription(_ value: Any?, parsedCredits: [ResetCredit]) -> String {
        if value == nil || value is NSNull {
            return "No reset credits in latest local snapshot"
        }
        if !parsedCredits.isEmpty {
            return "\(parsedCredits.count) reset credit\(parsedCredits.count == 1 ? "" : "s") with expiry"
        }
        if let array = value as? [Any] {
            return "\(array.count) reset credits reported"
        }
        if let dict = value as? [String: Any] {
            if let available = intValue(dict["available"]) {
                return "\(available) reset credits available"
            }
            return "Reset credits reported"
        }
        return "Reset credit data available"
    }

    nonisolated private static func parseResetCredits(_ value: Any?) -> [ResetCredit] {
        if value == nil || value is NSNull {
            return []
        }
        if let array = value as? [Any] {
            return array.enumerated().compactMap { index, item in
                parseResetCredit(item, index: index)
            }
        }
        if let dict = value as? [String: Any] {
            for key in ["items", "credits", "reset_credits", "resetCredits", "available_credits"] {
                if let nested = dict[key] as? [Any] {
                    return nested.enumerated().compactMap { index, item in
                        parseResetCredit(item, index: index)
                    }
                }
            }
            if let expiresAt = resetCreditDate(from: dict) {
                let label = resetCreditLabel(from: dict, fallback: "Reset Credit")
                return [ResetCredit(id: resetCreditID(from: dict, fallback: "reset-credit-1"), label: label, expiresAt: expiresAt)]
            }
        }
        return []
    }

    nonisolated private static func parseResetCredit(_ value: Any, index: Int) -> ResetCredit? {
        let fallback = "Reset Credit \(index + 1)"
        if let dict = value as? [String: Any] {
            let expiresAt = resetCreditDate(from: dict)
            guard expiresAt != nil || !dict.isEmpty else {
                return nil
            }
            return ResetCredit(
                id: resetCreditID(from: dict, fallback: "reset-credit-\(index + 1)"),
                label: resetCreditLabel(from: dict, fallback: fallback),
                expiresAt: expiresAt
            )
        }
        if let text = value as? String {
            return ResetCredit(id: "reset-credit-\(index + 1)", label: text.isEmpty ? fallback : text, expiresAt: nil)
        }
        return nil
    }

    nonisolated private static func resetCreditID(from dict: [String: Any], fallback: String) -> String {
        for key in ["id", "credit_id", "name", "label"] {
            if let value = dict[key] as? String, !value.isEmpty {
                return value
            }
        }
        return fallback
    }

    nonisolated private static func resetCreditLabel(from dict: [String: Any], fallback: String) -> String {
        for key in ["label", "name", "title"] {
            if let value = dict[key] as? String, !value.isEmpty {
                return value
            }
        }
        return fallback
    }

    nonisolated private static func resetCreditDate(from dict: [String: Any]) -> Date? {
        for key in ["expires_at", "expiresAt", "expiry", "expires", "expiration", "expiry_at"] {
            if let date = dateValue(dict[key]) {
                return date
            }
        }
        return nil
    }

    nonisolated private static func tokens(from dict: [String: Any]) -> UsageTokens {
        UsageTokens(
            input: max(intValue(dict["input_tokens"]) ?? 0, 0),
            cachedInput: max(intValue(dict["cached_input_tokens"]) ?? 0, 0),
            output: max(intValue(dict["output_tokens"]) ?? 0, 0),
            reasoningOutput: max(intValue(dict["reasoning_output_tokens"]) ?? 0, 0),
            total: max(intValue(dict["total_tokens"]) ?? 0, 0)
        )
    }

    nonisolated private static func jsonObject(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    nonisolated private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Double {
            guard value.isFinite,
                  value >= Double(Int.min),
                  value < Double(Int.max) else {
                return nil
            }
            return Int(value)
        }
        if let value = value as? String { return Int(value) }
        return nil
    }

    nonisolated private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value.isFinite ? value : nil }
        if let value = value as? Int { return Double(value) }
        if let value = value as? String,
           let parsed = Double(value),
           parsed.isFinite {
            return parsed
        }
        return nil
    }

    nonisolated private static func dateValue(_ value: Any?) -> Date? {
        if let value = value as? Date {
            return value
        }
        if let value = intValue(value) {
            return Date(timeIntervalSince1970: TimeInterval(value))
        }
        if let value = value as? String {
            return parseDate(value)
        }
        return nil
    }

    nonisolated private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return (try? Self.fractionalISOFormatStyle.parse(value)) ?? (try? Self.isoFormatStyle.parse(value))
    }

    nonisolated private static func sessionIDFromFilename(_ url: URL) -> String? {
        let name = url.deletingPathExtension().lastPathComponent
        guard let range = name.range(of: "019", options: .backwards) else {
            return nil
        }
        return String(name[range.lowerBound...])
    }

    static var defaultCodexHomeURL: URL {
        defaultCodexHome
    }

    private static var defaultCodexHome: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").standardizedFileURL
    }

    private static func loadSavedCodexHome(preferences: UserDefaults) -> URL {
        guard let rawPath = preferences.string(forKey: codexHomePathKey),
              !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return defaultCodexHome
        }
        return URL(fileURLWithPath: rawPath).standardizedFileURL
    }

    private static func codexHomeURL(fromConfigurationPath path: String?) -> URL {
        guard let path,
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return defaultCodexHome
        }
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    static func displayPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path
        let homePath = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        if path == defaultCodexHome.path {
            return "~/.codex"
        }
        if path == homePath {
            return "~"
        }
        if path.hasPrefix(homePath + "/") {
            return "~/" + String(path.dropFirst(homePath.count + 1))
        }
        return path
    }

    static func diagnosticDisplayPath(_ url: URL) -> String {
        let display = displayPath(url)
        if display == "~" || display.hasPrefix("~/") {
            return display
        }
        let folder = url.standardizedFileURL.lastPathComponent
        return folder.isEmpty ? "<custom folder>" : "<custom>/\(folder)"
    }

    static func shortProjectName(_ path: String) -> String {
        guard path != "Unknown project" else { return path }
        return URL(fileURLWithPath: path).lastPathComponent.isEmpty ? path : URL(fileURLWithPath: path).lastPathComponent
    }

    static func compactNumber(_ value: Int) -> String {
        let number = Double(value)
        if number >= 1_000_000_000 { return String(format: "%.1fB", number / 1_000_000_000) }
        if number >= 1_000_000 { return String(format: "%.1fM", number / 1_000_000) }
        if number >= 1_000 { return String(format: "%.1fK", number / 1_000) }
        return "\(value)"
    }

    static func signedCompactNumber(_ value: Int) -> String {
        if value == 0 {
            return "0"
        }
        let sign = value > 0 ? "+" : "-"
        return sign + compactNumber(abs(value))
    }

    static func currency(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    static func signedCurrency(_ value: Double) -> String {
        guard abs(value) >= 0.005 else {
            return "$0.00"
        }
        let sign = value > 0 ? "+" : "-"
        return sign + currency(abs(value))
    }

    static func signedPercent(_ value: Double?) -> String {
        guard let value else {
            return "new"
        }
        let percent = value * 100
        guard abs(percent) >= 0.5 else {
            return "0%"
        }
        let sign = percent > 0 ? "+" : ""
        return String(format: "%@%.0f%%", sign, percent)
    }

    static func byteSize(_ value: UInt64) -> String {
        guard value > 0 else {
            return "0 KB"
        }
        return Self.byteCountFormatter.string(fromByteCount: Int64(value))
    }

    static func averageCostPerMillion(tokens: Int, cost: Double) -> Double {
        guard tokens > 0, cost.isFinite else {
            return 0
        }
        return cost / Double(tokens) * 1_000_000
    }

    private static func deltaPercent(current: Double, previous: Double) -> Double? {
        guard previous > 0 else {
            return nil
        }
        return (current - previous) / previous
    }

    private static func activeDayCount(entries: [UsageEntry]) -> Double {
        guard let earliest = entries.map(\.timestamp).min(),
              let latest = entries.map(\.timestamp).max() else {
            return 30
        }
        let start = Calendar.current.startOfDay(for: earliest)
        let end = Calendar.current.startOfDay(for: latest)
        let days = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
        return Double(max(days + 1, 1))
    }

    private static func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") {
            return "\"\(escaped)\""
        }
        return escaped
    }

    static func percentLeft(_ limit: WindowLimit?) -> String {
        guard let limit, limit.usedPercent.isFinite else { return "No data" }
        let used = min(max(limit.usedPercent, 0), 100)
        let left = 100 - used
        return String(format: "%.0f%% left", left)
    }

    static func resetText(_ limit: WindowLimit?, now: Date = Date()) -> String {
        guard let date = limit?.resetsAt else { return "Reset unknown" }
        let remaining = Int(date.timeIntervalSince(now))
        if remaining <= 0 { return "expired" }
        let days = remaining / 86_400
        let hours = (remaining % 86_400) / 3_600
        let minutes = (remaining % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h left" }
        if hours > 0 { return "\(hours)h \(minutes)m left" }
        return "\(minutes)m left"
    }

    static func windowLimitDisplay(
        _ limit: WindowLimit?,
        snapshotSeenAt: Date?,
        now: Date = Date()
    ) -> WindowLimitDisplay {
        guard let limit else {
            return WindowLimitDisplay(value: "No data", detail: "No local snapshot", isExpired: false)
        }

        let knownDeadline = limit.resetsAt
        let inferredDeadline: Date? = snapshotSeenAt.flatMap { seenAt in
            guard (1...525_600).contains(limit.windowMinutes) else {
                return nil
            }
            return seenAt.addingTimeInterval(TimeInterval(limit.windowMinutes) * 60)
        }
        if knownDeadline.map({ $0 <= now }) == true ||
            (knownDeadline == nil && inferredDeadline.map({ $0 <= now }) == true) {
            return WindowLimitDisplay(value: "Expired", detail: "New Codex activity needed", isExpired: true)
        }

        return WindowLimitDisplay(
            value: percentLeft(limit),
            detail: limit.resetsAt == nil ? "Reset time unknown" : resetText(limit, now: now),
            isExpired: false
        )
    }

    static func expiryText(_ date: Date?, now: Date = Date()) -> String {
        guard let date else {
            return "Expiry unknown"
        }
        let remaining = Int(date.timeIntervalSince(now))
        if remaining <= 0 {
            return "expired"
        }
        let days = remaining / 86_400
        let hours = (remaining % 86_400) / 3_600
        let minutes = (remaining % 3_600) / 60
        if days > 0 { return "expires in \(days)d \(hours)h" }
        if hours > 0 { return "expires in \(hours)h \(minutes)m" }
        return "expires in \(minutes)m"
    }

    static func expiryDateText(_ date: Date?) -> String {
        guard let date else {
            return "No expiry in snapshot"
        }
        return resetCreditDateFormatter.string(from: date)
    }

    static func resetCreditDisplay(_ snapshot: RateLimitSnapshot?, now: Date = Date()) -> ResetCreditDisplay {
        guard let snapshot else {
            return ResetCreditDisplay(value: "No data", detail: "No local snapshot")
        }
        let description = snapshot.resetCreditsDescription
        if !snapshot.resetCredits.isEmpty {
            let notExpired = snapshot.resetCredits.filter { credit in
                credit.expiresAt.map { $0 > now } ?? true
            }
            if notExpired.isEmpty && snapshot.resetCredits.allSatisfy({ $0.expiresAt != nil }) {
                return ResetCreditDisplay(value: "Expired", detail: "New Codex activity needed", isExpired: true)
            }
            if notExpired.count != snapshot.resetCredits.count {
                return ResetCreditDisplay(
                    value: String(notExpired.count),
                    detail: "\(notExpired.count) not expired in latest snapshot"
                )
            }
        }
        if let first = description.split(separator: " ").first, Int(first) != nil {
            return ResetCreditDisplay(value: String(first), detail: description)
        }

        let lower = description.lowercased()
        if lower.contains("no reset credits") {
            return ResetCreditDisplay(value: "None", detail: description)
        }
        if lower.contains("reported") || lower.contains("available") {
            return ResetCreditDisplay(value: "Reported", detail: description)
        }
        return ResetCreditDisplay(value: "Data", detail: description)
    }

    static func loadSavedRates(preferences: UserDefaults = .standard) -> [ModelRate] {
        if let data = preferences.data(forKey: modelRatesKey),
           let decoded = try? JSONDecoder().decode([ModelRate].self, from: data) {
            var savedRates = sanitizedRates(decoded)
            let savedCatalogVersion = preferences.object(forKey: modelRateCatalogVersionKey) == nil
                ? 1
                : preferences.integer(forKey: modelRateCatalogVersionKey)
            if savedCatalogVersion < defaultRateCatalogVersion {
                savedRates = migratedRates(savedRates, fromVersion: savedCatalogVersion)
                persistRates(savedRates, preferences: preferences)
            }
            return savedRates
        }
        persistRates(defaultRates, preferences: preferences)
        return defaultRates
    }

    private static func loadSavedDateWindow(preferences: UserDefaults) -> DateWindow {
        guard let raw = preferences.string(forKey: dateWindowKey),
              let value = DateWindow(rawValue: raw) else {
            return .sevenDays
        }
        return value
    }

    private static func loadSavedScopeMode(preferences: UserDefaults) -> ScopeMode {
        guard let raw = preferences.string(forKey: scopeModeKey),
              let value = ScopeMode(rawValue: raw) else {
            return .all
        }
        return value
    }

    static let defaultRates: [ModelRate] = [
        ModelRate(model: "gpt-5.6-sol", inputPerMillion: 5.00, cachedInputPerMillion: 0.50, outputPerMillion: 30.00),
        ModelRate(model: "gpt-5.6-terra", inputPerMillion: 2.50, cachedInputPerMillion: 0.25, outputPerMillion: 15.00),
        ModelRate(model: "gpt-5.6-luna", inputPerMillion: 1.00, cachedInputPerMillion: 0.10, outputPerMillion: 6.00),
        ModelRate(model: "gpt-5.5", inputPerMillion: 5.00, cachedInputPerMillion: 0.50, outputPerMillion: 30.00),
        ModelRate(model: "gpt-5.5-pro", inputPerMillion: 30.00, cachedInputPerMillion: 0.00, outputPerMillion: 180.00),
        ModelRate(model: "gpt-5.4", inputPerMillion: 2.50, cachedInputPerMillion: 0.25, outputPerMillion: 15.00),
        ModelRate(model: "gpt-5.4-mini", inputPerMillion: 0.75, cachedInputPerMillion: 0.075, outputPerMillion: 4.50),
        ModelRate(model: "gpt-5.4-nano", inputPerMillion: 0.20, cachedInputPerMillion: 0.02, outputPerMillion: 1.25),
        ModelRate(model: "gpt-5.4-pro", inputPerMillion: 30.00, cachedInputPerMillion: 0.00, outputPerMillion: 180.00),
        ModelRate(model: "gpt-5.3-codex", inputPerMillion: 1.75, cachedInputPerMillion: 0.175, outputPerMillion: 14.00)
    ]

    static let defaultRateProfileName = "OpenAI API standard short-context rates"
    static let defaultRateSourceName = "OpenAI API pricing"
    static let defaultRateSourceURL = URL(string: "https://developers.openai.com/api/docs/pricing")!
    static let defaultRateVerifiedDate = "2026-07-10"
    static let defaultRateLimitations = "Local logs do not expose cache writes or tool-call charges; total-only rows use the input rate; long-context, processing-mode, regional, and subscription pricing can differ."
    static let defaultRateSourceSummary = "\(defaultRateProfileName), verified \(defaultRateVerifiedDate)"
    static let defaultRateSourceDetail = "\(defaultRateSourceName) / \(defaultRateVerifiedDate)"

    @inline(never)
    private static func migratedRates(_ savedRates: [ModelRate], fromVersion savedVersion: Int) -> [ModelRate] {
        var migrated = savedRates
        if savedVersion < 2 {
            for defaultRate in defaultRates {
                let normalizedDefault = normalizedModelIdentifier(defaultRate.model)
                if let index = migrated.firstIndex(where: { normalizedModelIdentifier($0.model) == normalizedDefault }) {
                    if shouldReplaceLegacyRate(migrated[index]) {
                        migrated[index] = defaultRate
                    }
                } else {
                    migrated.append(defaultRate)
                }
            }
        }
        if savedVersion < 3 {
            migrated = catalogOrderedRates(migrated)
        }
        return sanitizedRates(migrated)
    }

    @inline(never)
    private static func catalogOrderedRates(_ rates: [ModelRate]) -> [ModelRate] {
        var builtInModels = Set<String>()
        for defaultRate in defaultRates {
            builtInModels.insert(normalizedModelIdentifier(defaultRate.model))
        }

        var ratesByModel: [String: ModelRate] = [:]
        for rate in rates {
            ratesByModel[normalizedModelIdentifier(rate.model)] = rate
        }

        var ordered: [ModelRate] = []
        for defaultRate in defaultRates {
            if let rate = ratesByModel[normalizedModelIdentifier(defaultRate.model)] {
                ordered.append(rate)
            }
        }
        for rate in rates where !builtInModels.contains(normalizedModelIdentifier(rate.model)) {
            ordered.append(rate)
        }
        return ordered
    }

    private static func shouldReplaceLegacyRate(_ rate: ModelRate) -> Bool {
        let model = normalizedModelIdentifier(rate.model)
        let isZeroPlaceholder = rate.inputPerMillion == 0
            && rate.cachedInputPerMillion == 0
            && rate.outputPerMillion == 0
        if ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"].contains(model) {
            return isZeroPlaceholder
        }
        if ["gpt-5.5-pro", "gpt-5.4-pro"].contains(model) {
            return rate.inputPerMillion == 30
                && rate.cachedInputPerMillion == 30
                && rate.outputPerMillion == 180
        }
        return false
    }

    private static func persistRates(_ rates: [ModelRate], preferences: UserDefaults) {
        if let data = try? JSONEncoder().encode(rates) {
            preferences.set(data, forKey: modelRatesKey)
        }
        preferences.set(defaultRateCatalogVersion, forKey: modelRateCatalogVersionKey)
    }

    private static func zeroRate(_ model: String) -> ModelRate {
        ModelRate(model: model, inputPerMillion: 0, cachedInputPerMillion: 0, outputPerMillion: 0)
    }

    private static func sanitizedRates(_ values: [ModelRate]) -> [ModelRate] {
        var seen = Set<String>()
        let sanitized = values.compactMap { rate -> ModelRate? in
            let model = rate.model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !model.isEmpty else {
                return nil
            }
            guard seen.insert(model.lowercased()).inserted else {
                return nil
            }
            return ModelRate(
                model: model,
                inputPerMillion: rate.inputPerMillion.isFinite ? max(0, rate.inputPerMillion) : 0,
                cachedInputPerMillion: rate.cachedInputPerMillion.isFinite ? max(0, rate.cachedInputPerMillion) : 0,
                outputPerMillion: rate.outputPerMillion.isFinite ? max(0, rate.outputPerMillion) : 0
            )
        }
        return sanitized.isEmpty ? defaultRates : sanitized
    }

    private static func nextCustomModelName(existing: [String]) -> String {
        let names = Set(existing.map { $0.lowercased() })
        let base = "custom-model"
        if !names.contains(base) {
            return base
        }
        var index = 2
        while names.contains("\(base)-\(index)") {
            index += 1
        }
        return "\(base)-\(index)"
    }

    private static func windowTitle(forDays days: Int?) -> String {
        guard let days else {
            return DateWindow.lifetime.title
        }
        return DateWindow.allCases.first { $0.days == days }?.title ?? "\(days) days"
    }

    private static func defaultCacheURL(codexHome: URL) -> URL? {
        guard let cacheRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return cacheRoot
            .appendingPathComponent("CodexUsageMonitor", isDirectory: true)
            .appendingPathComponent("usage-cache-\(stableHash(codexHome.path)).json")
    }

    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private static let dateWindowKey = "dateWindow.v1"
    private static let scopeModeKey = "scopeMode.v1"
    private static let selectedScopeKey = "selectedScopeID.v1"
    private static let codexHomePathKey = "codexHomePath.v1"
    private static let modelRatesKey = "modelRates.v1"
    private static let modelRateCatalogVersionKey = "modelRateCatalogVersion.v1"
    private static let defaultRateCatalogVersion = 3
    nonisolated private static let parseCacheVersion = 3

    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        return formatter
    }()

    nonisolated private static let fractionalISOFormatStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    nonisolated private static let isoFormatStyle = Date.ISO8601FormatStyle()

    nonisolated private static let sessionMetaMarker = Data(#""type":"session_meta""#.utf8)
    nonisolated private static let turnContextMarker = Data(#""type":"turn_context""#.utf8)
    nonisolated private static let tokenCountMarker = Data(#""type":"token_count""#.utf8)
    nonisolated private static let maximumLogLineBytes = 8 * 1024 * 1024

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private static let activityTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter
    }()

    private static let diagnosticDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter
    }()

    private static let dayIDFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let shortDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private static let resetCreditDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter
    }()
}

private struct UsageScanSource {
    let codexHome: URL
    let cacheURL: URL?
}

private struct LocalUsageParseResult {
    var entries: [UsageEntry]
    var latestLimit: RateLimitSnapshot?
    var scannedFileCount: Int
    var cachedFileCount: Int
    var cacheSizeBytes: UInt64
    var parseIssueCount: Int
    var latestParseIssue: String?
}

private struct BillableTokenComponents {
    var inputTokens: Int
    var cachedInputTokens: Int
    var outputTokens: Int
    var totalOnlyTokens: Int

    init(tokens: UsageTokens) {
        let reportedInput = max(tokens.input, 0)
        let reportedCachedInput = max(tokens.cachedInput, 0)
        let totalInput = max(reportedInput, reportedCachedInput)
        cachedInputTokens = min(reportedCachedInput, totalInput)
        inputTokens = max(totalInput - cachedInputTokens, 0)
        outputTokens = max(tokens.output, 0)
        let classifiedTokens = totalInput + outputTokens
        totalOnlyTokens = max(tokens.total - classifiedTokens, 0)
    }

    var totalTokens: Int {
        inputTokens + cachedInputTokens + outputTokens + totalOnlyTokens
    }
}

private struct CostComponents {
    var inputTokens: Int
    var cachedInputTokens: Int
    var outputTokens: Int
    var totalOnlyTokens: Int
    var inputCost: Double
    var cachedInputCost: Double
    var outputCost: Double
    var totalOnlyCost: Double

    var totalCost: Double {
        inputCost + cachedInputCost + outputCost + totalOnlyCost
    }

    static let zero = CostComponents(
        inputTokens: 0,
        cachedInputTokens: 0,
        outputTokens: 0,
        totalOnlyTokens: 0,
        inputCost: 0,
        cachedInputCost: 0,
        outputCost: 0,
        totalOnlyCost: 0
    )

    static func +(lhs: CostComponents, rhs: CostComponents) -> CostComponents {
        CostComponents(
            inputTokens: lhs.inputTokens + rhs.inputTokens,
            cachedInputTokens: lhs.cachedInputTokens + rhs.cachedInputTokens,
            outputTokens: lhs.outputTokens + rhs.outputTokens,
            totalOnlyTokens: lhs.totalOnlyTokens + rhs.totalOnlyTokens,
            inputCost: lhs.inputCost + rhs.inputCost,
            cachedInputCost: lhs.cachedInputCost + rhs.cachedInputCost,
            outputCost: lhs.outputCost + rhs.outputCost,
            totalOnlyCost: lhs.totalOnlyCost + rhs.totalOnlyCost
        )
    }
}

private struct UsageParseCache: Codable {
    var version: Int
    var codexHomePath: String
    var indexSignature: String
    var files: [String: CachedSessionFile]
}

private struct CachedSessionFile: Codable {
    var size: UInt64
    var modifiedAt: TimeInterval
    var entries: [UsageEntry]
    var latestLimit: RateLimitSnapshot?
    var parseIssueCount: Int
    var latestParseIssue: String?
}

private struct CachedSessionParse {
    var entries: [UsageEntry]
    var latestLimit: RateLimitSnapshot?
    var parseIssueCount: Int
    var latestParseIssue: String?
}

private struct LineReadDiagnostics {
    var issueCount: Int
    var latestIssue: String?
}

private struct FileSignature {
    var size: UInt64
    var modifiedAt: TimeInterval

    var cacheKey: String {
        "\(size):\(modifiedAt)"
    }
}
