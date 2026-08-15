import AppKit
import Combine
import NeonCore
import SwiftUI

/// 把偏好、状态、窗口、通知串起来的中枢。
@MainActor
final class AppCoordinator: ObservableObject {
    /// AppDelegate 与 SwiftUI 场景要拿到同一个实例
    static let shared = AppCoordinator()

    let prefs: Preferences
    let store: StatusStore

    private var windowManager: StripWindowManager?
    private let confetti = ConfettiPresenter()
    private let notifier: Notifier
    private var cancellables: Set<AnyCancellable> = []

    // 默认参数在调用方上下文求值，Preferences.shared 是 @MainActor 隔离的，
    // 所以不能写成默认值，只能在这里取
    init(prefs: Preferences? = nil) {
        let prefs = prefs ?? .shared
        self.prefs = prefs
        self.store = StatusStore(prefs: prefs)
        self.notifier = Notifier(prefs: prefs)
    }

    func start() {
        // 菜单栏应用：不进 Dock、不抢焦点
        NSApp.setActivationPolicy(.accessory)

        windowManager = StripWindowManager(prefs: prefs, store: store)

        store.onStateChange = { [weak self] state, session in
            self?.handleStateChange(state, session: session)
        }

        prefs.$claudeEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                Task { @MainActor in
                    guard let self else { return }
                    if enabled {
                        self.store.start()
                        self.notifier.requestAuthorizationIfNeeded()
                    } else {
                        self.store.stop()
                    }
                }
            }
            .store(in: &cancellables)

        if prefs.claudeEnabled {
            store.start()
            notifier.requestAuthorizationIfNeeded()
        }
    }

    private func handleStateChange(_ state: TrafficState, session: SessionStatus?) {
        guard prefs.claudeEnabled else { return }
        notifier.handle(state: state, session: session)
        if state == .finished, prefs.confettiEnabled {
            confetti.celebrate()
        }
    }

    /// 设置面板里的"试一试"，不依赖真实会话就能看到灯效
    func preview(state: TrafficState) {
        let sample = SessionStatus(
            sessionID: "neonnotify-preview",
            state: state,
            event: previewEvent(for: state),
            cwd: FileManager.default.currentDirectoryPath,
            message: "预览：\(state.displayName)"
        )
        if state == .idle {
            StatusPaths.remove(sessionID: sample.sessionID)
        } else {
            try? StatusPaths.write(sample)
        }
        store.reload()
    }

    private func previewEvent(for state: TrafficState) -> String {
        switch state {
        case .idle: return "SessionStart"
        case .running: return "UserPromptSubmit"
        case .waiting: return "Notification"
        case .finished: return "Stop"
        }
    }
}
