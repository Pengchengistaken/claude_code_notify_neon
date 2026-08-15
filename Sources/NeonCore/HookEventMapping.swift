import Foundation

/// Claude Code hook 事件 → 交通灯状态的映射。
///
/// hook 进程写入时会带上原始事件名，app 侧再按当前设置重新推导状态，
/// 这样改设置不需要重装 hook。
public enum HookEventMapping {
    /// 需要删除会话记录的事件
    public static let terminatingEvents: Set<String> = ["SessionEnd"]

    /// 直接忽略、不写状态的事件。
    ///
    /// `SubagentStop` 会在回合结束的 `Stop` **之后**才到（实测晚约 4 秒）。
    /// 如果把它当成「运行中」，刚亮起的绿灯会被立刻打回黄灯，然后一直挂到超时。
    /// 子代理运行期间的状态本来就由 Task 工具的 PreToolUse/PostToolUse 覆盖，
    /// 这个事件没有额外信息，忽略掉最省事。
    public static let ignoredEvents: Set<String> = ["SubagentStop"]

    /// 认识的事件集合。不在这里面的事件一律不写状态 ——
    /// Claude Code 的事件类型比我们用到的多得多，把未知事件当成「运行中」
    /// 只会让灯色莫名其妙。
    public static func isKnown(_ event: String) -> Bool {
        knownEvents.contains(event) || terminatingEvents.contains(event) || ignoredEvents.contains(event)
    }

    private static let knownEvents: Set<String> = [
        "SessionStart", "UserPromptSubmit", "UserPromptExpansion",
        "PreToolUse", "PostToolUse", "PostToolUseFailure", "PostToolBatch",
        "SubagentStart", "PreCompact", "PostCompact",
        "PermissionRequest", "Notification",
        "Stop", "StopFailure",
    ]

    /// - Parameter treatPreToolUseAsWaiting: 参考项目把 PreToolUse 当红灯；
    ///   当前 Claude Code 有精确的 permission_prompt 事件，默认关闭。
    public static func state(
        event: String,
        notificationType: String?,
        treatPreToolUseAsWaiting: Bool = false
    ) -> TrafficState {
        switch event {
        case "SessionStart":
            return .idle
        case "UserPromptSubmit", "UserPromptExpansion":
            return .running
        case "PreToolUse":
            return treatPreToolUseAsWaiting ? .waiting : .running
        case "PostToolUse", "PostToolUseFailure", "PostToolBatch",
             "SubagentStart", "PostCompact", "PreCompact":
            return .running
        case "PermissionRequest":
            return .waiting
        case "Notification":
            return isWaitingNotification(notificationType) ? .waiting : .running
        case "Stop", "StopFailure":
            return .finished
        default:
            return .running
        }
    }

    /// 回合已经结束（上一个事件是 Stop）之后，这个事件该不该改变灯色。
    ///
    /// 回合结束后还会陆续收到一些与"当前该显示什么"无关的事件：
    ///   - `SubagentStop` 会在 Stop 之后几秒才到，会把刚亮的绿灯打回黄灯
    ///   - Claude Code 闲置约 60 秒后会发一条"在等你输入"的 `Notification`，
    ///     会让已经回到彩虹的灯带无端变红并响铃
    ///
    /// 权限询问只可能发生在回合进行中，所以回合结束后只认「开始新一轮」这类事件。
    public static func shouldOverrideFinishedTurn(event: String) -> Bool {
        switch event {
        case "UserPromptSubmit", "SessionStart", "SessionEnd", "PermissionRequest":
            return true
        default:
            return false
        }
    }

    /// Notification 事件里代表"在等用户"的类型；未知类型也当作等待，
    /// 因为 Claude Code 的通知本身就是为了叫人回来看。
    public static func isWaitingNotification(_ type: String?) -> Bool {
        guard let type, !type.isEmpty else { return true }
        switch type {
        case "auth_success", "auth_refresh":
            return false
        default:
            return true
        }
    }
}
