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

        let cacheURL = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0) }
        let store = UsageStore(preferences: preferences, cacheURL: cacheURL)
        store.dateWindow = .sevenDays
        store.loadFromDiskSynchronously()
        print(store.diagnosticSummary)
        let unpricedModels = store.unpricedModelNames.isEmpty ? "none" : store.unpricedModelNames.joined(separator: ",")
        print("pricingCoverage=\(store.pricingCoverageDescription) unpricedModels=\(unpricedModels)")
    }
}
