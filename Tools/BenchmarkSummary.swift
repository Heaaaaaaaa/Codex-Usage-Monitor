import Foundation

@main
struct BenchmarkSummary {
    @MainActor
    static func main() {
        let count = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 30_000
        guard (1...1_000_000).contains(count) else {
            fatalError("Event count must be between 1 and 1000000")
        }
        let suite = "CodexUsageBenchmark-\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let store = UsageStore(preferences: preferences)
        let now = Date()
        let models = ["gpt-6-astra", "openai/gpt-5.6-sol-2026-09-10", "gpt-5.6-terra", "gpt-5.6-luna", "unpriced-model"]
        store.entries = (0..<count).map { index in
            UsageEntry(
                id: "event-\(index)",
                timestamp: now.addingTimeInterval(-Double(index % 45) * 86_400 - Double(index % 600)),
                sessionID: "chat-\(index % 512)",
                chatTitle: "Benchmark chat \(index % 512)",
                projectPath: "/synthetic/project-\(index % 64)",
                model: models[index % models.count],
                tokens: UsageTokens(input: 1_000, cachedInput: 700, output: 100, reasoningOutput: 20, total: 1_100),
                sourceFile: "synthetic.jsonl:\(index)"
            )
        }
        store.dateWindow = .lifetime
        store.recompute()
        var timings: [Double] = []
        for _ in 0..<5 {
            let start = ProcessInfo.processInfo.systemUptime
            store.recompute()
            timings.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
        }
        timings.sort()
        print("events=\(count) median_ms=\(String(format: "%.2f", timings[timings.count / 2])) tokens=\(store.summary.tokens.total) cost=\(String(format: "%.6f", store.summary.cost))")
    }
}
