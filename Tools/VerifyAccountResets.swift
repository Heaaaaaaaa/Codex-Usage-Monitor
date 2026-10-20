import Foundation

@main
struct VerifyAccountResets {
    static func main() async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        let inventory = try await AccountResetClient.fetch(codexHome: home)
        print("Available resets: \(inventory.availableCount)")
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        for credit in inventory.credits {
            print("\(credit.label): \(credit.expiresAt.map { formatter.string(from: $0) } ?? "expiry not provided")")
        }
    }
}
