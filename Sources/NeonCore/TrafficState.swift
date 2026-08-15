import Foundation

/// 交通灯状态。rawValue 会写进状态文件，改动等于改协议。
public enum TrafficState: String, Codable, Sendable, CaseIterable {
    /// 无活动，灯带回到默认彩虹
    case idle
    /// 🟡 正在运行
    case running
    /// 🔴 等待确认（权限询问 / 等待用户输入）
    case waiting
    /// 🟢 运行完成
    case finished

    /// 多会话聚合优先级：红 > 黄 > 绿 > idle
    public var priority: Int {
        switch self {
        case .waiting: return 3
        case .running: return 2
        case .finished: return 1
        case .idle: return 0
        }
    }

    public var displayName: String {
        switch self {
        case .idle: return "空闲"
        case .running: return "正在运行"
        case .waiting: return "等待确认"
        case .finished: return "运行完成"
        }
    }
}
