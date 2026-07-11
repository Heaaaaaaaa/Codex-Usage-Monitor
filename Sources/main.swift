import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let launcher = Launcher()
launcher.showInitialWindowIfNeeded()
app.run()
