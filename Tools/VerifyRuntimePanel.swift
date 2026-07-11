import AppKit
import Carbon
import CoreGraphics
import Foundation

private enum RuntimeVerificationError: LocalizedError {
    case invalidArguments
    case invalidBundle(URL)
    case launchFailed(String)
    case launchTimedOut
    case unexpectedBundle(String)
    case reopenFailed(String)
    case panelDidNotAppear
    case finderUnavailable
    case panelDidNotHide(Int)

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "usage: VerifyRuntimePanel /path/to/CodexUsageMonitor.app"
        case .invalidBundle(let url):
            return "could not read bundle identifier from \(url.path)"
        case .launchFailed(let detail):
            return "failed to reopen app: \(detail)"
        case .launchTimedOut:
            return "timed out waiting for app reopen"
        case .unexpectedBundle(let path):
            return "LaunchServices opened an unexpected app bundle: \(path)"
        case .reopenFailed(let detail):
            return "could not send reopen event: \(detail)"
        case .panelDidNotAppear:
            return "app reopened but no on-screen panel was found"
        case .finderUnavailable:
            return "Finder is not running"
        case .panelDidNotHide(let count):
            return "panel remained visible after Finder activation: \(count)"
        }
    }
}

private func wait(timeout: TimeInterval, until condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() {
            return true
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    return condition()
}

private func visiblePanelCount(for processIdentifier: pid_t) -> Int {
    guard let windows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
    ) as? [[String: Any]] else {
        return 0
    }
    return windows.filter { window in
        guard let owner = window[kCGWindowOwnerPID as String] as? NSNumber,
              owner.int32Value == processIdentifier,
              let layer = window[kCGWindowLayer as String] as? NSNumber,
              layer.intValue == 0,
              let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let height = bounds["Height"] as? NSNumber else {
            return false
        }
        return height.doubleValue >= 100
    }.count
}

private func sendReopenEvent(to processIdentifier: pid_t) throws {
    let target = NSAppleEventDescriptor(processIdentifier: processIdentifier)
    let event = NSAppleEventDescriptor(
        eventClass: AEEventClass(kCoreEventClass),
        eventID: AEEventID(kAEReopenApplication),
        targetDescriptor: target,
        returnID: AEReturnID(kAutoGenerateReturnID),
        transactionID: AETransactionID(kAnyTransactionID)
    )
    do {
        _ = try event.sendEvent(options: .noReply, timeout: 1)
    } catch {
        throw RuntimeVerificationError.reopenFailed(error.localizedDescription)
    }
}

private func launchErrorDescription(_ error: Error) -> String {
    let cocoaError = error as NSError
    var detail = "\(cocoaError.localizedDescription) [\(cocoaError.domain) \(cocoaError.code)]"
    if let underlying = cocoaError.userInfo[NSUnderlyingErrorKey] as? NSError {
        detail += " underlying=[\(underlying.domain) \(underlying.code): \(underlying.localizedDescription)]"
    }
    return detail
}

private func verifyPanelBehavior(appURL: URL) throws -> (before: Int, after: Int, processIdentifier: pid_t) {
    guard Bundle(url: appURL)?.bundleIdentifier != nil else {
        throw RuntimeVerificationError.invalidBundle(appURL)
    }

    let previousFrontmostApp = NSWorkspace.shared.frontmostApplication
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    configuration.createsNewApplicationInstance = true

    var runningApp: NSRunningApplication?
    var launchError: Error?
    NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, error in
        runningApp = app
        launchError = error
    }

    guard wait(timeout: 10, until: { runningApp != nil || launchError != nil }) else {
        throw RuntimeVerificationError.launchTimedOut
    }
    if let launchError {
        throw RuntimeVerificationError.launchFailed(launchErrorDescription(launchError))
    }
    guard let runningApp else {
        throw RuntimeVerificationError.launchTimedOut
    }
    let expectedURL = appURL.resolvingSymlinksInPath().standardizedFileURL
    let actualURL = runningApp.bundleURL?.resolvingSymlinksInPath().standardizedFileURL
    guard actualURL == expectedURL else {
        throw RuntimeVerificationError.unexpectedBundle(actualURL?.path ?? "unknown")
    }

    defer {
        runningApp.terminate()
        if let previousFrontmostApp,
           previousFrontmostApp.processIdentifier != runningApp.processIdentifier,
           !previousFrontmostApp.isTerminated {
            previousFrontmostApp.activate(options: [])
        }
    }

    try sendReopenEvent(to: runningApp.processIdentifier)
    guard wait(timeout: 5, until: { visiblePanelCount(for: runningApp.processIdentifier) > 0 }) else {
        throw RuntimeVerificationError.panelDidNotAppear
    }
    let visibleBefore = visiblePanelCount(for: runningApp.processIdentifier)

    guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else {
        throw RuntimeVerificationError.finderUnavailable
    }
    finder.activate(options: [])

    guard wait(timeout: 5, until: { visiblePanelCount(for: runningApp.processIdentifier) == 0 }) else {
        throw RuntimeVerificationError.panelDidNotHide(visiblePanelCount(for: runningApp.processIdentifier))
    }
    return (visibleBefore, 0, runningApp.processIdentifier)
}

do {
    guard CommandLine.arguments.count == 2 else {
        throw RuntimeVerificationError.invalidArguments
    }
    let result = try verifyPanelBehavior(appURL: URL(fileURLWithPath: CommandLine.arguments[1]))
    print("PASS transient panel visibility before=\(result.before) after=\(result.after) pid=\(result.processIdentifier)")
} catch {
    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    FileHandle.standardError.write(Data("FAIL runtime panel: \(message)\n".utf8))
    exit(1)
}
