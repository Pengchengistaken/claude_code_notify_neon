import Foundation

/// 把 hook 配置合并进 ~/.claude/settings.json，以及干净地卸载。
///
/// 原则：只碰 `hooks` 字段里属于自己的条目，其余（tui / theme / model / env
/// 以及用户自己的 hooks）原样保留；改动前先备份。
public enum HookInstaller {
    /// 要挂钩的事件。覆盖三色状态所需的全部时机。
    public static let events: [(event: String, needsMatcher: Bool)] = [
        ("SessionStart", false),
        ("UserPromptSubmit", false),
        ("PreToolUse", true),
        ("PostToolUse", true),
        ("Notification", false),
        ("PermissionRequest", true),
        ("Stop", false),
        // 不挂 SubagentStop：它会在回合结束的 Stop 之后才到，把绿灯打回黄灯
        ("SessionEnd", false),
    ]

    public static let helperName = "neon-hook"

    public enum InstallError: LocalizedError {
        case helperMissing(String)
        case settingsUnreadable(String)
        case settingsMalformed

        public var errorDescription: String? {
            switch self {
            case let .helperMissing(path):
                return "找不到 hook 程序：\(path)。请确认 app 完整，未被拆包。"
            case let .settingsUnreadable(path):
                return "无法读取 \(path)。"
            case .settingsMalformed:
                return "~/.claude/settings.json 不是合法的 JSON 对象，已中止，未做任何修改。"
            }
        }
    }

    public static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude/settings.json", directoryHint: .notDirectory)
    }

    /// 当前 app 内 hook 可执行文件的绝对路径。
    /// 主 app 与 neon-hook 自己调用时都要得到同一个路径，所以按可执行文件所在目录推。
    public static var helperPath: String {
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            return bundleURL
                .appending(path: "Contents/MacOS/\(helperName)", directoryHint: .notDirectory)
                .path
        }
        // 未打包运行（swift run）时退回到可执行文件同级目录
        return bundleURL.appending(path: helperName, directoryHint: .notDirectory).path
    }

    // MARK: 状态查询

    /// 已安装且路径与当前 app 一致
    public static func isInstalled() -> Bool {
        installedPaths().contains(helperPath)
    }

    /// 装的是别处的同名 hook（app 被移动过），需要提示重新安装
    public static func hasStalePath() -> Bool {
        let paths = installedPaths()
        return !paths.isEmpty && !paths.contains(helperPath)
    }

    public static func installedPaths() -> Set<String> {
        guard let root = readSettings() else { return [] }
        var result: Set<String> = []
        let hooks = root["hooks"] as? [String: Any] ?? [:]
        for (_, value) in hooks {
            for group in value as? [[String: Any]] ?? [] {
                for entry in group["hooks"] as? [[String: Any]] ?? [] {
                    if let command = entry["command"] as? String, command.hasSuffix(helperName) {
                        result.insert(command)
                    }
                }
            }
        }
        return result
    }

    /// 设置面板里展示的配置预览
    public static func previewJSON() -> String {
        let payload: [String: Any] = ["hooks": desiredHooks()]
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: 安装 / 卸载

    @discardableResult
    public static func install() throws -> URL? {
        guard FileManager.default.isExecutableFile(atPath: helperPath) else {
            throw InstallError.helperMissing(helperPath)
        }
        var root = try requireSettings()
        // 先把自己以前写进去的条目全部清掉再重写。只遍历"本版要挂的事件"是不够的：
        // 上一版挂过、这一版不再挂的事件（比如 SubagentStop）会变成孤儿留在配置里。
        var hooks = strippingOwnEntries(from: root["hooks"] as? [String: Any] ?? [:])

        for (event, entries) in desiredHooks() {
            var groups = hooks[event] as? [[String: Any]] ?? []
            groups.append(contentsOf: entries)
            hooks[event] = groups
        }

        root["hooks"] = hooks
        let backup = try backupExistingSettings()
        try writeSettings(root)
        return backup
    }

    @discardableResult
    public static func uninstall() throws -> URL? {
        guard var root = readSettings() else { return nil }
        guard let existing = root["hooks"] as? [String: Any] else { return nil }

        let hooks = strippingOwnEntries(from: existing)

        if hooks.isEmpty {
            root["hooks"] = nil
        } else {
            root["hooks"] = hooks
        }

        let backup = try backupExistingSettings()
        try writeSettings(root)
        return backup
    }

    // MARK: 内部

    private static func desiredHooks() -> [String: [[String: Any]]] {
        var result: [String: [[String: Any]]] = [:]
        let entry: [String: Any] = [
            "type": "command",
            "command": helperPath,
            "timeout": 5,
        ]
        for (event, needsMatcher) in events {
            var group: [String: Any] = ["hooks": [entry]]
            if needsMatcher { group["matcher"] = "*" }
            result[event] = [group]
        }
        return result
    }

    /// 把整个 hooks 字典里属于自己的条目全部摘掉，用户自己的 hooks 原样保留
    private static func strippingOwnEntries(from hooks: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else {
                result[event] = value
                continue
            }
            let cleaned = removingOwnEntries(from: groups)
            if !cleaned.isEmpty { result[event] = cleaned }
        }
        return result
    }

    /// 删掉 command 指向任意 neon-hook 的条目，保留用户自己的 hooks
    private static func removingOwnEntries(from groups: [[String: Any]]) -> [[String: Any]] {
        groups.compactMap { group -> [String: Any]? in
            guard let entries = group["hooks"] as? [[String: Any]] else { return group }
            let kept = entries.filter { entry in
                guard let command = entry["command"] as? String else { return true }
                return !command.hasSuffix(helperName)
            }
            if kept.isEmpty { return nil }
            var copy = group
            copy["hooks"] = kept
            return copy
        }
    }

    private static func readSettings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: settingsURL) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// 文件不存在 → 空配置；文件存在但不是 JSON 对象 → 报错中止，绝不覆盖
    private static func requireSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        guard let data = try? Data(contentsOf: settingsURL) else {
            throw InstallError.settingsUnreadable(settingsURL.path)
        }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw InstallError.settingsMalformed
        }
        return object
    }

    private static func backupExistingSettings() throws -> URL? {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return nil }
        let stamp = ISO8601DateFormatter.filenameSafe.string(from: Date())
        let backup = settingsURL.deletingLastPathComponent()
            .appending(path: "settings.json.neonbak-\(stamp)", directoryHint: .notDirectory)
        try? FileManager.default.removeItem(at: backup)
        try FileManager.default.copyItem(at: settingsURL, to: backup)
        pruneBackups(keeping: 5)
        return backup
    }

    /// 备份只保留最近几份，避免反复装卸把 ~/.claude 塞满
    private static func pruneBackups(keeping limit: Int) {
        let directory = settingsURL.deletingLastPathComponent()
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        let backups = names
            .filter { $0.hasPrefix("settings.json.neonbak-") }
            .sorted(by: >)  // 文件名带 ISO 时间戳，字典序即时间序
        for name in backups.dropFirst(limit) {
            try? FileManager.default.removeItem(at: directory.appending(path: name, directoryHint: .notDirectory))
        }
    }

    private static func writeSettings(_ root: [String: Any]) throws {
        var data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        data.append(0x0A)  // 保留结尾换行，别让文件在 git diff 里显得脏
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: settingsURL, options: .atomic)
    }
}

private extension ISO8601DateFormatter {
    static let filenameSafe: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        return formatter
    }()
}
