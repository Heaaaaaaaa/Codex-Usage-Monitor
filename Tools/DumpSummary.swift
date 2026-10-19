import Foundation

@main
struct DumpSummary {
    @MainActor
    static func main() {
        let suiteName = "CodexUsageMonitorDiagnostics-\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName) ?? .standard
        defer {
            preferences.removePersistentDomain(forName: suiteName)
        }

        let arguments = Array(CommandLine.arguments.dropFirst())
        let cacheURL = arguments.first(where: { !$0.hasPrefix("--") }).map { URL(fileURLWithPath: $0) }
        let store = UsageStore(preferences: preferences, cacheURL: cacheURL)
        store.dateWindow = arguments.contains("--lifetime") ? .lifetime : .sevenDays
        store.loadFromDiskSynchronously()
        if arguments.contains("--json") {
            let result: [String: Any] = [
                "tokens": store.summary.tokens.total,
                "sessions": store.summary.sessionCount,
                "events": store.summary.eventCount,
                "files": store.scanDiagnostics.scannedFileCount,
                "cachedFiles": store.scanDiagnostics.cachedFileCount,
                "parseIssues": store.scanDiagnostics.parseIssueCount,
                "days": store.dailyRows.map { ["date": $0.id, "tokens": $0.tokens.total] as [String: Any] },
                "models": store.modelRows.map { ["model": $0.id, "tokens": $0.tokens.total] as [String: Any] }
            ]
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), let json = String(data: data, encoding: .utf8) { print(json) }
            return
        }
        print(store.diagnosticSummary)
        let unpricedModels = store.unpricedModelNames.isEmpty ? "none" : store.unpricedModelNames.joined(separator: ",")
        print("pricingCoverage=\(store.pricingCoverageDescription) unpricedModels=\(unpricedModels)")
    }
}
