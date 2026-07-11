import AppKit
import Combine
import Darwin
import SwiftUI
import UserNotifications

final class Launcher: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSWindowDelegate {
    private let store = UsageStore()
    private let appSettings = AppSettings()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let logWatcher = CodexLogWatcher()
    private let budgetNotifier = BudgetNotificationController()
    private var refreshTimer: Timer?
    private var window: NSPanel!
    private var cancellables: Set<AnyCancellable> = []

    override init() {
        super.init()
        NSApp.delegate = self
        configureWindow()
        configureStatusItem()
        configureMainMenu()

        store.statusChanged = { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateStatusTitle()
                self?.evaluateBudgetNotification()
            }
        }
        store.codexHomeChanged = { [weak self] _ in
            self?.restartLogWatcher()
        }
        logWatcher.onChange = { [weak self] in
            self?.logFilesDidChange()
        }
        appSettings.$menuBarDisplayMode
            .dropFirst()
            .sink { [weak self] _ in
                self?.updateStatusTitle()
            }
            .store(in: &cancellables)
        appSettings.$tokenBudgetLimit
            .dropFirst()
            .sink { [weak self] _ in
                self?.updateStatusTitle()
                self?.evaluateBudgetNotification()
            }
            .store(in: &cancellables)
        appSettings.$costBudgetLimit
            .dropFirst()
            .sink { [weak self] _ in
                self?.updateStatusTitle()
                self?.evaluateBudgetNotification()
            }
            .store(in: &cancellables)
        appSettings.$budgetNotificationsEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                if enabled {
                    self?.budgetNotifier.requestAuthorizationIfNeeded()
                }
                self?.evaluateBudgetNotification()
            }
            .store(in: &cancellables)
        appSettings.$autoRefreshInterval
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleRefreshTimer()
                self?.restartLogWatcher()
            }
            .store(in: &cancellables)

        store.refresh()
        scheduleRefreshTimer()
        restartLogWatcher()
    }

    deinit {
        refreshTimer?.invalidate()
        logWatcher.stop()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func show() {
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(window.contentViewController)
    }

    func showInitialWindowIfNeeded() {
        if appSettings.showWindowOnLaunch {
            show()
        }
    }

    private func configureWindow() {
        let root = RootView(store: store, appSettings: appSettings) { [weak self] in
            self?.hideWindow()
        }
        let controller = UsageHostingController(rootView: root, store: store)
        window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 710),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        window.title = "Codex Usage Monitor"
        window.contentViewController = controller
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 500, height: 620)
        window.hidesOnDeactivate = true
        window.isFloatingPanel = false
        window.level = .normal
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeApplicationDidChange(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }
        button.image = NSImage(systemSymbolName: "chart.bar.xaxis", accessibilityDescription: "Codex Usage")
        button.image?.isTemplate = true
        button.imagePosition = .imageLeading
        button.title = "CX"
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateStatusTitle()
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()

        appMenu.addItem(NSMenuItem(title: "About Codex Usage Monitor", action: #selector(showAbout), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Show Codex Usage", action: #selector(showWindow), keyEquivalent: "0"))
        appMenu.addItem(NSMenuItem(title: "Refresh", action: #selector(refreshUsage), keyEquivalent: "r"))
        appMenu.addItem(makeAutoRefreshMenuItem())
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Export CSV...", action: #selector(exportCSV), keyEquivalent: "e"))
        appMenu.addItem(NSMenuItem(title: "Copy Summary", action: #selector(copySummary), keyEquivalent: "c"))
        appMenu.addItem(NSMenuItem(title: "Copy Diagnostics", action: #selector(copyDiagnostics), keyEquivalent: "d"))
        appMenu.addItem(NSMenuItem(title: "Open Codex Logs", action: #selector(openCodexLogs), keyEquivalent: "l"))
        appMenu.addItem(NSMenuItem(title: "Choose Codex Log Folder...", action: #selector(chooseCodexLogs), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem(title: "Import Settings...", action: #selector(importSettings), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem(title: "Export Settings...", action: #selector(exportSettings), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem(title: "Show Window on Launch", action: #selector(toggleShowWindowOnLaunch), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem(title: "Budget Notifications", action: #selector(toggleBudgetNotifications), keyEquivalent: ""))
        appMenu.addItem(makeDisplayModeMenuItem())
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Codex Usage Monitor", action: #selector(quit), keyEquivalent: "q"))

        appMenu.items.forEach { $0.target = self }
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        let snapshotItem = makeSnapshotMenuItem()
        let showItem = NSMenuItem(title: "Show Codex Usage", action: #selector(showWindow), keyEquivalent: "")
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: "")
        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshUsage), keyEquivalent: "")
        let autoRefreshItem = makeAutoRefreshMenuItem()
        let exportItem = NSMenuItem(title: "Export CSV...", action: #selector(exportCSV), keyEquivalent: "")
        let copyItem = NSMenuItem(title: "Copy Summary", action: #selector(copySummary), keyEquivalent: "")
        let diagnosticsItem = NSMenuItem(title: "Copy Diagnostics", action: #selector(copyDiagnostics), keyEquivalent: "")
        let logsItem = NSMenuItem(title: "Open Codex Logs", action: #selector(openCodexLogs), keyEquivalent: "")
        let chooseLogsItem = NSMenuItem(title: "Choose Codex Log Folder...", action: #selector(chooseCodexLogs), keyEquivalent: "")
        let importSettingsItem = NSMenuItem(title: "Import Settings...", action: #selector(importSettings), keyEquivalent: "")
        let exportSettingsItem = NSMenuItem(title: "Export Settings...", action: #selector(exportSettings), keyEquivalent: "")
        let aboutItem = NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: "")
        let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        let showWindowOnLaunchItem = NSMenuItem(title: "Show Window on Launch", action: #selector(toggleShowWindowOnLaunch), keyEquivalent: "")
        let budgetNotificationsItem = NSMenuItem(title: "Budget Notifications", action: #selector(toggleBudgetNotifications), keyEquivalent: "")
        let displayModeItem = makeDisplayModeMenuItem()
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "")

        [showItem, settingsItem, refreshItem, exportItem, copyItem, diagnosticsItem, logsItem, chooseLogsItem, importSettingsItem, exportSettingsItem, aboutItem, launchAtLoginItem, showWindowOnLaunchItem, budgetNotificationsItem, quitItem].forEach { $0.target = self }
        menu.addItem(snapshotItem)
        menu.addItem(.separator())
        menu.addItem(showItem)
        menu.addItem(settingsItem)
        menu.addItem(refreshItem)
        menu.addItem(autoRefreshItem)
        menu.addItem(.separator())
        menu.addItem(exportItem)
        menu.addItem(copyItem)
        menu.addItem(diagnosticsItem)
        menu.addItem(logsItem)
        menu.addItem(chooseLogsItem)
        menu.addItem(importSettingsItem)
        menu.addItem(exportSettingsItem)
        menu.addItem(.separator())
        menu.addItem(launchAtLoginItem)
        menu.addItem(showWindowOnLaunchItem)
        menu.addItem(budgetNotificationsItem)
        menu.addItem(displayModeItem)
        menu.addItem(.separator())
        menu.addItem(aboutItem)
        menu.addItem(quitItem)
        return menu
    }

    private func makeSnapshotMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Usage Snapshot", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "chart.bar.xaxis", accessibilityDescription: "Usage Snapshot")

        let submenu = NSMenu()
        for line in statusSnapshotLines() {
            let lineItem = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            lineItem.isEnabled = false
            submenu.addItem(lineItem)
        }
        item.submenu = submenu
        return item
    }

    private func makeDisplayModeMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Menu Bar Shows", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.addItem(NSMenuItem(title: "Tokens", action: #selector(showTokensInMenuBar), keyEquivalent: ""))
        submenu.addItem(NSMenuItem(title: "Estimated Cost", action: #selector(showCostInMenuBar), keyEquivalent: ""))
        submenu.addItem(NSMenuItem(title: "Tokens + Est. Cost", action: #selector(showTokensAndCostInMenuBar), keyEquivalent: ""))
        submenu.items.forEach { $0.target = self }
        item.submenu = submenu
        return item
    }

    private func makeAutoRefreshMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Auto Refresh", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.addItem(NSMenuItem(title: AutoRefreshInterval.off.menuTitle, action: #selector(setAutoRefreshOff), keyEquivalent: ""))
        submenu.addItem(NSMenuItem(title: AutoRefreshInterval.oneMinute.menuTitle, action: #selector(setAutoRefreshOneMinute), keyEquivalent: ""))
        submenu.addItem(NSMenuItem(title: AutoRefreshInterval.fiveMinutes.menuTitle, action: #selector(setAutoRefreshFiveMinutes), keyEquivalent: ""))
        submenu.addItem(NSMenuItem(title: AutoRefreshInterval.fifteenMinutes.menuTitle, action: #selector(setAutoRefreshFifteenMinutes), keyEquivalent: ""))
        submenu.items.forEach { $0.target = self }
        item.submenu = submenu
        return item
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent, event.type == .rightMouseUp else {
            toggleWindow()
            return
        }
        statusItem.menu = makeStatusMenu()
        sender.performClick(nil)
        statusItem.menu = nil
    }

    private func toggleWindow() {
        if window.isVisible {
            hideWindow()
        } else {
            show()
        }
    }

    private func hideWindow() {
        window.orderOut(nil)
    }

    private func autoHideWindowIfNeeded() {
        guard window.isVisible,
              window.attachedSheet == nil,
              NSApp.modalWindow == nil else {
            return
        }
        hideWindow()
    }

    private func scheduleAutoHideWindowIfNeeded() {
        DispatchQueue.main.async { [weak self] in
            self?.autoHideWindowIfNeeded()
        }
    }

    private func updateStatusTitle() {
        guard let button = statusItem.button else {
            return
        }
        button.title = appSettings.menuBarTitle(summary: store.summary, pricingCoverage: store.pricingCoverage)
        button.toolTip = statusSnapshotLines().joined(separator: "\n")
    }

    private func statusSnapshotLines() -> [String] {
        appSettings.statusMenuSnapshotLines(
            summary: store.summary,
            pricingCoverage: store.pricingCoverage,
            windowTitle: store.dateWindow.title,
            scopeDescription: store.activeScopeDescription,
            healthStatus: store.healthStatus
        )
    }

    private func scheduleRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil

        guard let interval = appSettings.autoRefreshInterval.seconds else {
            return
        }

        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.store.refreshInBackgroundIfIdle()
        }
        timer.tolerance = max(1, interval * 0.10)
        refreshTimer = timer
    }

    private func restartLogWatcher() {
        guard appSettings.autoRefreshInterval.seconds != nil else {
            logWatcher.stop()
            return
        }
        logWatcher.start(codexHome: store.codexHomeURL)
    }

    private func logFilesDidChange() {
        guard store.refreshInBackgroundIfIdle() else {
            return
        }
        restartLogWatcher()
    }

    private func evaluateBudgetNotification() {
        budgetNotifier.evaluate(summary: store.summary, settings: appSettings)
    }

    @objc private func showWindow() {
        show()
    }

    @objc private func showSettings() {
        show()
        NotificationCenter.default.post(name: .showCodexUsageSettings, object: nil)
    }

    @objc private func refreshUsage() {
        store.refresh()
    }

    @objc private func exportCSV() {
        show()
        AppActions.exportCSV(store: store)
    }

    @objc private func copySummary() {
        AppActions.copySummary(store: store)
    }

    @objc private func copyDiagnostics() {
        AppActions.copyDiagnostics(store: store, settings: appSettings)
    }

    @objc private func openCodexLogs() {
        AppActions.openCodexFolder(store: store)
    }

    @objc private func chooseCodexLogs() {
        show()
        AppActions.chooseCodexFolder(store: store)
    }

    @objc private func importSettings() {
        show()
        AppActions.importSettings(store: store, settings: appSettings)
    }

    @objc private func exportSettings() {
        show()
        AppActions.exportSettings(store: store, settings: appSettings)
    }

    @objc private func showAbout() {
        AppActions.showAbout()
    }

    @objc private func toggleLaunchAtLogin() {
        appSettings.toggleLaunchAtLogin()
    }

    @objc private func toggleShowWindowOnLaunch() {
        appSettings.setShowWindowOnLaunch(!appSettings.showWindowOnLaunch)
    }

    @objc private func toggleBudgetNotifications() {
        appSettings.setBudgetNotificationsEnabled(!appSettings.budgetNotificationsEnabled)
    }

    @objc private func showTokensInMenuBar() {
        appSettings.setMenuBarDisplayMode(.tokens)
    }

    @objc private func showCostInMenuBar() {
        appSettings.setMenuBarDisplayMode(.cost)
    }

    @objc private func showTokensAndCostInMenuBar() {
        appSettings.setMenuBarDisplayMode(.tokensAndCost)
    }

    @objc private func setAutoRefreshOff() {
        appSettings.setAutoRefreshInterval(.off)
    }

    @objc private func setAutoRefreshOneMinute() {
        appSettings.setAutoRefreshInterval(.oneMinute)
    }

    @objc private func setAutoRefreshFiveMinutes() {
        appSettings.setAutoRefreshInterval(.fiveMinutes)
    }

    @objc private func setAutoRefreshFifteenMinutes() {
        appSettings.setAutoRefreshInterval(.fifteenMinutes)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func activeApplicationDidChange(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return
        }
        autoHideWindowIfNeeded()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        show()
        return false
    }

    func applicationDidResignActive(_ notification: Notification) {
        scheduleAutoHideWindowIfNeeded()
    }

    func windowDidResignKey(_ notification: Notification) {
        scheduleAutoHideWindowIfNeeded()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hideWindow()
        return false
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleLaunchAtLogin) {
            appSettings.refreshLaunchAtLoginStatus()
            menuItem.state = appSettings.launchAtLoginEnabled ? .on : .off
            return appSettings.launchAtLoginCanToggle
        }

        if menuItem.action == #selector(toggleShowWindowOnLaunch) {
            menuItem.state = appSettings.showWindowOnLaunch ? .on : .off
            return true
        }

        if menuItem.action == #selector(toggleBudgetNotifications) {
            menuItem.state = appSettings.budgetNotificationsEnabled ? .on : .off
            return true
        }

        switch menuItem.action {
        case #selector(showTokensInMenuBar):
            menuItem.state = appSettings.menuBarDisplayMode == .tokens ? .on : .off
        case #selector(showCostInMenuBar):
            menuItem.state = appSettings.menuBarDisplayMode == .cost ? .on : .off
        case #selector(showTokensAndCostInMenuBar):
            menuItem.state = appSettings.menuBarDisplayMode == .tokensAndCost ? .on : .off
        case #selector(setAutoRefreshOff):
            menuItem.state = appSettings.autoRefreshInterval == .off ? .on : .off
        case #selector(setAutoRefreshOneMinute):
            menuItem.state = appSettings.autoRefreshInterval == .oneMinute ? .on : .off
        case #selector(setAutoRefreshFiveMinutes):
            menuItem.state = appSettings.autoRefreshInterval == .fiveMinutes ? .on : .off
        case #selector(setAutoRefreshFifteenMinutes):
            menuItem.state = appSettings.autoRefreshInterval == .fifteenMinutes ? .on : .off
        default:
            break
        }

        return true
    }
}

private final class BudgetNotificationController: NSObject, UNUserNotificationCenterDelegate {
    private var lastAlertKey: String?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else {
                return
            }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    func evaluate(summary: UsageSummary, settings: AppSettings) {
        guard settings.budgetNotificationsEnabled else {
            lastAlertKey = nil
            return
        }

        let alert = settings.budgetAlert(summary: summary)
        guard alert.isVisible else {
            lastAlertKey = nil
            return
        }

        let key = "\(alert.title)|\(alert.detail)"
        guard key != lastAlertKey else {
            return
        }
        lastAlertKey = key
        deliver(alert)
    }

    private func deliver(_ alert: BudgetAlert) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                self.post(alert, center: center)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted {
                        self.post(alert, center: center)
                    }
                }
            case .denied:
                break
            @unknown default:
                break
            }
        }
    }

    private func post(_ alert: BudgetAlert, center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = alert.level == .exceeded ? "Codex usage budget exceeded" : "Codex usage budget near limit"
        content.body = alert.detail
        content.sound = .default
        content.threadIdentifier = "codex-usage-budget"

        let request = UNNotificationRequest(
            identifier: "codex-usage-budget-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

private final class CodexLogWatcher {
    var onChange: (() -> Void)?

    private let queue = DispatchQueue(label: "CodexUsageMonitor.LogWatcher")
    private var sources: [DispatchSourceFileSystemObject] = []
    private var pendingChange: DispatchWorkItem?

    deinit {
        stop()
    }

    func start(codexHome: URL) {
        stop()

        let watchedRoots = [
            codexHome,
            codexHome.appendingPathComponent("sessions"),
            codexHome.appendingPathComponent("archived_sessions"),
            codexHome.appendingPathComponent("session_index.jsonl")
        ]
        let candidates = watchedRoots + recentSessionLogFiles(codexHome: codexHome)

        for url in candidates {
            guard FileManager.default.fileExists(atPath: url.path) else {
                continue
            }
            watch(url)
        }
    }

    func stop() {
        pendingChange?.cancel()
        pendingChange = nil
        sources.forEach { $0.cancel() }
        sources.removeAll()
    }

    private func recentSessionLogFiles(codexHome: URL) -> [URL] {
        let folders = [
            codexHome.appendingPathComponent("sessions"),
            codexHome.appendingPathComponent("archived_sessions")
        ]
        var files: [(url: URL, modifiedAt: Date)] = []

        for folder in folders {
            guard let enumerator = FileManager.default.enumerator(
                at: folder,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                files.append((url, modifiedAt))
            }
        }

        return files
            .sorted { lhs, rhs in
                if lhs.modifiedAt == rhs.modifiedAt { return lhs.url.path > rhs.url.path }
                return lhs.modifiedAt > rhs.modifiedAt
            }
            .prefix(Self.maxWatchedSessionFiles)
            .map(\.url)
    }

    private func watch(_ url: URL) {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .link, .rename, .delete, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.scheduleChange()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        sources.append(source)
    }

    private func scheduleChange() {
        pendingChange?.cancel()
        let work = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async {
                self?.onChange?()
            }
        }
        pendingChange = work
        queue.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private static let maxWatchedSessionFiles = 256
}
