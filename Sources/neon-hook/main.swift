import Foundation
import NeonCore

// neon-hook —— 由 Claude Code 的 hooks 调用，读 stdin 的事件 JSON，
// 把会话状态写进 ~/.claude/neon-status/<session_id>.json。
//
// 铁律：
//   1. 永远 exit(0)，任何异常都不能让 Claude Code 报错。
//   2. 不向 stdout 写任何东西（stdout 会被当成 hook 的返回值解析）。
//   3. 尽量快，冷启动就是 Claude Code 每次事件的额外开销。

/// 除了被 Claude Code 调用，还支持三个命令行子命令，方便不开设置面板也能装卸：
///   neon-hook --install / --uninstall / --status
private func runCommandLine(_ argument: String) -> Int32 {
    switch argument {
    case "--install":
        do {
            let backup = try HookInstaller.install()
            print("已安装 hooks 到 \(HookInstaller.settingsURL.path)")
            print("hook 程序: \(HookInstaller.helperPath)")
            if let backup { print("原配置已备份到 \(backup.lastPathComponent)") }
            print("请重开 Claude Code 会话使其生效。")
            return 0
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            return 1
        }
    case "--uninstall":
        do {
            let backup = try HookInstaller.uninstall()
            print("已从 \(HookInstaller.settingsURL.path) 移除 hooks")
            if let backup { print("原配置已备份到 \(backup.lastPathComponent)") }
            return 0
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            return 1
        }
    case "--status":
        let installed = HookInstaller.installedPaths()
        print("settings.json: \(HookInstaller.settingsURL.path)")
        print("当前 hook 程序: \(HookInstaller.helperPath)")
        if installed.isEmpty {
            print("状态: 未安装")
        } else if HookInstaller.isInstalled() {
            print("状态: 已安装")
        } else {
            print("状态: 已安装但指向别处 \(installed.sorted().joined(separator: ", "))，建议重新安装")
        }
        return 0
    case "--help", "-h":
        print("""
        neon-hook —— NeonNotify 的 Claude Code hook

        由 Claude Code 通过 hooks 自动调用（读 stdin 的事件 JSON）。
        也支持手工管理配置：
          --install     写入 hooks 到 ~/.claude/settings.json（自动备份）
          --uninstall   移除本 app 写入的 hooks
          --status      查看安装状态
        """)
        return 0
    default:
        return 0
    }
}

/// 从 JSON 对象里取字符串，容忍字段缺失
private func string(_ object: [String: Any], _ key: String) -> String? {
    guard let value = object[key] as? String, !value.isEmpty else { return nil }
    return value
}

private func run() {
    // stdin 可能是空的（手工调用），readDataToEndOfFile 不会阻塞太久
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard !input.isEmpty,
          let object = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any]
    else { return }

    guard let event = string(object, "hook_event_name") else { return }
    let sessionID = string(object, "session_id") ?? "unknown"

    // 抓包模式：记下收到的事件，用来查"某个操作触发了哪些 hook"。
    // 事件名放最前面 —— 它在原始 JSON 里靠后，直接截断会把它切掉。
    StatusPaths.appendEventLog("\(event) \(String(decoding: input, as: UTF8.self).prefix(1200))")

    // 不认识的事件只记录、不改状态
    guard HookEventMapping.isKnown(event) else { return }

    if HookEventMapping.terminatingEvents.contains(event) {
        StatusPaths.remove(sessionID: sessionID)
        notifyObservers()
        return
    }

    if HookEventMapping.ignoredEvents.contains(event) { return }

    let notificationType = string(object, "notification_type")
    let state = HookEventMapping.state(event: event, notificationType: notificationType)

    // 回合已经结束的话，只认「开始新一轮」这类事件，其余迟到事件一律不写
    if let existing = StatusPaths.read(sessionID: sessionID), existing.event == "Stop" {
        guard HookEventMapping.shouldOverrideFinishedTurn(event: event) else { return }
    }

    // 通知正文：优先用通知消息，其次是最后一条助手消息，再次是工具名
    let message = string(object, "notification_message")
        ?? string(object, "last_assistant_message").map { String($0.prefix(200)) }
        ?? string(object, "tool_name")

    let status = SessionStatus(
        sessionID: sessionID,
        state: state,
        event: event,
        cwd: string(object, "cwd"),
        message: message,
        transcriptPath: string(object, "transcript_path")
    )

    try? StatusPaths.write(status)
    notifyObservers()

    // 会话被 kill 时不会有 SessionEnd，顺手清理陈旧文件（很便宜，只 stat 目录）
    if event == "SessionStart" {
        StatusPaths.pruneStale()
    }
}

/// 广播 Darwin notification，让 app 立刻刷新，不必等文件系统事件
private func notifyObservers() {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFNotificationName(StatusPaths.darwinNotificationName as CFString),
        nil,
        nil,
        true
    )
}

if let argument = CommandLine.arguments.dropFirst().first, argument.hasPrefix("--") {
    exit(runCommandLine(argument))
}

run()
exit(0)
