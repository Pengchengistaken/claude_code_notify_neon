import Foundation

/// 从对话记录里找出"用户按了 Ctrl+C"。
///
/// Claude Code 没有任何取消/中断事件（实测按 Ctrl+C 后不发 Stop，也不发
/// PermissionDenied），最后一个 hook 事件会停在 PreToolUse/PostToolUse 上，
/// 灯带就一直黄到超时。
///
/// 但中断一定会写进对话记录：一条 `type: "user"` 且带顶层 `interruptedMessageId`
/// 字段的记录，时间戳就是按下 Ctrl+C 的时刻。记录文件路径每个 hook payload 都带
/// （`transcript_path`），所以拿得到。
public enum TranscriptInspector {
    /// 只读文件尾部，记录文件可能有几十 MB
    private static let tailByteCount = 64 * 1024

    /// 返回记录里最后一次中断的时间，没有则返回 nil
    public static func lastInterrupt(atPath path: String) -> Date? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }

        guard let size = try? handle.seekToEnd() else { return nil }
        let offset = size > UInt64(tailByteCount) ? size - UInt64(tailByteCount) : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return nil }

        let text = String(decoding: data, as: UTF8.self)
        // 从后往前找，最后一条中断才是最新的
        for line in text.split(separator: "\n").reversed() {
            guard line.contains("\"interruptedMessageId\"") else { continue }
            guard let lineData = line.data(using: .utf8),
                  let object = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any],
                  object["interruptedMessageId"] != nil,
                  let timestamp = object["timestamp"] as? String
            else { continue }
            return date(from: timestamp)
        }
        return nil
    }

    /// 记录里的时间戳带毫秒：2026-08-15T02:10:13.586Z
    private static func date(from string: String) -> Date? {
        if let date = fractionalFormatter.date(from: string) { return date }
        return plainFormatter.date(from: string)
    }

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainFormatter = ISO8601DateFormatter()
}
