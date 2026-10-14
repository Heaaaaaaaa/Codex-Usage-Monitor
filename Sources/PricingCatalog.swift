import Foundation

enum PricingCatalogError: Error {
    case invalidDocument
    case invalidResponse
    case tooLarge
}

struct PricingCatalog: Codable {
    let rates: [ModelRate]
    let checkedAt: Date

    // Only the explicitly labeled Standard short-context table is eligible.
    // Other tiers, modalities, and units must never silently become token rates.
    static func parse(_ document: String, checkedAt: Date = Date()) throws -> PricingCatalog {
        let lines = document.components(separatedBy: .newlines)
        guard lines.contains(where: { $0.trimmingCharacters(in: .whitespaces) == "Prices per 1M tokens." }),
              let heading = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "### Standard pricing data" }) else {
            throw PricingCatalogError.invalidDocument
        }
        let expected = ["Model", "Short context input", "Short context cached input", "Short context cache writes", "Short context output", "Long context input", "Long context cached input", "Long context cache writes", "Long context output"]
        var foundHeader = false
        var rates: [ModelRate] = []
        var models = Set<String>()
        for line in lines.dropFirst(heading + 1) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.hasPrefix("|") {
                if foundHeader { break }
                if trimmed.hasPrefix("#") { throw PricingCatalogError.invalidDocument }
                continue
            }
            let cells = trimmed.split(separator: "|", omittingEmptySubsequences: false).dropFirst().dropLast().map { $0.trimmingCharacters(in: .whitespaces) }
            if !foundHeader {
                guard cells == expected else { throw PricingCatalogError.invalidDocument }
                foundHeader = true
                continue
            }
            if cells.allSatisfy({ $0 == "---" }) { continue }
            guard cells.count == expected.count else { throw PricingCatalogError.invalidDocument }
            let model = cells[0].replacingOccurrences(of: " (<272K context length)", with: "")
            guard !model.isEmpty, model.count <= 100,
                  model.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.").contains($0) }),
                  models.insert(model).inserted,
                  let input = price(cells[1]), let cached = price(cells[2], allowUnavailable: true),
                  let output = price(cells[4]) else { throw PricingCatalogError.invalidDocument }
            rates.append(ModelRate(model: model, inputPerMillion: input, cachedInputPerMillion: cached, outputPerMillion: output))
        }
        guard foundHeader, !rates.isEmpty else { throw PricingCatalogError.invalidDocument }
        return PricingCatalog(rates: rates, checkedAt: checkedAt)
    }

    private static func price(_ value: String, allowUnavailable: Bool = false) -> Double? {
        if allowUnavailable && value == "-" { return 0 }
        guard value.hasPrefix("$"), let number = Double(value.dropFirst()), number.isFinite, number > 0, number <= 10_000 else { return nil }
        return number
    }

    static func mergedRates(current: [ModelRate], previous: [ModelRate], incoming: [ModelRate], overrides: Set<String> = []) -> [ModelRate] {
        func key(_ model: String) -> String { model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let old = Dictionary(previous.map { (key($0.model), $0) }, uniquingKeysWith: { first, _ in first })
        var result = current
        for rate in incoming {
            let model = key(rate.model)
            guard !overrides.contains(model) else { continue }
            if let index = result.firstIndex(where: { key($0.model) == model }) {
                let existing = result[index]
                if existing == old[model] || (existing.inputPerMillion == 0 && existing.cachedInputPerMillion == 0 && existing.outputPerMillion == 0) {
                    result[index] = rate
                }
            } else if old[model] == nil {
                result.append(rate)
            }
        }
        return result
    }
}

private final class PricingRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum PricingCatalogClient {
    static let sourceURL = URL(string: "https://developers.openai.com/api/docs/pricing.md")!

    static func fetch() async throws -> PricingCatalog {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration, delegate: PricingRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: sourceURL)
        request.setValue("text/markdown", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.url == sourceURL else {
            throw PricingCatalogError.invalidResponse
        }
        let maximumSize = 2_000_000
        guard response.expectedContentLength <= maximumSize else { throw PricingCatalogError.tooLarge }
        var data = Data()
        for try await byte in bytes {
            guard data.count < maximumSize else { throw PricingCatalogError.tooLarge }
            data.append(byte)
        }
        guard let document = String(data: data, encoding: .utf8) else { throw PricingCatalogError.invalidDocument }
        return try PricingCatalog.parse(document)
    }
}
