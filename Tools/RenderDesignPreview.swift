import AppKit
import SwiftUI

// Render the real SwiftUI view against a synthetic fixture, with no screen or cursor capture.
@main
struct RenderDesignPreview {
    @MainActor
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            fatalError("usage: RenderDesignPreview demo-codex-home output-directory")
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let suite = "dev.codexusage.render.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let store = UsageStore(
            codexHome: URL(fileURLWithPath: CommandLine.arguments[1]),
            preferences: preferences,
            cacheURL: output.appendingPathComponent("preview-cache.json")
        )
        store.setDateWindow(.sevenDays)
        store.refresh()
        let deadline = Date().addingTimeInterval(15)
        while store.isRefreshing && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        guard !store.isRefreshing && !store.dailyRows.isEmpty else {
            fatalError("Synthetic preview fixture did not load")
        }
        let scenes: [(String, ColorScheme, Double, DashboardPage, SettingsPage?)] = [
            ("overview-dark", .dark, 720, .overview, nil),
            ("overview-light", .light, 720, .overview, nil),
            ("overview-compact", .dark, 580, .overview, nil),
            ("activity", .dark, 720, .activity, nil),
            ("breakdown", .dark, 720, .breakdown, nil),
            ("rates-dark", .dark, 720, .overview, .rates),
            ("rates-light", .light, 720, .overview, .rates),
            ("general", .dark, 720, .overview, .general),
            ("budgets", .dark, 720, .overview, .budgets),
            ("diagnostics", .dark, 720, .overview, .diagnostics)
        ]
        for (name, scheme, height, page, settings) in scenes {
            let root = RootView(store: store, appSettings: AppSettings(preferences: preferences), onClose: {}, onQuit: {}, initialPage: page, initialSettingsPage: settings)
                .environment(\.colorScheme, scheme)
            let host = NSHostingView(rootView: root)
            host.frame = NSRect(x: 0, y: 0, width: 540, height: height)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            window.contentView = host
            window.orderFront(nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                fatalError("Unable to allocate native preview bitmap")
            }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                fatalError("Unable to encode native preview")
            }
            try data.write(to: output.appendingPathComponent("\(name).png"))
            if let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) {
                try jpeg.write(to: output.appendingPathComponent("\(name).jpeg"))
            }
            window.orderOut(nil)
            print("Rendered \(name): \(bitmap.pixelsWide)x\(bitmap.pixelsHigh)")
        }
    }
}
