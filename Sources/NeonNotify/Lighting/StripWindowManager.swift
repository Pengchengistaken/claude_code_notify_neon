import AppKit
import Combine
import SwiftUI

/// 按设置在各块屏幕上创建/销毁灯带窗口，并响应显示器热插拔。
@MainActor
final class StripWindowManager {
    private let prefs: Preferences
    private let store: StatusStore
    /// key 为 NSScreen 的 displayID，屏幕重排后仍能对上
    private var windows: [CGDirectDisplayID: OverlayWindow] = [:]
    private var cancellables: Set<AnyCancellable> = []

    init(prefs: Preferences, store: StatusStore) {
        self.prefs = prefs
        self.store = store

        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        // 只有影响窗口本身（层级/显示器/开关）的设置才需要重建
        prefs.$lightingEnabled.dropFirst().sink { [weak self] _ in self?.scheduleRefresh() }.store(in: &cancellables)
        prefs.$displayMode.dropFirst().sink { [weak self] _ in self?.scheduleRefresh() }.store(in: &cancellables)
        prefs.$level.dropFirst().sink { [weak self] _ in self?.scheduleRefresh() }.store(in: &cancellables)

        refresh()
    }

    /// @Published 在 willSet 时机触发，推迟一轮再读新值
    private func scheduleRefresh() {
        DispatchQueue.main.async { [weak self] in self?.refresh() }
    }

    func refresh() {
        guard prefs.lightingEnabled else {
            teardown()
            return
        }

        let targets = targetScreens()
        let targetIDs = Set(targets.compactMap(\.displayID))

        for (id, window) in windows where !targetIDs.contains(id) {
            window.orderOut(nil)
            window.close()
            windows[id] = nil
        }

        for screen in targets {
            guard let id = screen.displayID else { continue }
            if let existing = windows[id] {
                existing.level = prefs.level.windowLevel
                existing.setFrame(screen.frame, display: true)
            } else {
                let window = OverlayWindow(screen: screen, level: prefs.level.windowLevel)
                window.contentView = NSHostingView(
                    rootView: StripView(prefs: prefs, store: store)
                )
                window.orderFrontRegardless()
                windows[id] = window
            }
        }
    }

    func teardown() {
        for (_, window) in windows {
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
    }

    private func targetScreens() -> [NSScreen] {
        let screens = NSScreen.screens
        let primary = NSScreen.screens.first  // screens[0] 即主显示器
        switch prefs.displayMode {
        case .all:
            return screens
        case .primaryOnly:
            return primary.map { [$0] } ?? []
        case .exceptPrimary:
            return screens.filter { $0.displayID != primary?.displayID }
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
