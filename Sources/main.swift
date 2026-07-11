import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let launcher = Launcher()
    launcher.showInitialWindowIfNeeded()
    app.run()
}
