import Foundation

/// 状态文件目录与读写工具。app 与 hook 共用，保证路径/编码一致。
public enum StatusPaths {
    public static let bundleIdentifier = "com.lipengcheng.neonnotify"

    /// Darwin notification 名称，hook 写完文件后广播，app 立即刷新
    public static let darwinNotificationName = "com.lipengcheng.neonnotify.status"

    /// ~/.claude/neon-status
    public static var directory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appending(path: ".claude/neon-status", directoryHint: .isDirectory)
    }

    public static func fileURL(for sessionID: String) -> URL {
        directory.appending(path: sanitize(sessionID) + ".json", directoryHint: .notDirectory)
    }

    /// session_id 来自外部输入，去掉路径分隔符等危险字符
    public static func sanitize(_ sessionID: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = String(sessionID.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        return cleaned.isEmpty ? "unknown" : String(cleaned.prefix(96))
    }

    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// 原子写：先写临时文件再 rename，rename 会触发目录变更事件
    public static func write(_ status: SessionStatus) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = fileURL(for: status.sessionID)
        let data = try encoder.encode(status)
        let tmp = directory.appending(path: ".\(UUID().uuidString).tmp", directoryHint: .notDirectory)
        try data.write(to: tmp, options: .atomic)
        // replaceItemAt 在目标不存在时会失败，回退成 moveItem
        if fm.fileExists(atPath: target.path) {
            _ = try fm.replaceItemAt(target, withItemAt: tmp)
        } else {
            try fm.moveItem(at: tmp, to: target)
        }
    }

    public static func remove(sessionID: String) {
        try? FileManager.default.removeItem(at: fileURL(for: sessionID))
    }

    /// 存在这个文件时，hook 会把收到的每个事件原样追加到 events.log。
    /// 用来搞清楚"某个操作到底会触发哪些 hook"，比如按下 Ctrl+C 取消。
    public static var debugMarkerURL: URL {
        directory.appending(path: ".debug", directoryHint: .notDirectory)
    }

    public static var eventLogURL: URL {
        directory.appending(path: "events.log", directoryHint: .notDirectory)
    }

    public static func appendEventLog(_ line: String) {
        guard FileManager.default.fileExists(atPath: debugMarkerURL.path) else { return }
        let stamp = ISO8601DateFormatter().string(from: Date())
        guard let data = "\(stamp) \(line)\n".data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: eventLogURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: eventLogURL)
        }
    }

    public static func read(sessionID: String) -> SessionStatus? {
        guard let data = try? Data(contentsOf: fileURL(for: sessionID)) else { return nil }
        return try? decoder.decode(SessionStatus.self, from: data)
    }

    /// 读取目录下所有会话状态，损坏的文件直接跳过
    public static func readAll() -> [SessionStatus] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return [] }
        return names.compactMap { name in
            guard name.hasSuffix(".json") else { return nil }
            let url = directory.appending(path: name, directoryHint: .notDirectory)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(SessionStatus.self, from: data)
        }
    }

    /// 清理长期无更新的会话文件（进程被 kill 时不会走 SessionEnd）
    public static func pruneStale(olderThan interval: TimeInterval = 6 * 3600) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return }
        let cutoff = Date().addingTimeInterval(-interval)
        for name in names {
            let url = directory.appending(path: name, directoryHint: .notDirectory)
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = values.contentModificationDate,
                  modified < cutoff
            else { continue }
            try? fm.removeItem(at: url)
        }
    }
}
