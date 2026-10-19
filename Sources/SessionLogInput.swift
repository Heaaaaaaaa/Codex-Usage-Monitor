import Foundation

// Both formats feed the same bounded JSONL parser. No extracted logs are written.
final class SessionLogInput {
    private let file: FileHandle?
    private let decoder: OpaquePointer?

    init(url: URL) throws {
        if url.lastPathComponent.hasSuffix(".jsonl.zst") {
            guard let decoder = url.path.withCString({ usage_log_open($0) }) else {
                throw CocoaError(.fileReadUnknown)
            }
            self.decoder = decoder
            self.file = nil
        } else {
            self.file = try FileHandle(forReadingFrom: url)
            self.decoder = nil
        }
    }

    deinit {
        if let decoder { usage_log_close(decoder) }
        try? file?.close()
    }

    func read(upToCount count: Int) throws -> Data? {
        guard let decoder else { return try file?.read(upToCount: count) }
        var data = Data(count: count)
        let size = data.withUnsafeMutableBytes { buffer in
            usage_log_read(decoder, buffer.baseAddress, buffer.count)
        }
        guard size >= 0 else { throw CocoaError(.fileReadCorruptFile) }
        guard size > 0 else { return nil }
        data.count = Int(size)
        return data
    }
}
