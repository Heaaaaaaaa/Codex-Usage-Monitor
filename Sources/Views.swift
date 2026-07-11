import SwiftUI

extension Notification.Name {
    static let showCodexUsageSettings = Notification.Name("CodexUsageMonitor.showSettings")
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

private enum SettingsPage: String, CaseIterable, Identifiable {
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

struct RootView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var appSettings: AppSettings
    let onClose: () -> Void

    @State private var showingSettings = false
    @State private var selectedSettingsPage: SettingsPage = .general
    @State private var selectedBreakdown: BreakdownKind = .projects
    @State private var confirmingClearCache = false
    @State private var rateDraft: [ModelRate] = []
    @State private var rateDraftBaseline: [ModelRate] = []

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
        .frame(minWidth: 500, minHeight: 620)
        .background(AppColor.background)
        .foregroundStyle(AppColor.primaryText)
        .onAppear {
            store.refreshIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showCodexUsageSettings)) { _ in
            showSettings(.general)
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
                onClose()
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
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                if store.isLoadingSelectedWindow {
                    LoadingUsagePanel(windowTitle: store.dateWindow.title, detail: store.loadMessage)
                    filters
                        .disabled(true)
                } else {
                    summaryHero
                    if store.healthStatus.isVisible {
                        healthNotice
                    }
                    if appSettings.hasBudgetLimits {
                        budgetStatusSection
                    }
                    filters
                    TrendPanel(
                        rows: store.dailyRows,
                        metric: Binding(get: {
                            appSettings.trendMetric
                        }, set: { metric in
                            appSettings.setTrendMetric(metric)
                        })
                    )
                    recentActivity
                    limits
                    tokenDetails
                    costDetails
                    breakdown
                }
            }
            .padding(18)
        }
    }

    private var settingsContent: some View {
        VStack(spacing: 0) {
            Picker("Settings section", selection: $selectedSettingsPage) {
                ForEach(SettingsPage.allCases) { page in
                    Text(page.rawValue).tag(page)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Settings section")
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 12)

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
                .padding(.horizontal, 18)
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
                    .font(.system(size: 23, weight: .semibold))
                Text(showingSettings ? selectedSettingsPage.detail : headerDetail)
                    .font(.system(size: 12, weight: .medium))
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
                HeaderButton(symbol: "slider.horizontal.3", help: "Settings") {
                    showSettings(.general)
                }
            }
            HeaderButton(symbol: "xmark", help: "Close") {
                closePanel()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var headerDetail: String {
        if store.isRefreshing {
            return store.loadMessage
        }
        let chatLabel = store.summary.sessionCount == 1 ? "chat" : "chats"
        let eventLabel = store.summary.eventCount == 1 ? "event" : "events"
        return "\(store.summary.sessionCount) \(chatLabel) / \(store.summary.eventCount) \(eventLabel) / \(store.lastRefreshText)"
    }

    private var summaryHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(scopeTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColor.accent)
                        .lineLimit(1)
                    Text(store.dateWindow.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColor.secondaryText)
                }
                Spacer()
                Text(store.codexHomeDisplayPath)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppColor.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 180)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppColor.control)
                    .clipShape(RoundedRectangle(cornerRadius: AppStyle.smallRadius, style: .continuous))
                    .help(store.codexHomeURL.path)
            }

            HStack(alignment: .top, spacing: 14) {
                PrimaryFigure(
                    title: "Tokens",
                    value: UsageStore.compactNumber(store.summary.tokens.total),
                    caption: "\(store.summary.eventCount) token events"
                )
                Divider().background(AppColor.border)
                PrimaryFigure(
                    title: "Est. cost",
                    value: UsageStore.currency(store.summary.cost),
                    caption: costCaption
                )
                .help("\(UsageStore.defaultRateSourceSummary). \(UsageStore.defaultRateLimitations)")
            }

            if store.comparison.isVisible {
                ComparisonStrip(comparison: store.comparison)
            }

            LazyVGrid(columns: AppStyle.twoColumns, spacing: 8) {
                TokenChip(title: "Input", value: UsageStore.compactNumber(store.summary.tokens.input), color: AppColor.blue)
                TokenChip(title: "Cached", value: UsageStore.compactNumber(store.summary.tokens.cachedInput), color: AppColor.gold)
                TokenChip(title: "Output", value: UsageStore.compactNumber(store.summary.tokens.output), color: AppColor.rose)
                TokenChip(title: "Reasoning", value: UsageStore.compactNumber(store.summary.tokens.reasoningOutput), color: AppColor.green)
                TokenChip(title: "Avg / 1M", value: UsageStore.currency(store.averageCostPerMillion), color: AppColor.accent)
                TokenChip(title: "30d pace", value: UsageStore.currency(store.thirtyDayCostPace), color: AppColor.green)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: AppStyle.radius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AppColor.heroTop, AppColor.heroBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppStyle.radius, style: .continuous)
                .stroke(AppColor.heroBorder, lineWidth: 1)
        )
    }

    private var filters: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Filters")
                Picker("Window", selection: Binding(get: {
                    store.dateWindow
                }, set: { newValue in
                    store.setDateWindow(newValue)
                })) {
                    ForEach(DateWindow.allCases) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                HStack(spacing: 10) {
                    Picker("Scope", selection: Binding(get: {
                        store.scopeMode
                    }, set: { newValue in
                        store.setScopeMode(newValue)
                    })) {
                        ForEach(ScopeMode.allCases) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if store.scopeMode != .all {
                        Picker("Target", selection: Binding(get: {
                            store.selectedScopeID
                        }, set: { newValue in
                            store.setSelectedScope(newValue)
                        })) {
                            Text("Any").tag("")
                            ForEach(store.scopeOptions) { row in
                                Text(row.label).tag(row.id)
                            }
                        }
                        .frame(width: 180)
                    }
                }
            }
        }
    }

    private var limits: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            limitsContent(now: context.date)
        }
    }

    private func limitsContent(now: Date) -> some View {
        let snapshot = store.latestLimits
        let primaryDisplay = UsageStore.windowLimitDisplay(snapshot?.primary, snapshotSeenAt: snapshot?.seenAt, now: now)
        let secondaryDisplay = UsageStore.windowLimitDisplay(snapshot?.secondary, snapshotSeenAt: snapshot?.seenAt, now: now)
        let resetDisplay = UsageStore.resetCreditDisplay(snapshot, now: now)

        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Limits")
            HStack(spacing: 8) {
                LimitTile(
                    symbol: "clock",
                    title: "5-hour",
                    value: primaryDisplay.value,
                    detail: primaryDisplay.detail,
                    color: primaryDisplay.isExpired ? AppColor.tertiaryText : AppColor.accent
                )
                LimitTile(
                    symbol: "calendar",
                    title: "Weekly",
                    value: secondaryDisplay.value,
                    detail: secondaryDisplay.detail,
                    color: secondaryDisplay.isExpired ? AppColor.tertiaryText : AppColor.green
                )
                LimitTile(
                    symbol: "plus",
                    title: "Resets",
                    value: resetDisplay.value,
                    detail: resetDisplay.detail,
                    color: resetDisplay.isExpired ? AppColor.tertiaryText : AppColor.gold
                )
            }
            if let credits = snapshot?.resetCredits, !credits.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Reset Credit Expiry")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColor.secondaryText)
                        Spacer()
                        Text("\(credits.count) reported")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppColor.tertiaryText)
                    }
                    ForEach(credits.prefix(4)) { credit in
                        ResetCreditRowView(credit: credit, now: now)
                    }
                }
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

    private var tokenDetails: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Token Mix")
                StatRow(symbol: "arrow.down.left", color: AppColor.blue, label: "Input tokens", value: UsageStore.compactNumber(store.summary.tokens.input))
                StatRow(symbol: "bolt.horizontal", color: AppColor.gold, label: "Cached input", value: UsageStore.compactNumber(store.summary.tokens.cachedInput))
                StatRow(symbol: "arrow.up.right", color: AppColor.rose, label: "Output tokens", value: UsageStore.compactNumber(store.summary.tokens.output))
                StatRow(symbol: "sparkles", color: AppColor.green, label: "Reasoning tokens", value: UsageStore.compactNumber(store.summary.tokens.reasoningOutput))
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
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(AppColor.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

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
                .padding(12)
                .background(AppColor.row)
                .clipShape(RoundedRectangle(cornerRadius: AppStyle.smallRadius, style: .continuous))

                HStack(spacing: 11) {
                    Image(systemName: "power")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(AppColor.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

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
                .padding(12)
                .background(AppColor.row)
                .clipShape(RoundedRectangle(cornerRadius: AppStyle.smallRadius, style: .continuous))

                HStack(spacing: 11) {
                    Image(systemName: "menubar.rectangle")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(AppColor.green)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show window on launch")
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
                    .accessibilityLabel("Show window on launch")
                }
                .padding(12)
                .background(AppColor.row)
                .clipShape(RoundedRectangle(cornerRadius: AppStyle.smallRadius, style: .continuous))

                HStack(spacing: 11) {
                    Image(systemName: "textformat.size")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(AppColor.gold)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

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
                .padding(12)
                .background(AppColor.row)
                .clipShape(RoundedRectangle(cornerRadius: AppStyle.smallRadius, style: .continuous))

                HStack(spacing: 11) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(AppColor.rose)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

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
                .padding(12)
                .background(AppColor.row)
                .clipShape(RoundedRectangle(cornerRadius: AppStyle.smallRadius, style: .continuous))

                HStack(spacing: 11) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(AppColor.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

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
                .padding(12)
                .background(AppColor.row)
                .clipShape(RoundedRectangle(cornerRadius: AppStyle.smallRadius, style: .continuous))
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
                        Text(UsageStore.defaultRateSourceDetail)
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
                        rateDraft = UsageStore.defaultRates
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
                        Text("Model").frame(width: 144, alignment: .leading)
                        Text("Input").frame(width: 72, alignment: .trailing)
                        Text("Cached").frame(width: 72, alignment: .trailing)
                        Text("Output").frame(width: 72, alignment: .trailing)
                        Text("").frame(width: 26)
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

    private func closePanel() {
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

    init(padding: CGFloat = 14, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(AppColor.panel)
            .overlay(
                RoundedRectangle(cornerRadius: AppStyle.radius, style: .continuous)
                    .stroke(AppColor.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppStyle.radius, style: .continuous))
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
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppColor.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(caption)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColor.tertiaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ComparisonStrip: View {
    let comparison: UsageComparison

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("vs \(comparison.label)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColor.tertiaryText)
                    .lineLimit(1)
                Text(previousText)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppColor.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ComparisonMetric(
                title: "Tokens",
                value: UsageStore.signedCompactNumber(comparison.tokenDelta),
                detail: UsageStore.signedPercent(comparison.tokenDeltaPercent),
                color: comparison.tokenDelta >= 0 ? AppColor.gold : AppColor.green
            )

            ComparisonMetric(
                title: "Est. cost",
                value: UsageStore.signedCurrency(comparison.costDelta),
                detail: UsageStore.signedPercent(comparison.costDeltaPercent),
                color: comparison.costDelta >= 0 ? AppColor.gold : AppColor.green
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(AppColor.heroInset)
        .clipShape(RoundedRectangle(cornerRadius: AppStyle.smallRadius, style: .continuous))
        .help(helpText)
    }

    private var previousText: String {
        guard comparison.hasPreviousActivity else {
            return "No previous usage"
        }
        return "\(UsageStore.compactNumber(comparison.previousTokens)) / \(UsageStore.currency(comparison.previousCost))"
    }

    private var helpText: String {
        "Previous \(comparison.label): \(UsageStore.compactNumber(comparison.previousTokens)) tokens, \(UsageStore.currency(comparison.previousCost))"
    }
}

private struct ComparisonMetric: View {
    let title: String
    let value: String
    let detail: String
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppColor.tertiaryText)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(value)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppColor.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                    Text(detail)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
        .frame(width: 112, alignment: .leading)
    }
}

private struct TokenChip: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(width: 6, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColor.tertiaryText)
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppColor.primaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppColor.heroInset)
        .clipShape(RoundedRectangle(cornerRadius: AppStyle.smallRadius, style: .continuous))
    }
}

private struct TrendPanel: View {
    let rows: [DailyUsageRow]
    @Binding var metric: TrendMetric

    private var maxValue: Double {
        let maximum = rows.map(value(for:)).max() ?? 0
        return maximum > 0 ? maximum : 1
    }

    private var countText: String {
        guard !rows.isEmpty else { return "No events" }
        let prefix = rows.count > 1 ? "Last " : ""
        return "\(prefix)\(rows.count) \(rows.count == 1 ? "day" : "days")"
    }

    private var totalText: String {
        switch metric {
        case .tokens:
            return UsageStore.compactNumber(rows.reduce(0) { $0 + $1.tokens.total })
        case .cost:
            return UsageStore.currency(rows.reduce(0) { $0 + $1.cost })
        }
    }

    private func value(for row: DailyUsageRow) -> Double {
        switch metric {
        case .tokens: return Double(row.tokens.total)
        case .cost: return row.cost
        }
    }

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        SectionTitle("Daily Trend")
                        Text("\(countText) / \(totalText)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppColor.tertiaryText)
                            .lineLimit(1)
                    }
                    Spacer()
                    Picker("Trend metric", selection: $metric) {
                        ForEach(TrendMetric.allCases) { value in
                            Text(value.displayTitle).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 132)
                    .accessibilityLabel("Trend metric")
                }

                if rows.isEmpty {
                    EmptyState(text: "No daily activity for this filter")
                } else {
                    HStack(alignment: .bottom, spacing: 7) {
                        ForEach(rows) { row in
                            DailyBar(row: row, maxValue: maxValue, metric: metric)
                        }
                    }
                    .frame(height: 98)
                    .padding(.top, 2)
                }
            }
        }
    }
}

private struct DailyBar: View {
    let row: DailyUsageRow
    let maxValue: Double
    let metric: TrendMetric

    private var value: Double {
        switch metric {
        case .tokens: return Double(row.tokens.total)
        case .cost: return row.cost
        }
    }

    private var color: Color {
        metric == .tokens ? AppColor.accent : AppColor.green
    }

    private var height: CGFloat {
        guard value > 0 else {
            return 2
        }
        let ratio = CGFloat(value / maxValue)
        return max(8, 58 * ratio)
    }

    private var accessibilityValue: String {
        switch metric {
        case .tokens:
            return "\(UsageStore.compactNumber(row.tokens.total)) tokens"
        case .cost:
            return "\(UsageStore.currency(row.cost)) estimated cost"
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(value > 0 ? color : AppColor.control)
                .frame(height: height)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
                .help("\(row.label): \(UsageStore.compactNumber(row.tokens.total)) tokens, \(UsageStore.currency(row.cost))")
            Text(row.label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(AppColor.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.label)
        .accessibilityValue(accessibilityValue)
    }
}

private struct LimitTile: View {
    let symbol: String
    let title: String
    let value: String
    let detail: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(color)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColor.secondaryText)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppColor.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(AppColor.panel)
        .overlay(
            RoundedRectangle(cornerRadius: AppStyle.radius, style: .continuous)
                .stroke(AppColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppStyle.radius, style: .continuous))
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
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
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
            .frame(width: 144)
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
    static let background = Color(red: 0.058, green: 0.066, blue: 0.078)
    static let panel = Color(red: 0.095, green: 0.112, blue: 0.135)
    static let row = Color(red: 0.122, green: 0.142, blue: 0.172)
    static let control = Color(red: 0.145, green: 0.166, blue: 0.202)
    static let tableBackground = Color(red: 0.075, green: 0.088, blue: 0.108)
    static let border = Color.white.opacity(0.08)
    static let heroTop = Color(red: 0.155, green: 0.176, blue: 0.225)
    static let heroBottom = Color(red: 0.088, green: 0.105, blue: 0.132)
    static let heroInset = Color.white.opacity(0.055)
    static let heroBorder = Color.white.opacity(0.11)
    static let primaryText = Color(red: 0.92, green: 0.94, blue: 0.98)
    static let secondaryText = Color(red: 0.66, green: 0.70, blue: 0.77)
    static let tertiaryText = Color(red: 0.48, green: 0.53, blue: 0.60)
    static let accent = Color(red: 0.46, green: 0.54, blue: 0.92)
    static let green = Color(red: 0.23, green: 0.74, blue: 0.52)
    static let blue = Color(red: 0.32, green: 0.57, blue: 0.90)
    static let gold = Color(red: 0.88, green: 0.61, blue: 0.25)
    static let rose = Color(red: 0.86, green: 0.35, blue: 0.48)
}
