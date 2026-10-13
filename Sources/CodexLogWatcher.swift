import Darwin
import Foundation

// Mutable state is accessed on the main actor; deinit only cancels the remaining sources.
final class CodexLogWatcher: @unchecked Sendable {
    @MainActor var onChange: (@MainActor @Sendable () -> Void)?

    private let queue = DispatchQueue(label: "CodexUsageMonitor.LogWatcher")
    private let discoveryQueue = DispatchQueue(label: "CodexUsageMonitor.LogDiscovery", qos: .utility)
    private let discover: @Sendable (URL) -> [URL]
    private var sources: [String: WatchedLog] = [:]
    private var pendingChange: DispatchWorkItem?
    private var discoveryGeneration: UInt64 = 0
    private var codexHome: URL?

    init(discover: @escaping @Sendable (URL) -> [URL] = { SessionLogDiscovery.candidates(codexHome: $0) }) {
        self.discover = discover
    }

    deinit {
        pendingChange?.cancel()
        sources.values.forEach { $0.source.cancel() }
    }

    @MainActor var watchedPaths: Set<String> { Set(sources.keys) }

    @MainActor
    func start(codexHome: URL) {
        let home = codexHome.standardizedFileURL
        if self.codexHome != home {
            stop()
            self.codexHome = home
        }
        discoveryGeneration &+= 1
        let generation = discoveryGeneration
        let discover = discover
        discoveryQueue.async { [weak self] in
            let candidates = discover(home)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.discoveryGeneration == generation, self.codexHome == home else {
                    return
                }
                self.reconcile(candidates)
            }
        }
    }

    @MainActor
    func stop() {
        discoveryGeneration &+= 1
        codexHome = nil
        pendingChange?.cancel()
        pendingChange = nil
        let activeSources = Array(sources.values)
        sources.removeAll(keepingCapacity: true)
        activeSources.forEach { $0.source.cancel() }
        queue.sync {}
    }

    @MainActor
    private func reconcile(_ candidates: [URL]) {
        let paths = Set(candidates.map(\.path))
        let retired = sources.keys.filter { !paths.contains($0) }
        for path in retired {
            sources.removeValue(forKey: path)?.source.cancel()
        }
        if !retired.isEmpty {
            queue.sync {}
        }
        for url in candidates where sources[url.path] == nil {
            watch(url)
        }
    }

    @MainActor
    private func watch(_ url: URL) {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .link, .rename, .delete, .revoke],
            queue: queue
        )
        let registration = WatchedLog(source: source)
        source.setEventHandler { [weak self, weak registration] in
            guard let registration else { return }
            let events = registration.source.data
            DispatchQueue.main.async { [weak self] in
                guard let self, self.sources[url.path] === registration else { return }
                if !events.intersection([.rename, .delete, .revoke]).isEmpty {
                    self.sources.removeValue(forKey: url.path)?.source.cancel()
                }
                self.scheduleChange()
            }
        }
        source.setCancelHandler { close(descriptor) }
        sources[url.path] = registration
        source.resume()
    }

    @MainActor
    private func scheduleChange() {
        pendingChange?.cancel()
        let generation = discoveryGeneration
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.discoveryGeneration == generation, !self.sources.isEmpty else { return }
                self.pendingChange = nil
                self.onChange?()
            }
        }
        pendingChange = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }
}

private final class WatchedLog: @unchecked Sendable {
    let source: DispatchSourceFileSystemObject

    init(source: DispatchSourceFileSystemObject) {
        self.source = source
    }
}

enum SessionLogDiscovery {
    static let maxWatchedSessionFiles = 64

    static func candidates(codexHome: URL) -> [URL] {
        let roots = [codexHome, codexHome.appendingPathComponent("sessions"),
                     codexHome.appendingPathComponent("archived_sessions"),
                     codexHome.appendingPathComponent("session_index.jsonl")]
        return roots.filter { FileManager.default.fileExists(atPath: $0.path) } + recentFiles(codexHome: codexHome)
    }

    static func recentFiles(codexHome: URL) -> [URL] {
        var newest: [(url: URL, modifiedAt: Date)] = []
        newest.reserveCapacity(maxWatchedSessionFiles)
        for name in ["sessions", "archived_sessions"] {
            guard let enumerator = FileManager.default.enumerator(
                at: codexHome.appendingPathComponent(name),
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                      values.isRegularFile == true else { continue }
                let candidate = (url: url, modifiedAt: values.contentModificationDate ?? .distantPast)
                let position = newest.firstIndex {
                    candidate.modifiedAt > $0.modifiedAt ||
                    (candidate.modifiedAt == $0.modifiedAt && candidate.url.path > $0.url.path)
                } ?? newest.count
                guard position < maxWatchedSessionFiles else { continue }
                newest.insert(candidate, at: position)
                if newest.count > maxWatchedSessionFiles { newest.removeLast() }
            }
        }
        return newest.map(\.url)
    }
}
