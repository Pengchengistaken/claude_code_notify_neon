import NeonCore
import SettingsAccess
import SwiftUI

@main
struct NeonNotifyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var coordinator = AppCoordinator.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(coordinator: coordinator)
        } label: {
            Image(systemName: menuBarSymbol)
        }

        Settings {
            SettingsRootView(coordinator: coordinator)
        }
    }

    private var menuBarSymbol: String {
        coordinator.prefs.lightingEnabled ? "light.beacon.max.fill" : "light.beacon.max"
    }
}

/// SwiftUI 的 App 生命周期不提供启动时机做 AppKit 初始化，用 delegate 补上
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppCoordinator.shared.start()
    }
}

private struct MenuContent: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject private var prefs: Preferences
    @ObservedObject private var store: StatusStore

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        self.prefs = coordinator.prefs
        self.store = coordinator.store
    }

    var body: some View {
        Toggle("开启灯光", isOn: $prefs.lightingEnabled)
        Toggle("Claude Code 通知", isOn: $prefs.claudeEnabled)

        Divider()

        if prefs.claudeEnabled {
            Text("\(store.effectiveState.emoji) \(store.effectiveState.displayName)")
            if !store.sessions.isEmpty {
                Text("\(store.sessions.count) 个会话")
            }
            Divider()
        }

        // MenuBarExtra 的 menu 形态里 openSettings 不可用，必须用 SettingsLink。
        // 用 SettingsAccess 的 preAction 版本：.accessory 应用不激活的话，
        // 设置窗口会开在别的窗口后面。
        SettingsLink {
            Text("设置…")
        } preAction: {
            NSApp.activate(ignoringOtherApps: true)
        } postAction: {
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("退出 NeonNotify") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
