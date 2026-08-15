import Foundation

/// 单个 Claude Code 会话的状态快照，由 neon-hook 写入、NeonNotify 读取。
public struct SessionStatus: Codable, Sendable, Equatable {
    public var sessionID: String
    public var state: TrafficState
    /// 触发本次状态的 hook 事件名，便于排查
    public var event: String
    /// 会话的工作目录，用于通知里显示项目名
    public var cwd: String?
    /// 需要确认的原因 / 最后一条助手消息摘要
    public var message: String?
    /// 对话记录路径。Claude Code 没有"取消"事件，只能靠它检测 Ctrl+C
    public var transcriptPath: String?
    public var updatedAt: Date

    public init(
        sessionID: String,
        state: TrafficState,
        event: String,
        cwd: String? = nil,
        message: String? = nil,
        transcriptPath: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.sessionID = sessionID
        self.state = state
        self.event = event
        self.cwd = cwd
        self.message = message
        self.transcriptPath = transcriptPath
        self.updatedAt = updatedAt
    }

    /// 通知里展示的项目名
    public var projectName: String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }
}
