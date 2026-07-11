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

        let store = UsageStore(preferences: preferences)
        store.dateWindow = .sevenDays
        store.loadFromDiskSynchronously()
        print(store.diagnosticSummary)
        let unpricedModels = store.unpricedModelNames.isEmpty ? "none" : store.unpricedModelNames.joined(separator: ",")
        print("pricingCoverage=\(store.pricingCoverageDescription) unpricedModels=\(unpricedModels)")
    }
}
