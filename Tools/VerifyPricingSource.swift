import Foundation

@main
private struct VerifyPricingSource {
    static func main() async throws {
        let catalog: PricingCatalog
        if let path = CommandLine.arguments.dropFirst().first {
            catalog = try PricingCatalog.parse(String(contentsOfFile: path, encoding: .utf8))
        } else {
            catalog = try await PricingCatalogClient.fetch()
        }
        guard let rate = catalog.rates.first(where: { $0.model == "gpt-6.1-sol" }),
              rate.inputPerMillion == 2, rate.cachedInputPerMillion == 0.1, rate.outputPerMillion == 10 else {
            throw PricingCatalogError.invalidDocument
        }
        print("Verified official Standard catalog: \(catalog.rates.count) models")
        print("GPT-6.1 Sol: $\(rate.inputPerMillion) input / $\(rate.cachedInputPerMillion) cached / $\(rate.outputPerMillion) output per 1M tokens")
    }
}
