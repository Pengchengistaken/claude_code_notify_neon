import AppKit
import NeonCore
import UserNotifications

/// 原生系统通知 + 提示音。
///
/// 用 UNUserNotificationCenter 而不是 osascript，通知横幅上显示的就是本 app 的
/// 名字和图标，不会变成 "Script Editor"。提示音走 NSSound 独立播放，
/// 即使用户拒绝了通知权限也还能听见。
@MainActor
final class Notifier {
    private let prefs: Preferences
    private var didRequestAuthorization = false

    init(prefs: Preferences) {
        self.prefs = prefs
    }

    /// 首次开启通知时申请权限
    func requestAuthorizationIfNeeded() {
        guard prefs.notificationsEnabled, !didRequestAuthorization else { return }
        didRequestAuthorization = true
        guard Bundle.main.bundleIdentifier != nil else { return }  // 未打包运行时跳过
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                NSLog("[NeonNotify] 通知授权失败: \(error.localizedDescription)")
            } else {
                NSLog("[NeonNotify] 通知授权: \(granted ? "已允许" : "被拒绝")")
            }
        }
    }

    /// 聚合状态变化时调用。只有红灯和绿灯值得打扰用户。
    func handle(state: TrafficState, session: SessionStatus?) {
        switch state {
        case .waiting:
            play(prefs.waitingSound)
            notify(
                title: "🔴 等待确认",
                body: body(for: session, fallback: "Claude Code 需要你确认"),
                sound: prefs.waitingSound
            )
        case .finished:
            play(prefs.finishedSound)
            notify(
                title: "🟢 运行完成",
                body: body(for: session, fallback: "Claude Code 已完成本轮任务"),
                sound: prefs.finishedSound
            )
        case .running, .idle:
            break
        }
    }

    private func body(for session: SessionStatus?, fallback: String) -> String {
        guard let session else { return fallback }
        let project = session.projectName.map { "[\($0)] " } ?? ""
        let detail = session.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let detail, !detail.isEmpty {
            return project + String(detail.prefix(160))
        }
        return project + fallback
    }

    private func notify(title: String, body: String, sound: AlertSound) {
        guard prefs.notificationsEnabled, Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // 声音已经用 NSSound 放过了，这里不再重复响铃
        content.sound = nil
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("[NeonNotify] 发送通知失败: \(error.localizedDescription)")
            }
        }
    }

    private func play(_ sound: AlertSound) {
        guard let name = sound.systemSoundName, let nsSound = NSSound(named: name) else { return }
        nsSound.stop()
        nsSound.play()
    }
}
