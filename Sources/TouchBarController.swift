import AppKit
import Combine
import SwiftUI

final class UsageHostingController: NSHostingController<RootView>, NSTouchBarDelegate {
    private let store: UsageStore
    private var touchBarSummaryLabel: NSTextField?
    private var touchBarWindowControl: NSSegmentedControl?
    private var touchBarCancellable: AnyCancellable?

    init(rootView: RootView, store: UsageStore) {
        self.store = store
        super.init(rootView: rootView)
        touchBarCancellable = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateTouchBarControls()
            }
        }
    }

    @available(*, unavailable)
    required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func makeTouchBar() -> NSTouchBar? {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [.usageSummary, .fixedSpaceSmall, .usageRefresh, .usageWindow, .usageCopy]
        return bar
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case .usageSummary:
            let item = NSCustomTouchBarItem(identifier: identifier)
            let label = NSTextField(labelWithString: store.touchBarSummary)
            label.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
            label.alignment = .center
            touchBarSummaryLabel = label
            item.view = label
            return item
        case .usageRefresh:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = NSButton(title: "Refresh", target: self, action: #selector(refreshFromTouchBar))
            return item
        case .usageWindow:
            let item = NSCustomTouchBarItem(identifier: identifier)
            let control = NSSegmentedControl(labels: DateWindow.allCases.map(\.rawValue), trackingMode: .selectOne, target: self, action: #selector(windowChanged(_:)))
            if let index = DateWindow.allCases.firstIndex(of: store.dateWindow) {
                control.selectedSegment = index
            }
            touchBarWindowControl = control
            item.view = control
            return item
        case .usageCopy:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = NSButton(title: "Copy", target: self, action: #selector(copySummary))
            return item
        default:
            return nil
        }
    }

    private func updateTouchBarControls() {
        touchBarSummaryLabel?.stringValue = store.touchBarSummary
        if let index = DateWindow.allCases.firstIndex(of: store.dateWindow) {
            touchBarWindowControl?.selectedSegment = index
        }
    }

    @objc private func refreshFromTouchBar() {
        store.refresh()
    }

    @objc private func windowChanged(_ sender: NSSegmentedControl) {
        let index = sender.selectedSegment
        guard DateWindow.allCases.indices.contains(index) else {
            return
        }
        store.setDateWindow(DateWindow.allCases[index])
    }

    @objc private func copySummary() {
        AppActions.copySummary(store: store)
    }
}

extension NSTouchBarItem.Identifier {
    static let usageSummary = NSTouchBarItem.Identifier("local.codex.usagemonitor.summary")
    static let usageRefresh = NSTouchBarItem.Identifier("local.codex.usagemonitor.refresh")
    static let usageWindow = NSTouchBarItem.Identifier("local.codex.usagemonitor.window")
    static let usageCopy = NSTouchBarItem.Identifier("local.codex.usagemonitor.copy")
}
