import Combine
import Foundation
import ServiceManagement

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case tokens = "Tokens"
    case cost = "Cost"
    case tokensAndCost = "Tokens + Cost"

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .tokens: return "Tokens"
        case .cost: return "Estimated Cost"
        case .tokensAndCost: return "Tokens + Est. Cost"
        }
    }

    var detail: String {
        switch self {
        case .tokens:
            return "Shows token usage in the menu bar"
        case .cost:
            return "Shows estimated cost in the menu bar"
        case .tokensAndCost:
            return "Shows tokens and estimated cost"
        }
    }
}

enum TrendMetric: String, CaseIterable, Identifiable {
    case tokens = "Tokens"
    case cost = "Cost"

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .tokens: return "Tokens"
        case .cost: return "Est. Cost"
        }
    }
}

enum AutoRefreshInterval: String, CaseIterable, Identifiable {
    case off = "Off"
    case oneMinute = "1 min"
    case fiveMinutes = "5 min"
    case fifteenMinutes = "15 min"

    var id: String { rawValue }

    var seconds: TimeInterval? {
        switch self {
        case .off: return nil
        case .oneMinute: return 60
        case .fiveMinutes: return 300
        case .fifteenMinutes: return 900
        }
    }

    var menuTitle: String {
        switch self {
        case .off: return "Off"
        case .oneMinute: return "Every Minute"
        case .fiveMinutes: return "Every 5 Minutes"
        case .fifteenMinutes: return "Every 15 Minutes"
        }
    }

    var detail: String {
        switch self {
        case .off:
            return "Manual refresh only"
        case .oneMinute:
            return "Watches logs and refreshes every minute"
        case .fiveMinutes:
            return "Watches logs and refreshes every 5 minutes"
        case .fifteenMinutes:
            return "Watches logs and refreshes every 15 minutes"
        }
    }
}

struct BudgetStatus: Equatable {
    var title: String
    var value: String
    var detail: String
    var fraction: Double
    var isConfigured: Bool
    var isExceeded: Bool
}

enum BudgetAlertLevel: Equatable {
    case none
    case warning
    case exceeded

    var priority: Int {
        switch self {
        case .none: return 0
        case .warning: return 1
        case .exceeded: return 2
        }
    }

    var title: String {
        switch self {
        case .none: return "No budget alert"
        case .warning: return "Budget near limit"
        case .exceeded: return "Budget exceeded"
        }
    }

    var marker: String {
        switch self {
        case .none: return ""
        case .warning: return "!"
        case .exceeded: return "!!"
        }
    }
}

struct BudgetAlert: Equatable {
    var level: BudgetAlertLevel
    var detail: String
    var fraction: Double

    var title: String {
        level.title
    }

    var marker: String {
        level.marker
    }

    var isVisible: Bool {
        level != .none
    }

    static let none = BudgetAlert(level: .none, detail: "None", fraction: 0)
}

enum AppConfigurationError: LocalizedError {
    case unsupportedVersion(Int)
    case invalidValue(field: String, value: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "Settings file version \(version) is not supported."
        case .invalidValue(let field, let value):
            return "Settings file contains an invalid \(field): \(value)."
        }
    }
}

struct AppConfiguration: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = currentSchemaVersion
    var exportedAt: Date
    var showWindowOnLaunch: Bool
    var menuBarDisplayMode: String
    var autoRefreshInterval: String
    var budgetNotificationsEnabled: Bool?
    var tokenBudgetLimit: Int
    var costBudgetLimit: Double
    var codexHomePath: String?
    var dateWindow: String
    var scopeMode: String
    var selectedScopeID: String
    var modelRates: [ModelRate]
    var defaultRateSource: String
    var defaultRateVerifiedDate: String
    var trendMetric: String? = nil

    func menuBarDisplayModeValue() throws -> MenuBarDisplayMode {
        try validated(MenuBarDisplayMode(rawValue: menuBarDisplayMode), field: "menu bar display mode", value: menuBarDisplayMode)
    }

    func autoRefreshIntervalValue() throws -> AutoRefreshInterval {
        try validated(AutoRefreshInterval(rawValue: autoRefreshInterval), field: "auto-refresh interval", value: autoRefreshInterval)
    }

    func trendMetricValue() throws -> TrendMetric {
        guard let trendMetric else {
            return .tokens
        }
        return try validated(TrendMetric(rawValue: trendMetric), field: "trend metric", value: trendMetric)
    }

    func dateWindowValue() throws -> DateWindow {
        try validated(DateWindow(rawValue: dateWindow), field: "date window", value: dateWindow)
    }

    func scopeModeValue() throws -> ScopeMode {
        try validated(ScopeMode(rawValue: scopeMode), field: "scope mode", value: scopeMode)
    }

    func validateSchema() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw AppConfigurationError.unsupportedVersion(schemaVersion)
        }
    }

    static func encode(_ configuration: AppConfiguration) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(configuration)
    }

    static func decode(from data: Data) throws -> AppConfiguration {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let configuration = try decoder.decode(AppConfiguration.self, from: data)
        try configuration.validateSchema()
        return configuration
    }

    private func validated<T>(_ value: T?, field: String, value rawValue: String) throws -> T {
        guard let value else {
            throw AppConfigurationError.invalidValue(field: field, value: rawValue)
        }
        return value
    }
}

final class AppSettings: ObservableObject {
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginCanToggle = true
    @Published private(set) var launchAtLoginDetail = "Off"
    @Published private(set) var showWindowOnLaunch = true
    @Published private(set) var menuBarDisplayMode: MenuBarDisplayMode = .tokens
    @Published private(set) var trendMetric: TrendMetric = .tokens
    @Published private(set) var autoRefreshInterval: AutoRefreshInterval = .oneMinute
    @Published private(set) var budgetNotificationsEnabled = false
    @Published private(set) var tokenBudgetLimit: Int = 0
    @Published private(set) var costBudgetLimit: Double = 0

    private let preferences: UserDefaults

    init(
        preferences: UserDefaults = .standard,
        refreshLoginStatus: Bool = true
    ) {
        self.preferences = preferences
        self.showWindowOnLaunch = Self.loadShowWindowOnLaunch(preferences: preferences)
        self.menuBarDisplayMode = Self.loadMenuBarDisplayMode(preferences: preferences)
        self.trendMetric = Self.loadTrendMetric(preferences: preferences)
        self.autoRefreshInterval = Self.loadAutoRefreshInterval(preferences: preferences)
        self.budgetNotificationsEnabled = Self.loadBudgetNotificationsEnabled(preferences: preferences)
        self.tokenBudgetLimit = Self.loadTokenBudgetLimit(preferences: preferences)
        self.costBudgetLimit = Self.loadCostBudgetLimit(preferences: preferences)
        if refreshLoginStatus {
            refreshLaunchAtLoginStatus()
        }
    }

    func refreshLaunchAtLoginStatus() {
        switch SMAppService.mainApp.status {
        case .enabled:
            launchAtLoginEnabled = true
            launchAtLoginCanToggle = true
            launchAtLoginDetail = "Starts automatically when you sign in"
        case .requiresApproval:
            launchAtLoginEnabled = false
            launchAtLoginCanToggle = true
            launchAtLoginDetail = "Waiting for approval in System Settings"
        case .notFound:
            launchAtLoginEnabled = false
            launchAtLoginCanToggle = false
            launchAtLoginDetail = "Move the app to Applications to enable"
        case .notRegistered:
            launchAtLoginEnabled = false
            launchAtLoginCanToggle = true
            launchAtLoginDetail = "Off"
        @unknown default:
            launchAtLoginEnabled = false
            launchAtLoginCanToggle = false
            launchAtLoginDetail = "Unavailable on this Mac"
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            let service = SMAppService.mainApp
            switch (enabled, service.status) {
            case (true, .enabled):
                break
            case (true, _):
                try service.register()
            case (false, .enabled), (false, .requiresApproval):
                try service.unregister()
            case (false, _):
                break
            }
            refreshLaunchAtLoginStatus()
        } catch {
            refreshLaunchAtLoginStatus()
            launchAtLoginDetail = "Could not update: \(error.localizedDescription)"
        }
    }

    func toggleLaunchAtLogin() {
        setLaunchAtLogin(!launchAtLoginEnabled)
    }

    func setShowWindowOnLaunch(_ enabled: Bool) {
        showWindowOnLaunch = enabled
        preferences.set(enabled, forKey: Self.showWindowOnLaunchKey)
    }

    var showWindowOnLaunchDetail: String {
        showWindowOnLaunch ? "Window opens when the app starts" : "Starts quietly in the menu bar"
    }

    func setMenuBarDisplayMode(_ mode: MenuBarDisplayMode) {
        menuBarDisplayMode = mode
        preferences.set(mode.rawValue, forKey: Self.menuBarDisplayModeKey)
    }

    func setTrendMetric(_ metric: TrendMetric) {
        trendMetric = metric
        preferences.set(metric.rawValue, forKey: Self.trendMetricKey)
    }

    func menuBarTitle(summary: UsageSummary, pricingCoverage: PricingCoverage) -> String {
        let tokens = UsageStore.compactNumber(summary.tokens.total)
        let cost = "\(pricingCoverage.isComplete ? "" : "~")\(UsageStore.currency(summary.cost))"
        let baseTitle: String
        switch menuBarDisplayMode {
        case .tokens:
            baseTitle = "CX \(tokens)"
        case .cost:
            baseTitle = "CX \(cost)"
        case .tokensAndCost:
            baseTitle = "CX \(tokens) / \(cost)"
        }

        let alert = budgetAlert(summary: summary)
        guard alert.isVisible else {
            return baseTitle
        }
        return "\(baseTitle) \(alert.marker)"
    }

    func statusMenuSnapshotLines(
        summary: UsageSummary,
        pricingCoverage: PricingCoverage,
        windowTitle: String,
        scopeDescription: String,
        healthStatus: UsageHealthStatus
    ) -> [String] {
        var lines = [
            "Filter: \(windowTitle) / \(scopeDescription)",
            "Tokens: \(UsageStore.compactNumber(summary.tokens.total))",
            "Estimated cost: \(UsageStore.currency(summary.cost))",
            "Pricing coverage: \(pricingCoverage.percentText)",
            "Events: \(summary.eventCount) / Chats: \(summary.sessionCount)"
        ]

        let tokenBudget = tokenBudgetStatus(summary: summary)
        if tokenBudget.isConfigured {
            lines.append("Token budget: \(tokenBudget.value) - \(tokenBudget.detail)")
        }

        let costBudget = costBudgetStatus(summary: summary)
        if costBudget.isConfigured {
            lines.append("Estimated cost budget: \(costBudget.value) - \(costBudget.detail)")
        }

        let alert = budgetAlert(summary: summary)
        if alert.isVisible {
            lines.append("Budget alert: \(alert.title) - \(alert.detail)")
        }

        lines.append("Status: \(healthStatus.isVisible ? healthStatus.title : "Ready")")
        return lines
    }

    func setAutoRefreshInterval(_ interval: AutoRefreshInterval) {
        autoRefreshInterval = interval
        preferences.set(interval.rawValue, forKey: Self.autoRefreshIntervalKey)
    }

    func setBudgetNotificationsEnabled(_ enabled: Bool) {
        budgetNotificationsEnabled = enabled
        preferences.set(enabled, forKey: Self.budgetNotificationsEnabledKey)
    }

    func setTokenBudgetLimit(_ limit: Int) {
        tokenBudgetLimit = max(0, limit)
        preferences.set(tokenBudgetLimit, forKey: Self.tokenBudgetLimitKey)
    }

    func setCostBudgetLimit(_ limit: Double) {
        costBudgetLimit = limit.isFinite ? max(0, limit) : 0
        preferences.set(costBudgetLimit, forKey: Self.costBudgetLimitKey)
    }

    func exportConfiguration(store: UsageStore, exportedAt: Date = Date()) -> AppConfiguration {
        AppConfiguration(
            exportedAt: exportedAt,
            showWindowOnLaunch: showWindowOnLaunch,
            menuBarDisplayMode: menuBarDisplayMode.rawValue,
            autoRefreshInterval: autoRefreshInterval.rawValue,
            budgetNotificationsEnabled: budgetNotificationsEnabled,
            tokenBudgetLimit: tokenBudgetLimit,
            costBudgetLimit: costBudgetLimit,
            codexHomePath: store.configurationCodexHomePath,
            dateWindow: store.dateWindow.rawValue,
            scopeMode: store.scopeMode.rawValue,
            selectedScopeID: store.selectedScopeID,
            modelRates: store.rates,
            defaultRateSource: UsageStore.defaultRateSourceSummary,
            defaultRateVerifiedDate: UsageStore.defaultRateVerifiedDate,
            trendMetric: trendMetric.rawValue
        )
    }

    func applyConfiguration(_ configuration: AppConfiguration, to store: UsageStore, refreshAfterImport: Bool = true) throws {
        try configuration.validateSchema()
        let displayMode = try configuration.menuBarDisplayModeValue()
        let trendMetric = try configuration.trendMetricValue()
        let refreshInterval = try configuration.autoRefreshIntervalValue()
        let dateWindow = try configuration.dateWindowValue()
        let scopeMode = try configuration.scopeModeValue()

        setShowWindowOnLaunch(configuration.showWindowOnLaunch)
        setMenuBarDisplayMode(displayMode)
        setTrendMetric(trendMetric)
        setAutoRefreshInterval(refreshInterval)
        setBudgetNotificationsEnabled(configuration.budgetNotificationsEnabled ?? false)
        setTokenBudgetLimit(configuration.tokenBudgetLimit)
        setCostBudgetLimit(configuration.costBudgetLimit)

        let needsRefresh = store.applyConfiguration(
            codexHomePath: configuration.codexHomePath,
            dateWindow: dateWindow,
            scopeMode: scopeMode,
            selectedScopeID: configuration.selectedScopeID,
            rates: configuration.modelRates
        )

        if needsRefresh && refreshAfterImport {
            store.refresh()
        }
    }

    var hasBudgetLimits: Bool {
        tokenBudgetLimit > 0 || costBudgetLimit > 0
    }

    func tokenBudgetStatus(summary: UsageSummary) -> BudgetStatus {
        guard tokenBudgetLimit > 0 else {
            return BudgetStatus(title: "Token budget", value: "Off", detail: "Not set", fraction: 0, isConfigured: false, isExceeded: false)
        }

        let used = summary.tokens.total
        let rawFraction = Double(used) / Double(tokenBudgetLimit)
        return BudgetStatus(
            title: "Token budget",
            value: Self.percentText(rawFraction),
            detail: "\(UsageStore.compactNumber(used)) of \(UsageStore.compactNumber(tokenBudgetLimit)) tokens",
            fraction: Self.clampedFraction(rawFraction),
            isConfigured: true,
            isExceeded: rawFraction >= 1
        )
    }

    func costBudgetStatus(summary: UsageSummary) -> BudgetStatus {
        guard costBudgetLimit > 0 else {
            return BudgetStatus(title: "Estimated cost budget", value: "Off", detail: "Not set", fraction: 0, isConfigured: false, isExceeded: false)
        }

        let rawFraction = summary.cost / costBudgetLimit
        return BudgetStatus(
            title: "Estimated cost budget",
            value: Self.percentText(rawFraction),
            detail: "\(UsageStore.currency(summary.cost)) of \(UsageStore.currency(costBudgetLimit))",
            fraction: Self.clampedFraction(rawFraction),
            isConfigured: true,
            isExceeded: rawFraction >= 1
        )
    }

    func budgetAlert(summary: UsageSummary) -> BudgetAlert {
        var alerts: [BudgetAlert] = []

        if tokenBudgetLimit > 0 {
            let rawFraction = Double(summary.tokens.total) / Double(tokenBudgetLimit)
            let status = tokenBudgetStatus(summary: summary)
            let level = Self.budgetAlertLevel(rawFraction)
            if level != .none {
                alerts.append(Self.budgetAlert(status: status, level: level, rawFraction: rawFraction))
            }
        }

        if costBudgetLimit > 0 {
            let rawFraction = summary.cost / costBudgetLimit
            let status = costBudgetStatus(summary: summary)
            let level = Self.budgetAlertLevel(rawFraction)
            if level != .none {
                alerts.append(Self.budgetAlert(status: status, level: level, rawFraction: rawFraction))
            }
        }

        return alerts.sorted { lhs, rhs in
            if lhs.level.priority == rhs.level.priority {
                return lhs.fraction > rhs.fraction
            }
            return lhs.level.priority > rhs.level.priority
        }.first ?? .none
    }

    func diagnosticReport(
        store: UsageStore,
        appVersion: String = "unknown",
        build: String = "unknown",
        generatedAt: Date = Date()
    ) -> String {
        let tokenBudget = tokenBudgetStatus(summary: store.summary)
        let costBudget = costBudgetStatus(summary: store.summary)
        let alert = budgetAlert(summary: store.summary)
        let unpricedModels = store.unpricedModelNames.isEmpty ? "None" : store.unpricedModelNames.joined(separator: ", ")

        return [
            "Codex Usage Monitor Diagnostics",
            "Version: \(appVersion) (\(build))",
            "Generated: \(Self.reportDateFormatter.string(from: generatedAt))",
            "",
            "[Summary]",
            store.summaryText(redactScope: true),
            "",
            "[Health]",
            store.healthStatus.isVisible ? "\(store.healthStatus.title) - \(store.healthStatus.detail)" : "Ready",
            "",
            "[Display]",
            "Menu bar: \(menuBarDisplayMode.rawValue)",
            "Trend metric: \(trendMetric.rawValue)",
            "Auto refresh: \(autoRefreshInterval.rawValue)",
            "Window on launch: \(showWindowOnLaunch ? "On" : "Off")",
            "",
            "[Budgets]",
            "Token: \(tokenBudget.value) - \(tokenBudget.detail)",
            "Cost: \(costBudget.value) - \(costBudget.detail)",
            "Alert: \(alert.isVisible ? "\(alert.title) - \(alert.detail)" : "None")",
            "Notifications: \(budgetNotificationsEnabled ? "On" : "Off")",
            "",
            "[Scan]",
            "Codex home: \(UsageStore.diagnosticDisplayPath(URL(fileURLWithPath: store.scanDiagnostics.codexHomePath)))",
            "Loaded window: \(store.scanDiagnostics.loadedWindowTitle)",
            "Files scanned: \(store.scanDiagnostics.scannedFileCount)",
            "Files from cache: \(store.scanDiagnostics.cachedFileCount)",
            "Cache size: \(UsageStore.byteSize(store.scanDiagnostics.cacheSizeBytes))",
            "Events loaded: \(store.scanDiagnostics.eventCount)",
            "Parse issues: \(store.scanDiagnostics.parseIssueCount)",
            "Latest parse issue: \(store.scanDiagnostics.latestParseIssue ?? "None")",
            "Latest event: \(store.formattedDiagnosticDate(store.scanDiagnostics.latestEventAt))",
            "Latest limit snapshot: \(store.formattedDiagnosticDate(store.scanDiagnostics.latestLimitAt))",
            "Completed: \(store.formattedDiagnosticDate(store.scanDiagnostics.completedAt))",
            "",
            "[Rates]",
            "Configured rates: \(store.rates.count)",
            "Default source: \(UsageStore.defaultRateSourceSummary)",
            "Pricing URL: \(UsageStore.defaultRateSourceURL.absoluteString)",
            "Pricing coverage: \(store.pricingCoverageDescription)",
            "Unpriced models: \(unpricedModels)",
            "Limitations: \(UsageStore.defaultRateLimitations)",
            "",
            "[Privacy]",
            "Reads selected local Codex log folder only.",
            "Sources: sessions, archived_sessions, session_index",
            "Auth files: not read",
            "",
            "[Machine Summary]",
            store.diagnosticSummary
        ].joined(separator: "\n")
    }

    static func loadShowWindowOnLaunch(preferences: UserDefaults = .standard) -> Bool {
        if preferences.object(forKey: showWindowOnLaunchKey) == nil {
            return true
        }
        return preferences.bool(forKey: showWindowOnLaunchKey)
    }

    static func loadMenuBarDisplayMode(preferences: UserDefaults = .standard) -> MenuBarDisplayMode {
        guard let raw = preferences.string(forKey: menuBarDisplayModeKey),
              let mode = MenuBarDisplayMode(rawValue: raw) else {
            return .tokens
        }
        return mode
    }

    static func loadTrendMetric(preferences: UserDefaults = .standard) -> TrendMetric {
        guard let raw = preferences.string(forKey: trendMetricKey),
              let metric = TrendMetric(rawValue: raw) else {
            return .tokens
        }
        return metric
    }

    static func loadAutoRefreshInterval(preferences: UserDefaults = .standard) -> AutoRefreshInterval {
        guard let raw = preferences.string(forKey: autoRefreshIntervalKey),
              let interval = AutoRefreshInterval(rawValue: raw) else {
            return .oneMinute
        }
        return interval
    }

    static func loadBudgetNotificationsEnabled(preferences: UserDefaults = .standard) -> Bool {
        preferences.bool(forKey: budgetNotificationsEnabledKey)
    }

    static func loadTokenBudgetLimit(preferences: UserDefaults = .standard) -> Int {
        max(0, preferences.integer(forKey: tokenBudgetLimitKey))
    }

    static func loadCostBudgetLimit(preferences: UserDefaults = .standard) -> Double {
        let value = preferences.double(forKey: costBudgetLimitKey)
        return value.isFinite ? max(0, value) : 0
    }

    private static func clampedFraction(_ value: Double) -> Double {
        guard value.isFinite else {
            return 0
        }
        return min(max(value, 0), 1)
    }

    private static func budgetAlertLevel(_ rawFraction: Double) -> BudgetAlertLevel {
        guard rawFraction.isFinite else {
            return .none
        }
        if rawFraction >= 1 {
            return .exceeded
        }
        if rawFraction >= budgetWarningThreshold {
            return .warning
        }
        return .none
    }

    private static func budgetAlert(status: BudgetStatus, level: BudgetAlertLevel, rawFraction: Double) -> BudgetAlert {
        BudgetAlert(
            level: level,
            detail: "\(status.title) \(status.value) - \(status.detail)",
            fraction: max(0, rawFraction)
        )
    }

    private static func percentText(_ fraction: Double) -> String {
        guard fraction.isFinite else {
            return "0%"
        }
        return "\(max(0, Int((fraction * 100).rounded())))%"
    }

    private static let showWindowOnLaunchKey = "showWindowOnLaunch.v1"
    private static let menuBarDisplayModeKey = "menuBarDisplayMode.v1"
    private static let trendMetricKey = "trendMetric.v1"
    private static let autoRefreshIntervalKey = "autoRefreshInterval.v1"
    private static let budgetNotificationsEnabledKey = "budgetNotificationsEnabled.v1"
    private static let tokenBudgetLimitKey = "tokenBudgetLimit.v1"
    private static let costBudgetLimitKey = "costBudgetLimit.v1"
    private static let budgetWarningThreshold = 0.80

    private static let reportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
