import SwiftUI
import Charts

// Retain the macOS 13 property wrapper when newer SDKs also expose a State macro.
private typealias ViewState<Value> = SwiftUI.State<Value>

extension Notification.Name {
    static let showCodexUsageSettings = Notification.Name("CodexUsageMonitor.showSettings")
    static let codexUsagePopoverDidClose = Notification.Name("CodexUsageMonitor.popoverDidClose")
}

private enum BreakdownKind: String, CaseIterable, Identifiable {
    case projects = "Projects"
    case chats = "Chats"
    case models = "Models"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .projects: return "folder"
        case .chats: return "bubble.left.and.bubble.right"
        case .models: return "cpu"
        }
    }

    var scopeMode: ScopeMode? {
        switch self {
        case .projects: return .project
        case .chats: return .chat
        case .models: return .model
        }
    }

    @MainActor
    func rows(from store: UsageStore) -> [BreakdownRow] {
        switch self {
        case .projects: return store.projectRows
        case .chats: return store.chatRows
        case .models: return store.modelRows
        }
    }
}

enum SettingsPage: String, CaseIterable, Identifiable {
    case general = "General"
    case budgets = "Budgets"
    case rates = "Rates"
    case diagnostics = "Diagnostics"

    var id: String { rawValue }

    var detail: String {
        switch self {
        case .general:
            return "Startup, menu bar, refresh, and local data"
        case .budgets:
            return "Limits for the active usage filter"
        case .rates:
            return "Editable USD estimates by model"
        case .diagnostics:
            return "Scan health, privacy, and local cache"
        }
    }
}

enum DashboardPage: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case activity = "Activity"
    case breakdown = "Breakdown"

    var id: String { rawValue }
}

struct RootView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var appSettings: AppSettings
    let onClose: () -> Void
    let onQuit: () -> Void

    @ViewState private var showingSettings = false
    @ViewState private var selectedSettingsPage: SettingsPage = .general
    @ViewState private var selectedBreakdown: BreakdownKind = .projects
    @ViewState private var confirmingClearCache = false
    @ViewState private var rateDraft: [ModelRate] = []
    @ViewState private var rateDraftBaseline: [ModelRate] = []
    @ViewState private var dashboardPage: DashboardPage = .overview

    init(store: UsageStore, appSettings: AppSettings, onClose: @escaping () -> Void,
         onQuit: @escaping () -> Void, initialPage: DashboardPage = .overview,
         initialSettingsPage: SettingsPage? = nil) {
        self.store = store
        self.appSettings = appSettings
        self.onClose = onClose
        self.onQuit = onQuit
        _dashboardPage = State(initialValue: initialPage)
        _showingSettings = State(initialValue: initialSettingsPage != nil)
        _selectedSettingsPage = State(initialValue: initialSettingsPage ?? .general)
        _rateDraft = State(initialValue: store.rates)
        _rateDraftBaseline = State(initialValue: store.rates)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(AppColor.border)
            if showingSettings {
                settingsContent
            } else {
                dashboardContent
            }
        }
        .frame(minWidth: 540, minHeight: 580)
        .background(AppColor.background)
        .foregroundStyle(AppColor.primaryText)
        .tint(AppColor.accent)
        .onAppear {
            store.refreshIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showCodexUsageSettings)) { _ in
            showSettings(.general)
        }
        .onReceive(NotificationCenter.default.publisher(for: .codexUsagePopoverDidClose)) { _ in
            if showingSettings {
                leaveSettings()
            }
        }
        .onChange(of: store.rates) { newRates in
            if !showingSettings || selectedSettingsPage != .rates || rateDraft == rateDraftBaseline {
                rateDraft = newRates
                rateDraftBaseline = newRates
            }
        }
        .onExitCommand {
            if showingSettings {
                leaveSettings()
            } else {
                closePopover()
            }
        }
        .confirmationDialog("Clear Parse Caches?", isPresented: $confirmingClearCache) {
            Button("Clear Caches", role: .destructive) {
                store.clearParseCache()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The app will delete its local parsed-log caches. Your Codex logs and settings are not changed.")
        }
    }

    private var dashboardContent: some View {
        VStack(spacing: 0) {
            filters
            NavigationTabs(selection: $dashboardPage, items: DashboardPage.allCases, title: { $0.rawValue })
                .padding(.horizontal, 22)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    if store.isLoadingSelectedWindow {
                        LoadingUsagePanel(windowTitle: store.dateWindow.title, detail: store.loadMessage)
                    } else {
                        if store.healthStatus.isVisible {
                            healthNotice.padding(.top, 14)
                        }
                        switch dashboardPage {
                        case .overview:
                            summaryHero
                            Divider()
                            limits.padding(.vertical, 16)
                            Divider()
                            TrendPanel(rows: store.dailyRows, metric: Binding(get: {
                                appSettings.trendMetric
                            }, set: { appSettings.setTrendMetric($0) }))
                            Divider()
                            usageComposition
                            if appSettings.hasBudgetLimits {
                                Divider()
                                budgetStatusSection
                            }
                        case .activity:
                            recentActivity
                        case .breakdown:
                            breakdown
                            Divider()
                            costDetails
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 16)
            }
            .id(dashboardPage)
            Divider()
            HStack(spacing: 6) {
                Image(systemName: store.isRefreshing ? "arrow.triangle.2.circlepath" : "checkmark.circle")
                    .foregroundStyle(store.isRefreshing ? AppColor.secondaryText : AppColor.green)
                Text(store.isRefreshing ? "Refreshing" : "Updated \(store.lastRefreshText)")
                Spacer()
                Text("\(store.summary.sessionCount) chats")
                Text("\u{00B7}")
                Text("\(store.summary.eventCount) events")
            }
            .font(.system(size: 11))
            .foregroundStyle(AppColor.secondaryText)
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background(AppColor.panel)
        }
    }

    private var settingsContent: some View {
        VStack(spacing: 0) {
            NavigationTabs(selection: $selectedSettingsPage, items: SettingsPage.allCases, title: { $0.rawValue })
            .padding(.horizontal, 22)
            Divider()

            ScrollView(showsIndicators: false) {
                Group {
                    switch selectedSettingsPage {
                    case .general:
                        appSettingsSection
                    case .budgets:
                        budgetSettingsSection
                    case .rates:
                        rateSettingsSection
                    case .diagnostics:
                        diagnosticsSection
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 18)
            }
            .id(selectedSettingsPage)
        }
    }

    private var healthNotice: some View {
        HealthNotice(status: store.healthStatus) { action in
            handleHealthAction(action)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            if showingSettings {
                HeaderButton(symbol: "chevron.left", help: "Back to dashboard") {
                    leaveSettings()
                }
                .keyboardShortcut(.cancelAction)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(showingSettings ? "Settings" : "Codex Usage")
                    .font(.system(size: 17, weight: .semibold))
                Text(showingSettings ? selectedSettingsPage.detail : "Tokens & API cost")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColor.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            if !showingSettings {
                HeaderButton(symbol: "arrow.clockwise", help: "Refresh") {
                    store.refresh()
                }
                .opacity(store.isRefreshing ? 0.45 : 1)
                .disabled(store.isRefreshing)
                HeaderActionMenu(store: store)
                HeaderButton(symbol: "gearshape", help: "Settings") {
                    showSettings(.general)
                }
                HeaderButton(symbol: "power", help: "Quit Codex Usage Monitor") {
                    onQuit()
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }


    private var summaryHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 24) {
                PrimaryFigure(
                    title: "Total tokens",
                    value: UsageStore.compactNumber(store.summary.tokens.total),
                    caption: store.historyCaption
                )
                PrimaryFigure(
                    title: "Estimated cost",
                    value: UsageStore.currency(store.summary.cost),
                    caption: costCaption
                )
                .help("\(UsageStore.defaultRateSourceSummary). \(UsageStore.defaultRateLimitations)")
            }
            if store.comparison.isVisible {
                HStack(spacing: 6) {
                    Image(systemName: store.comparison.tokenDelta >= 0 ? "arrow.up.right" : "arrow.down.right")
                    Text("\(UsageStore.signedPercent(store.comparison.tokenDeltaPercent)) tokens")
                    Text("\u{00B7}")
                    Text("\(UsageStore.signedCurrency(store.comparison.costDelta))")
                    Text("vs \(store.comparison.label)")
                        .foregroundStyle(AppColor.tertiaryText)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppColor.secondaryText)
                .lineLimit(1)
                .help("Previous period: \(UsageStore.compactNumber(store.comparison.previousTokens)) tokens, \(UsageStore.currency(store.comparison.previousCost))")
            }
        }
        .padding(.vertical, 20)
    }

    private var filters: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Menu {
                    ForEach(ScopeMode.allCases) { mode in
                        Button {
                            store.setScopeMode(mode)
                        } label: {
                            if store.scopeMode == mode {
                                Label(mode == .all ? "All activity" : mode.rawValue, systemImage: "checkmark")
                            } else {
                                Text(mode == .all ? "All activity" : mode.rawValue)
                            }
                        }
                    }
                } label: {
                    Label(store.scopeMode == .all ? "All activity" : store.scopeMode.rawValue, systemImage: "line.3.horizontal.decrease")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColor.primaryText)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Scope")
                Spacer(minLength: 8)
                Picker("Window", selection: Binding(get: {
                    store.dateWindow
                }, set: { store.setDateWindow($0) })) {
                    ForEach(DateWindow.allCases) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 236)
            }
            if store.scopeMode != .all {
                Picker("Target", selection: Binding(get: {
                    store.selectedScopeID
                }, set: { store.setSelectedScope($0) })) {
                    Text("Any \(store.scopeMode.rawValue.lowercased())").tag("")
                    ForEach(store.scopeOptions) { row in
                        Text(row.label).tag(row.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var usageComposition: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle("Token composition")
                Text("Tokens")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColor.tertiaryText)
            }
            StatRow(symbol: "arrow.down.left", color: AppColor.blue, label: "Non-cached input", value: UsageStore.compactNumber(store.summary.tokens.nonCachedInput))
            StatRow(symbol: "bolt.horizontal", color: AppColor.gold, label: "Cached input", value: UsageStore.compactNumber(store.summary.tokens.cachedInput))
            StatRow(symbol: "arrow.up.right", color: AppColor.rose, label: "Output", value: UsageStore.compactNumber(store.summary.tokens.output))
            StatRow(symbol: "sparkles", color: AppColor.green, label: "Reasoning (included in output)", value: UsageStore.compactNumber(store.summary.tokens.reasoningOutput))
            HStack {
                Text("Avg / 1M")
                Text(UsageStore.currency(store.averageCostPerMillion)).foregroundStyle(AppColor.primaryText)
                Spacer()
                Text("30d pace")
                Text(UsageStore.currency(store.thirtyDayCostPace)).foregroundStyle(AppColor.primaryText)
            }
            .font(.system(size: 11))
            .foregroundStyle(AppColor.secondaryText)
            .padding(.top, 6)
        }
        .padding(.vertical, 16)
    }

    private var limits: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            limitsContent(now: context.date)
        }
    }

    private func limitsContent(now: Date) -> some View {
        let snapshot = store.latestLimits
        let windows = snapshot?.reportedWindows ?? []
        let resetDisplay = UsageStore.resetCreditDisplay(snapshot, now: now)

        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Account allowance")
            VStack(spacing: 12) {
                if windows.isEmpty {
                    LimitTile(
                        symbol: "gauge",
                        title: "Usage",
                        value: "No data",
                        detail: snapshot == nil ? "No local snapshot" : "No window reported",
                        color: AppColor.tertiaryText
                    )
                } else {
                    ForEach(Array(windows.indices), id: \.self) { index in
                        let limit = windows[index]
                        let display = UsageStore.windowLimitDisplay(
                            limit,
                            snapshotSeenAt: snapshot?.seenAt,
                            now: now
                        )
                        LimitTile(
                            symbol: limit.kind.symbol,
                            title: limit.kind.title,
                            value: display.value,
                            detail: display.detail,
                            color: display.isExpired
                                ? AppColor.tertiaryText
                                : (limit.kind.usesCalendarColor ? AppColor.green : AppColor.accent)
                        )
                    }
                }
                LimitTile(
                    symbol: "plus",
                    title: "Resets",
                    value: resetDisplay.value,
                    detail: resetDisplay.detail,
                    color: resetDisplay.isExpired ? AppColor.tertiaryText : AppColor.gold
                )
            }
            if let credits = snapshot?.resetCredits, !credits.isEmpty {
                DisclosureGroup("Reset credit expiry") {
                    VStack(spacing: 7) {
                        ForEach(credits) { credit in
                            ResetCreditRowView(credit: credit, now: now)
                        }
                    }
                    .padding(.top, 8)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppColor.secondaryText)
            }
        }
    }

    private var recentActivity: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle("Recent Activity")
                    Spacer()
                    Text(store.recentRows.isEmpty ? "No events" : "\(store.recentRows.count) latest")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppColor.tertiaryText)
                }

                if store.recentRows.isEmpty {
                    EmptyState(text: "No recent token events for this filter")
                } else {
                    VStack(spacing: 7) {
                        ForEach(store.recentRows) { row in
                            RecentActivityRowView(row: row)
                        }
                    }
                }
            }
        }
    }


    private var costDetails: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle("Estimated Cost Mix")
                    Spacer()
                    Text(UsageStore.currency(store.summary.cost))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppColor.green)
                }

                if store.costRows.isEmpty {
                    EmptyState(text: "No cost rows for this filter")
                } else {
                    VStack(spacing: 7) {
                        ForEach(store.costRows) { row in
                            CostComponentRowView(row: row)
                        }
                    }
                }
            }
        }
    }

    private var breakdown: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle("Breakdown")
                    Spacer()
                    Picker("Breakdown", selection: $selectedBreakdown) {
                        ForEach(BreakdownKind.allCases) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 230)
                    .labelsHidden()
                }

                let rows = selectedBreakdown.rows(from: store)
                if rows.isEmpty {
                    EmptyState(text: "No \(selectedBreakdown.rawValue.lowercased()) for this filter")
                } else {
                    VStack(spacing: 7) {
                        ForEach(rows) { row in
                            if let mode = selectedBreakdown.scopeMode {
                                Button {
                                    store.setScopeMode(mode)
                                    store.setSelectedScope(row.id)
                                    dashboardPage = .overview
                                } label: {
                                    BreakdownRowView(row: row, symbol: selectedBreakdown.symbol)
                                }
                                .buttonStyle(.plain)
                            } else {
                                BreakdownRowView(row: row, symbol: selectedBreakdown.symbol)
                            }
                        }
                    }
                }
            }
        }
    }

    private var appSettingsSection: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle("App")
                    Spacer()
                    Button {
                        AppActions.importSettings(store: store, settings: appSettings)
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Import settings")
                    .accessibilityLabel("Import settings")
                    Button {
                        AppActions.exportSettings(store: store, settings: appSettings)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Export settings")
                    .accessibilityLabel("Export settings")
                    Button("Refresh") {
                        appSettings.refreshLaunchAtLoginStatus()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                HStack(spacing: 11) {
                    Image(systemName: "folder")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppColor.blue)
                        .frame(width: 20, height: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Codex log folder")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColor.primaryText)
                        Text(store.codexHomeDisplayPath)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppColor.tertiaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .minimumScaleFactor(0.78)
                    }

                    Spacer()

                    Button {
                        AppActions.chooseCodexFolder(store: store)
                    } label: {
                        Label("Choose", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .help("Choose Codex log folder")

                    Button {
                        AppActions.resetCodexFolder(store: store)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.usesDefaultCodexHome)
                    .help("Reset to ~/.codex")
                    .accessibilityLabel("Reset Codex log folder")
                }
                .padding(.vertical, 12)

                HStack(spacing: 11) {
                    Image(systemName: "power")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppColor.accent)
                        .frame(width: 20, height: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at login")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColor.primaryText)
                        Text(appSettings.launchAtLoginDetail)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppColor.tertiaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }

                    Spacer()

                    Toggle("", isOn: Binding(get: {
                        appSettings.launchAtLoginEnabled
                    }, set: { newValue in
                        appSettings.setLaunchAtLogin(newValue)
                    }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(!appSettings.launchAtLoginCanToggle)
                    .help(appSettings.launchAtLoginDetail)
                    .accessibilityLabel("Launch at login")
                }
                .padding(.vertical, 12)

                HStack(spacing: 11) {
                    Image(systemName: "menubar.rectangle")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppColor.green)
                        .frame(width: 20, height: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open popover on launch")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColor.primaryText)
                        Text(appSettings.showWindowOnLaunchDetail)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppColor.tertiaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }

                    Spacer()

                    Toggle("", isOn: Binding(get: {
                        appSettings.showWindowOnLaunch
                    }, set: { newValue in
                        appSettings.setShowWindowOnLaunch(newValue)
                    }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .help(appSettings.showWindowOnLaunchDetail)
                    .accessibilityLabel("Open popover on launch")
                }
                .padding(.vertical, 12)

                HStack(spacing: 11) {
                    Image(systemName: "textformat.size")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppColor.gold)
                        .frame(width: 20, height: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Menu bar display")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColor.primaryText)
                        Text(appSettings.menuBarDisplayMode.detail)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppColor.tertiaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }

                    Spacer()

                    Picker("Menu bar display", selection: Binding(get: {
                        appSettings.menuBarDisplayMode
                    }, set: { newValue in
                        appSettings.setMenuBarDisplayMode(newValue)
                    })) {
                        ForEach(MenuBarDisplayMode.allCases) { mode in
                            Text(mode.displayTitle).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                .padding(.vertical, 12)

                HStack(spacing: 11) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppColor.rose)
                        .frame(width: 20, height: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Budget notifications")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColor.primaryText)
                        Text(appSettings.budgetNotificationsEnabled ? "Alerts for warning and exceeded budgets" : "Off")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppColor.tertiaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }

                    Spacer()

                    Toggle("", isOn: Binding(get: {
                        appSettings.budgetNotificationsEnabled
                    }, set: { newValue in
                        appSettings.setBudgetNotificationsEnabled(newValue)
                    }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .help("Budget notifications")
                    .accessibilityLabel("Budget notifications")
                }
                .padding(.vertical, 12)

                HStack(spacing: 11) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppColor.blue)
                        .frame(width: 20, height: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto refresh")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColor.primaryText)
                        Text(appSettings.autoRefreshInterval.detail)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppColor.tertiaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }

                    Spacer()

                    Picker("Auto refresh", selection: Binding(get: {
                        appSettings.autoRefreshInterval
                    }, set: { newValue in
                        appSettings.setAutoRefreshInterval(newValue)
                    })) {
                        ForEach(AutoRefreshInterval.allCases) { interval in
                            Text(interval.rawValue).tag(interval)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
                .padding(.vertical, 12)
            }
        }
    }

    private var diagnosticsSection: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle("Diagnostics & Privacy")
                    Spacer()
                    Button {
                        AppActions.copyDiagnostics(store: store, settings: appSettings)
                    } label: {
                        Label("Copy Report", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .help("Copies a report with custom folder paths redacted")
                    Button {
                        confirmingClearCache = true
                    } label: {
                        Label("Clear Caches", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.scanDiagnostics.cacheSizeBytes == 0 || store.isRefreshing)
                    Text(store.isRefreshing ? "Scanning" : "Ready")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(store.isRefreshing ? AppColor.gold : AppColor.green)
                }

                LazyVGrid(columns: AppStyle.twoColumns, spacing: 8) {
                    DiagnosticTile(
                        symbol: "folder",
                        title: "Codex home",
                        value: store.scanDiagnostics.codexHomePath,
                        color: AppColor.accent
                    )
                    DiagnosticTile(
                        symbol: "calendar",
                        title: "Loaded window",
                        value: store.scanDiagnostics.loadedWindowTitle,
                        color: AppColor.green
                    )
                    DiagnosticTile(
                        symbol: "doc.text",
                        title: "Files scanned",
                        value: "\(store.scanDiagnostics.scannedFileCount)",
                        color: AppColor.blue
                    )
                    DiagnosticTile(
                        symbol: "bolt.horizontal",
                        title: "Cache hits",
                        value: "\(store.scanDiagnostics.cachedFileCount)",
                        color: AppColor.green
                    )
                    DiagnosticTile(
                        symbol: "externaldrive",
                        title: "Cache size",
                        value: UsageStore.byteSize(store.scanDiagnostics.cacheSizeBytes),
                        color: AppColor.accent
                    )
                    DiagnosticTile(
                        symbol: "number",
                        title: "Events loaded",
                        value: "\(store.scanDiagnostics.eventCount)",
                        color: AppColor.gold
                    )
                    DiagnosticTile(
                        symbol: "exclamationmark.triangle",
                        title: "Parse issues",
                        value: "\(store.scanDiagnostics.parseIssueCount)",
                        color: store.scanDiagnostics.parseIssueCount > 0 ? AppColor.rose : AppColor.green
                    )
                    DiagnosticTile(
                        symbol: "clock",
                        title: "Last scan",
                        value: store.formattedDiagnosticDate(store.scanDiagnostics.completedAt),
                        color: AppColor.rose
                    )
                    DiagnosticTile(
                        symbol: "chart.line.uptrend.xyaxis",
                        title: "Latest event",
                        value: store.formattedDiagnosticDate(store.scanDiagnostics.latestEventAt),
                        color: AppColor.accent
                    )
                }

                HStack(spacing: 11) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(AppColor.green)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Local only")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColor.primaryText)
                        Text("Codex logs plus local parse cache")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppColor.tertiaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }

                    Spacer()

                    Text("No auth")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppColor.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(AppColor.control)
                        .clipShape(RoundedRectangle(cornerRadius: AppStyle.smallRadius, style: .continuous))
                }
                .padding(12)
                .background(AppColor.row)
                .clipShape(RoundedRectangle(cornerRadius: AppStyle.smallRadius, style: .continuous))
            }
        }
    }

    private var budgetStatusSection: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle("Budgets")
                    Spacer()
                    Text(store.dateWindow.rawValue)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppColor.tertiaryText)
                }

                HStack(spacing: 8) {
                    BudgetStatusTile(status: appSettings.tokenBudgetStatus(summary: store.summary), color: AppColor.accent)
                    BudgetStatusTile(status: appSettings.costBudgetStatus(summary: store.summary), color: AppColor.green)
                }
            }
        }
    }

    private var budgetSettingsSection: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle("Budgets")
                    Spacer()
                    Text(scopeTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColor.tertiaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                BudgetInputRow(
                    symbol: "number",
                    title: "Token budget",
                    detail: appSettings.tokenBudgetStatus(summary: store.summary).detail,
                    color: AppColor.accent
                ) {
                    TextField("", value: Binding(get: {
                        appSettings.tokenBudgetLimit
                    }, set: { newValue in
                        appSettings.setTokenBudgetLimit(newValue)
                    }), format: .number)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppColor.primaryText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .frame(width: 96)
                    .background(AppColor.control)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .accessibilityLabel("Token budget")
                }

                BudgetInputRow(
                    symbol: "dollarsign",
                    title: "Estimated cost budget",
                    detail: appSettings.costBudgetStatus(summary: store.summary).detail,
                    color: AppColor.green
                ) {
                    TextField("", value: Binding(get: {
                        appSettings.costBudgetLimit
                    }, set: { newValue in
                        appSettings.setCostBudgetLimit(newValue)
                    }), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppColor.primaryText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .frame(width: 96)
                    .background(AppColor.control)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .accessibilityLabel("Estimated cost budget")
                }
            }
        }
    }

    private var rateSettingsSection: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle("Rates")
                    Spacer()
                    Text("USD per 1M tokens")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppColor.tertiaryText)
                    Button {
                        rateDraft = store.ratesByAddingCustomRow(to: rateDraft)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Add custom model rate")
                    .accessibilityLabel("Add custom model rate")
                }

                HStack(spacing: 11) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(AppColor.green)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(UsageStore.defaultRateProfileName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColor.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text(store.pricingUpdateMessage)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppColor.tertiaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Button {
                        AppActions.openPricingPage()
                    } label: {
                        Image(systemName: "link")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Open pricing source")
                    .accessibilityLabel("Open pricing source")

                    Button {
                        rateDraft = store.officialRates
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Restore official standard rates")
                    .accessibilityLabel("Restore official standard rates")
                }
                .padding(12)
                .background(AppColor.row)
                .clipShape(RoundedRectangle(cornerRadius: AppStyle.smallRadius, style: .continuous))

                HStack {
                    Toggle("Automatic pricing updates", isOn: $store.automaticPricingUpdates)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button {
                        store.refreshPricingIfNeeded(force: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(store.isUpdatingPricing)
                    .help("Check official pricing now")
                    .accessibilityLabel("Check official pricing now")
                }

                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColor.tertiaryText)
                    Text(UsageStore.defaultRateLimitations)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppColor.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !store.unpricedModelNames.isEmpty {
                    HStack(spacing: 11) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(AppColor.rose)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(unpricedTitle)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppColor.primaryText)
                                .lineLimit(1)
                            Text("\(store.pricingCoverage.percentText) of logged tokens priced")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(AppColor.gold)
                                .lineLimit(1)
                            Text(store.unpricedModelNames.prefix(3).joined(separator: ", "))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AppColor.tertiaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }

                        Spacer()

                        Button {
                            rateDraft = store.ratesByAddingMissingRows(to: rateDraft)
                        } label: {
                            Label("Add", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(12)
                    .background(AppColor.row)
                    .clipShape(RoundedRectangle(cornerRadius: AppStyle.smallRadius, style: .continuous))
                }

                VStack(spacing: 8) {
                    HStack {
                        Text("Model").frame(minWidth: 144, maxWidth: .infinity, alignment: .leading)
                        Text("Input").frame(width: 72, alignment: .trailing)
                        Text("Cached").frame(width: 72, alignment: .trailing)
                        Text("Output").frame(width: 72, alignment: .trailing)
                        Text("").frame(width: 20)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColor.secondaryText)

                    ForEach(rateDraft.indices, id: \.self) { index in
                        let modelName = rateDraft[index].model.isEmpty ? "rate row \(index + 1)" : rateDraft[index].model
                        HStack(spacing: 8) {
                            RateModelField(
                                value: $rateDraft[index].model,
                                accessibilityLabel: "Model name for rate row \(index + 1)"
                            )
                            RateField(
                                value: $rateDraft[index].inputPerMillion,
                                accessibilityLabel: "Input rate for \(modelName)"
                            )
                            RateField(
                                value: $rateDraft[index].cachedInputPerMillion,
                                accessibilityLabel: "Cached input rate for \(modelName)"
                            )
                            RateField(
                                value: $rateDraft[index].outputPerMillion,
                                accessibilityLabel: "Output rate for \(modelName)"
                            )
                            Button {
                                rateDraft.remove(at: index)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11, weight: .bold))
                                    .frame(width: 20, height: 20)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(AppColor.tertiaryText)
                            .help("Remove model rate")
                            .accessibilityLabel("Remove rate for \(modelName)")
                        }
                    }
                }
                .padding(12)
                .background(AppColor.tableBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppStyle.radius, style: .continuous))

                HStack {
                    Text(hasUnsavedRateChanges ? "Unsaved rate changes" : store.loadMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(hasUnsavedRateChanges ? AppColor.gold : AppColor.secondaryText)
                        .lineLimit(1)
                    Spacer()
                    Button("Revert") {
                        rateDraft = rateDraftBaseline
                    }
                    .disabled(!hasUnsavedRateChanges)
                    Button("Apply") {
                        store.applyRates(rateDraft)
                        rateDraft = store.rates
                        rateDraftBaseline = store.rates
                    }
                    .disabled(!hasUnsavedRateChanges)
                    .keyboardShortcut(.defaultAction)
                }
                .buttonStyle(.bordered)
            }
        }
    }


    private var scopeTitle: String {
        switch store.scopeMode {
        case .all:
            return "All activity"
        case .project:
            guard !store.selectedScopeID.isEmpty else { return "Any project" }
            return store.projectOptionRows.first { $0.id == store.selectedScopeID }?.label ?? "Selected project"
        case .chat:
            guard !store.selectedScopeID.isEmpty else { return "Any chat" }
            return store.chatOptionRows.first { $0.id == store.selectedScopeID }?.label ?? "Selected chat"
        case .model:
            guard !store.selectedScopeID.isEmpty else { return "Any model" }
            return store.modelOptionRows.first { $0.id == store.selectedScopeID }?.label ?? "Selected model"
        }
    }

    private var costCaption: String {
        guard store.pricingCoverage.observedTokens > 0 else {
            return "API estimate / no tokens"
        }
        return "API estimate / \(store.pricingCoverage.percentText) priced"
    }

    private var unpricedTitle: String {
        let count = store.unpricedModelNames.count
        return "\(count) model\(count == 1 ? "" : "s") \(count == 1 ? "needs" : "need") rates"
    }

    private func handleHealthAction(_ action: UsageHealthAction) {
        switch action {
        case .refresh:
            store.refresh()
        case .openLogs:
            AppActions.openCodexFolder(store: store)
        case .chooseLogs:
            AppActions.chooseCodexFolder(store: store)
        case .clearFilter:
            store.setSelectedScope("")
        case .addRates:
            showSettings(.rates)
            rateDraft = store.ratesByAddingMissingRows(to: rateDraft)
        }
    }

    private func showSettings(_ page: SettingsPage) {
        if !showingSettings {
            rateDraft = store.rates
            rateDraftBaseline = store.rates
        }
        selectedSettingsPage = page
        showingSettings = true
    }

    private var hasUnsavedRateChanges: Bool {
        rateDraft != rateDraftBaseline
    }

    private func leaveSettings() {
        rateDraft = store.rates
        rateDraftBaseline = store.rates
        showingSettings = false
    }

    private func closePopover() {
        rateDraft = store.rates
        rateDraftBaseline = store.rates
        onClose()
    }
}

private struct HeaderButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 31, height: 31)
                .background(AppColor.control)
                .clipShape(RoundedRectangle(cornerRadius: AppStyle.smallRadius, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppColor.primaryText)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct NavigationTabs<Item: Hashable & Identifiable>: View {
    @Binding var selection: Item
    let items: [Item]
    let title: (Item) -> String

    var body: some View {
        HStack(spacing: 24) {
            ForEach(items) { item in
                Button {
                    selection = item
                } label: {
                    Text(title(item))
                        .font(.system(size: 12, weight: selection == item ? .semibold : .medium))
                        .foregroundStyle(selection == item ? AppColor.primaryText : AppColor.secondaryText)
                        .padding(.vertical, 12)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(selection == item ? AppColor.accent : .clear)
                                .frame(height: 2)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title(item))
                .accessibilityAddTraits(selection == item ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
    }
}

private struct HeaderActionMenu: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        Menu {
            Button {
                AppActions.copySummary(store: store)
            } label: {
                Label("Copy Summary", systemImage: "doc.on.doc")
            }
            Button {
                AppActions.exportCSV(store: store)
            } label: {
                Label("Export CSV...", systemImage: "square.and.arrow.down")
            }
            Divider()
            Button {
                AppActions.openCodexFolder(store: store)
            } label: {
                Label("Open Codex Logs", systemImage: "folder")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 31, height: 31)
                .background(AppColor.control)
                .clipShape(RoundedRectangle(cornerRadius: AppStyle.smallRadius, style: .continuous))
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(AppColor.primaryText)
        .help("More actions")
        .accessibilityLabel("More actions")
    }
}

private struct Panel<Content: View>: View {
    let padding: CGFloat
    let content: Content

    init(padding: CGFloat = 0, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SectionTitle: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppColor.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HealthNotice: View {
    let status: UsageHealthStatus
    let actionHandler: (UsageHealthAction) -> Void

    private var color: Color {
        switch status.level {
        case .info: return AppColor.blue
        case .warning: return AppColor.gold
        }
    }

    private var symbol: String {
        switch status.level {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(status.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColor.primaryText)
                    .lineLimit(1)
                Text(status.detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColor.tertiaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 8)

            if let action = status.action {
                Button(action.rawValue) {
                    actionHandler(action)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(color.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: AppStyle.radius, style: .continuous)
                .stroke(color.opacity(0.28), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppStyle.radius, style: .continuous))
    }
}

private struct PrimaryFigure: View {
    let title: String
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColor.secondaryText)
            Text(value)
                .font(.system(size: 32, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(AppColor.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(caption)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppColor.tertiaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


private struct TrendPanel: View {
    let rows: [DailyUsageRow]
    @Binding var metric: TrendMetric

    private var axisPositions: [Double] {
        guard rows.count > 7 else { return rows.indices.map(Double.init) }
        return (0..<5).map { Double((2 * $0 + 1) * rows.count / 10) }
    }

    private func value(for row: DailyUsageRow) -> Double {
        metric == .tokens ? Double(row.tokens.total) : row.cost
    }

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionTitle("Daily usage")
                    Picker("Trend metric", selection: $metric) {
                        ForEach(TrendMetric.allCases) { value in
                            Text(value.displayTitle).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 142)
                    .accessibilityLabel("Trend metric")
                }
                if rows.isEmpty {
                    EmptyState(text: "No daily activity for this filter")
                } else {
                    Chart(Array(rows.enumerated()), id: \.element.id) { item in
                        let row = item.element
                        let halfWidth = rows.count == 1 ? 0.03 : 0.325
                        RectangleMark(
                            xStart: .value("Day", Double(item.offset) - halfWidth),
                            xEnd: .value("Day", Double(item.offset) + halfWidth),
                            yStart: .value("Baseline", 0),
                            yEnd: .value(metric == .tokens ? "Tokens" : "USD", value(for: row))
                        )
                        .foregroundStyle(metric == .tokens ? AppColor.accent : AppColor.blue)
                        .cornerRadius(2)
                        .accessibilityLabel(row.label)
                        .accessibilityValue(metric == .tokens
                            ? "\(UsageStore.compactNumber(row.tokens.total)) tokens"
                            : "\(UsageStore.currency(row.cost)) estimated cost")
                    }
                    .chartXScale(domain: -0.5...max(0.5, Double(rows.count) - 0.5))
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { axis in
                            AxisGridLine().foregroundStyle(AppColor.border)
                            AxisValueLabel(anchor: .trailing) {
                                if let value = axis.as(Double.self) {
                                    Text(metric == .tokens ? UsageStore.compactNumber(Int(min(value, Double(Int.max / 2)))) : UsageStore.currency(value))
                                        .font(.system(size: 9))
                                        .foregroundStyle(AppColor.tertiaryText)
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: axisPositions) { axis in
                            AxisValueLabel(anchor: .top) {
                                if let position = axis.as(Double.self), rows.indices.contains(Int(position)) {
                                    Text(rows[Int(position)].label)
                                        .font(.system(size: 9))
                                        .foregroundStyle(AppColor.secondaryText)
                                }
                            }
                        }
                    }
                    .frame(height: 112)
                }
            }
        }
    }
}

private struct LimitTile: View {
    let symbol: String
    let title: String
    let value: String
    let detail: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 20)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)
            Spacer(minLength: 8)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(AppColor.secondaryText)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .help("\(title): \(value). \(detail)")
    }
}

private struct ResetCreditRowView: View {
    let credit: ResetCredit
    let now: Date

    private var isExpired: Bool {
        credit.expiresAt.map { $0 <= now } ?? false
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(isExpired ? AppColor.tertiaryText : AppColor.gold)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(credit.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColor.primaryText)
                    .lineLimit(1)
                Text(UsageStore.expiryDateText(credit.expiresAt))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColor.tertiaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(UsageStore.expiryText(credit.expiresAt, now: now))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(credit.expiresAt == nil || isExpired ? AppColor.tertiaryText : AppColor.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(AppColor.row)
        .clipShape(RoundedRectangle(cornerRadius: AppStyle.smallRadius, style: .continuous))
        .help("\(credit.label): \(UsageStore.expiryDateText(credit.expiresAt))")
    }
}

private struct StatRow: View {
    let symbol: String
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 18, height: 18)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColor.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(AppColor.primaryText)
                .lineLimit(1)
        }
    }
}

private struct DiagnosticTile: View {
    let symbol: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColor.tertiaryText)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppColor.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .minimumScaleFactor(0.72)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .background(AppColor.row)
        .clipShape(RoundedRectangle(cornerRadius: AppStyle.smallRadius, style: .continuous))
        .help(value)
    }
}

private struct BudgetStatusTile: View {
    let status: BudgetStatus
    let color: Color

    private var effectiveColor: Color {
        status.isExceeded ? AppColor.rose : color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(status.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColor.secondaryText)
                    .lineLimit(1)
                Spacer()
                Text(status.value)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(effectiveColor)
                    .lineLimit(1)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(AppColor.control)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(effectiveColor)
                        .frame(width: proxy.size.width * status.fraction)
                }
            }
            .frame(height: 7)

            Text(status.detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppColor.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(AppColor.row)
        .clipShape(RoundedRectangle(cornerRadius: AppStyle.smallRadius, style: .continuous))
    }
}

private struct BudgetInputRow<Field: View>: View {
    let symbol: String
    let title: String
    let detail: String
    let color: Color
    let field: Field

    init(symbol: String, title: String, detail: String, color: Color, @ViewBuilder field: () -> Field) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.color = color
        self.field = field()
    }

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColor.primaryText)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColor.tertiaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer()
            field
        }
        .padding(12)
        .background(AppColor.row)
        .clipShape(RoundedRectangle(cornerRadius: AppStyle.smallRadius, style: .continuous))
    }
}

private struct BreakdownRowView: View {
    let row: BreakdownRow
    let symbol: String

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColor.secondaryText)
                .frame(width: 30, height: 30)
                .background(AppColor.control)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(row.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColor.primaryText)
                    .lineLimit(1)
                Text(row.detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColor.tertiaryText)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(UsageStore.compactNumber(row.tokens.total))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppColor.primaryText)
                    .lineLimit(1)
                Text(UsageStore.currency(row.cost))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppColor.green)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(AppColor.row)
        .clipShape(RoundedRectangle(cornerRadius: AppStyle.smallRadius, style: .continuous))
    }
}

private struct CostComponentRowView: View {
    let row: CostComponentRow

    private var color: Color {
        switch row.id {
        case "input": return AppColor.blue
        case "cached": return AppColor.gold
        case "output": return AppColor.rose
        default: return AppColor.accent
        }
    }

    private var symbol: String {
        switch row.id {
        case "input": return "arrow.down.left"
        case "cached": return "bolt.horizontal"
        case "output": return "arrow.up.right"
        default: return "sum"
        }
    }

    private var percentText: String {
        guard row.fraction > 0 else {
            return "0%"
        }
        return String(format: "%.0f%%", row.fraction * 100)
    }

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColor.primaryText)
                            .lineLimit(1)
                        Text("\(UsageStore.compactNumber(row.tokens)) tokens / \(row.detail)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppColor.tertiaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(UsageStore.currency(row.cost))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppColor.primaryText)
                            .lineLimit(1)
                        Text(percentText)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(color)
                            .lineLimit(1)
                    }
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(AppColor.control)
                        if row.fraction > 0 {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(color)
                                .frame(width: max(2, proxy.size.width * row.fraction))
                        }
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(AppColor.row)
        .clipShape(RoundedRectangle(cornerRadius: AppStyle.smallRadius, style: .continuous))
        .help("\(row.label): \(UsageStore.compactNumber(row.tokens)) tokens, \(UsageStore.currency(row.cost))")
    }
}

private struct RecentActivityRowView: View {
    let row: RecentActivityRow

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "clock")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColor.secondaryText)
                .frame(width: 30, height: 30)
                .background(AppColor.control)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(row.time)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppColor.accent)
                        .lineLimit(1)
                    Text(row.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColor.primaryText)
                        .lineLimit(1)
                }
                Text(row.detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColor.tertiaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(UsageStore.compactNumber(row.tokens.total))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppColor.primaryText)
                    .lineLimit(1)
                Text(UsageStore.currency(row.cost))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppColor.green)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(AppColor.row)
        .clipShape(RoundedRectangle(cornerRadius: AppStyle.smallRadius, style: .continuous))
    }
}

private struct EmptyState: View {
    let text: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "tray")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColor.tertiaryText)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColor.secondaryText)
            Spacer()
        }
        .padding(12)
        .background(AppColor.row)
        .clipShape(RoundedRectangle(cornerRadius: AppStyle.smallRadius, style: .continuous))
    }
}

private struct LoadingUsagePanel: View {
    let windowTitle: String
    let detail: String

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 11) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(AppColor.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Loading \(windowTitle.lowercased()) usage")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColor.primaryText)
                        Text(detail)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppColor.tertiaryText)
                            .lineLimit(1)
                    }
                }

                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(AppColor.accent)
                    .accessibilityLabel("Loading \(windowTitle) usage")
            }
        }
    }
}

private struct RateModelField: View {
    @Binding var value: String
    let accessibilityLabel: String

    var body: some View {
        TextField("model", text: $value)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(AppColor.primaryText)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .frame(minWidth: 144, maxWidth: .infinity)
            .background(AppColor.control)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityLabel(accessibilityLabel)
    }
}

private struct RateField: View {
    @Binding var value: Double
    let accessibilityLabel: String

    var body: some View {
        TextField("", value: $value, format: .number.precision(.fractionLength(3)))
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(AppColor.primaryText)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .frame(width: 72)
            .background(AppColor.control)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityLabel(accessibilityLabel)
    }
}

private enum AppStyle {
    static let radius: CGFloat = 8
    static let smallRadius: CGFloat = 7
    static let twoColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]
}

enum AppColor {
    private static func adaptive(_ light: Double, _ dark: Double) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(white: isDark ? dark : light, alpha: 1)
        })
    }

    static let background = adaptive(0.985, 0.085)
    static let panel = adaptive(0.955, 0.105)
    static let row = adaptive(0.95, 0.13)
    static let control = adaptive(0.915, 0.18)
    static let tableBackground = adaptive(0.95, 0.105)
    static let border = adaptive(0.85, 0.22)
    static let primaryText = adaptive(0.12, 0.95)
    static let secondaryText = adaptive(0.36, 0.70)
    static let tertiaryText = adaptive(0.43, 0.60)
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.36, green: 0.79, blue: 0.64, alpha: 1)
            : NSColor(red: 0.08, green: 0.43, blue: 0.32, alpha: 1)
    })
    static let green = accent
    static let blue = Color(nsColor: .systemBlue)
    static let gold = Color(nsColor: .systemOrange)
    static let rose = Color(nsColor: .systemPink)
}
