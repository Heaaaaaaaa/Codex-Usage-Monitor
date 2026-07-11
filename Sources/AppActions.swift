import AppKit
import Foundation
import UniformTypeIdentifiers

enum AppActions {
    static func showAbout() {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info["CFBundleVersion"] as? String ?? "unknown"
        let credits = NSAttributedString(
            string: "Local Codex usage monitor.\nReads your selected Codex log folder only and never sends usage data anywhere."
        )

        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Codex Usage Monitor",
            .applicationVersion: version,
            .version: build,
            .credits: credits
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    static func copySummary(store: UsageStore) {
        copy(store.summaryText())
    }

    static func copyDiagnostics(store: UsageStore, settings: AppSettings) {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info["CFBundleVersion"] as? String ?? "unknown"
        copy(settings.diagnosticReport(store: store, appVersion: version, build: build))
    }

    private static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    static func exportCSV(store: UsageStore) {
        let csv = store.csvString()
        let panel = NSSavePanel()
        panel.title = "Export Codex Usage"
        panel.message = "Save the currently filtered usage events as CSV."
        panel.nameFieldStringValue = "codex-usage-\(filenameDate()).csv"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.commaSeparatedText]

        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else {
                return
            }
            do {
                try csv.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                showAlert(message: "Could not export CSV.", detail: error.localizedDescription)
            }
        }

        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    static func exportSettings(store: UsageStore, settings: AppSettings) {
        let configuration = settings.exportConfiguration(store: store)
        let panel = NSSavePanel()
        panel.title = "Export Codex Usage Settings"
        panel.message = "Save app preferences, budgets, filters, and pricing rates as JSON."
        panel.nameFieldStringValue = "codex-usage-settings-\(filenameDate()).json"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]

        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else {
                return
            }
            do {
                let data = try AppConfiguration.encode(configuration)
                try data.write(to: url, options: [.atomic])
            } catch {
                showAlert(message: "Could not export settings.", detail: error.localizedDescription)
            }
        }

        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    static func importSettings(store: UsageStore, settings: AppSettings) {
        let panel = NSOpenPanel()
        panel.title = "Import Codex Usage Settings"
        panel.message = "Choose a Codex Usage Monitor settings JSON file."
        panel.prompt = "Import"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]

        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else {
                return
            }
            do {
                let data = try Data(contentsOf: url)
                let configuration = try AppConfiguration.decode(from: data)
                try settings.applyConfiguration(configuration, to: store)
            } catch {
                showAlert(message: "Could not import settings.", detail: error.localizedDescription)
            }
        }

        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    static func openCodexFolder(store: UsageStore) {
        NSWorkspace.shared.open(store.codexHomeURL)
    }

    static func openPricingPage() {
        NSWorkspace.shared.open(UsageStore.defaultRateSourceURL)
    }

    static func chooseCodexFolder(store: UsageStore) {
        let panel = NSOpenPanel()
        panel.title = "Choose Codex Log Folder"
        panel.message = "Select the Codex data folder that contains sessions, archived_sessions, and session_index.jsonl."
        panel.prompt = "Use Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = store.codexHomeURL

        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else {
                return
            }
            store.setCodexHome(url)
            store.refresh()
        }

        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    static func resetCodexFolder(store: UsageStore) {
        store.resetCodexHome()
        store.refresh()
    }

    private static func showAlert(message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.runModal()
    }

    private static func filenameDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: Date())
    }
}
