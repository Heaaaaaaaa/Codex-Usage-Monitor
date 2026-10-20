import Darwin
import Foundation

struct AccountResetInventory: Sendable {
    let availableCount: Int
    let credits: [ResetCredit]
    let fetchedAt: Date

    func activeCredits(now: Date) -> [ResetCredit] {
        credits.filter { $0.expiresAt.map { $0 > now } ?? true }
    }

    func remainingCount(now: Date) -> Int {
        max(0, availableCount - (credits.count - activeCredits(now: now).count))
    }

    static func decode(_ data: Data, now: Date = Date()) throws -> AccountResetInventory {
        struct Credit: Decodable {
            let id: String
            let status: String
            let title: String?
            let expiresAt: Double?
        }
        struct Inventory: Decodable {
            let availableCount: Int
            let credits: [Credit]?
        }
        struct Response: Decodable {
            let rateLimitResetCredits: Inventory?
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw AccountResetError.invalidResponse
        }
        guard let inventory = response.rateLimitResetCredits else { throw AccountResetError.unavailable }
        guard (0...1_000_000).contains(inventory.availableCount) else { throw AccountResetError.invalidResponse }
        var seen = Set<String>()
        let credits = (inventory.credits ?? []).compactMap { item -> ResetCredit? in
            guard item.status == "available", !item.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  seen.insert(item.id).inserted else { return nil }
            let expiry = item.expiresAt.map { Date(timeIntervalSince1970: $0) }
            guard expiry.map({ $0 > now }) ?? true else { return nil }
            let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            return ResetCredit(id: item.id, label: title.flatMap { $0.isEmpty ? nil : $0 } ?? "Usage reset", expiresAt: expiry)
        }.sorted { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
        return AccountResetInventory(availableCount: inventory.availableCount,
                                     credits: Array(credits.prefix(inventory.availableCount)), fetchedAt: now)
    }
}

enum AccountResetError: Error, LocalizedError {
    case cliMissing, invalidResponse, unavailable, timedOut, requestFailed

    var errorDescription: String? {
        switch self {
        case .cliMissing: return "Install Codex or ChatGPT with the Codex CLI"
        case .invalidResponse: return "Reset response not supported; update Codex"
        case .unavailable: return "Reset count not provided by Codex"
        case .timedOut: return "Account sync timed out; saved count retained"
        case .requestFailed: return "Account sync failed; check Codex sign-in"
        }
    }
}

enum AccountResetClient {
    static func fetch(codexHome: URL) async throws -> AccountResetInventory {
        try await Task.detached(priority: .utility) {
            guard let executable = executableURL() else { throw AccountResetError.cliMissing }
            return try read(executable: executable, codexHome: codexHome)
        }.value
    }

    static func executableURL() -> URL? {
        let applications = [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        var candidates = applications.flatMap { root in
            ["Codex.app", "ChatGPT.app"].map {
                root.appendingPathComponent("\($0)/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex")
            }
        }
        #if arch(arm64)
        let architecture = "arm64", target = "aarch64-apple-darwin"
        #else
        let architecture = "x64", target = "x86_64-apple-darwin"
        #endif
        for prefix in ["/opt/homebrew", "/usr/local"] {
            candidates.append(URL(fileURLWithPath: "\(prefix)/lib/node_modules/@openai/codex/node_modules/@openai/codex-darwin-\(architecture)/vendor/\(target)/bin/codex"))
            candidates.append(URL(fileURLWithPath: "\(prefix)/bin/codex"))
        }
        return candidates.first { url in
            guard FileManager.default.isExecutableFile(atPath: url.path), let handle = try? FileHandle(forReadingFrom: url) else { return false }
            defer { try? handle.close() }
            // Run a native CLI directly so timeout cleanup owns the actual process.
            guard let magic = try? handle.read(upToCount: 4) else { return false }
            let signatures: [[UInt8]] = [[0xcf, 0xfa, 0xed, 0xfe], [0xce, 0xfa, 0xed, 0xfe], [0xca, 0xfe, 0xba, 0xbe], [0xca, 0xfe, 0xba, 0xbf]]
            return signatures.contains(Array(magic))
        }
    }

    static func read(executable: URL, codexHome: URL, timeout: TimeInterval = 25) throws -> AccountResetInventory {
        let process = Process()
        let input = Pipe(), output = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://", "-c", "analytics.enabled=false"]
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.environment = ["HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                               "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin",
                               "TMPDIR": FileManager.default.temporaryDirectory.path,
                               "CODEX_HOME": codexHome.path]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw AccountResetError.requestFailed }
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            let deadline = Date().addingTimeInterval(0.5)
            while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            try? output.fileHandleForReading.close()
        }
        func send(_ value: [String: Any]) throws {
            let data = try JSONSerialization.data(withJSONObject: value) + Data([10])
            do { try input.fileHandleForWriting.write(contentsOf: data) } catch { throw AccountResetError.requestFailed }
        }
        try send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "codex_usage_monitor", "version": "0.5.4"]]])
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = Data()
        var bytes = [UInt8](repeating: 0, count: 65_536)
        var initialized = false
        while Date() < deadline {
            var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let status = poll(&descriptor, 1, Int32(min(1_000, max(1, deadline.timeIntervalSinceNow * 1_000))))
            if status < 0 { if errno == EINTR { continue }; throw AccountResetError.requestFailed }
            if status == 0 { continue }
            let count = Darwin.read(descriptor.fd, &bytes, bytes.count)
            guard count > 0 else { throw AccountResetError.requestFailed }
            buffer.append(contentsOf: bytes.prefix(count))
            guard buffer.count <= 512_000 else { throw AccountResetError.invalidResponse }
            while let end = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<end])
                buffer.removeSubrange(...end)
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { throw AccountResetError.invalidResponse }
                if (object["id"] as? Int) == 1 && !initialized {
                    guard object["error"] == nil, object["result"] != nil else { throw AccountResetError.requestFailed }
                    initialized = true
                    try send(["method": "initialized", "params": [:] as [String: String]])
                    // This client deliberately has no consume, login, or thread methods.
                    try send(["id": 2, "method": "account/rateLimits/read", "params": [:] as [String: String]])
                } else if (object["id"] as? Int) == 2 && initialized {
                    guard object["error"] == nil, let result = object["result"] as? [String: Any] else { throw AccountResetError.requestFailed }
                    return try AccountResetInventory.decode(JSONSerialization.data(withJSONObject: result))
                } else if object["method"] != nil, let id = object["id"] {
                    try send(["id": id, "error": ["code": -32601, "message": "Read-only usage monitor"]])
                }
            }
        }
        throw AccountResetError.timedOut
    }
}
