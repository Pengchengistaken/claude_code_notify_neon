import Combine
import Foundation
import NeonCore

/// 汇总所有 Claude Code 会话的状态。
///
/// 聚合规则（沿用 claude-code-traffic-light）：红 > 黄 > 绿 > idle。
/// 额外做两件事：绿灯保持若干秒后衰减回 idle；黄灯超时无心跳视为陈旧、忽略。
@MainActor
final class StatusStore: ObservableObject {
    /// 按最近更新排序的会话列表，设置面板用它做自检
    @Published private(set) var sessions: [SessionStatus] = []
    /// 聚合后的最终状态，灯带直接看这个
    @Published private(set) var effectiveState: TrafficState = .idle

    /// 状态发生变化时回调（通知与撒花的触发点），参数为新状态和触发它的会话
    var onStateChange: ((TrafficState, SessionStatus?) -> Void)?

    private let prefs: Preferences
    private var watcher: StatusWatcher?
    private var decayTimer: Timer?
    /// 每个会话最后一次被 Ctrl+C 中断的时间，从对话记录里读出来
    private var lastInterrupt: [String: Date] = [:]
    /// 只在有会话「进行中」时才轮询对话记录，空闲时零开销
    private var interruptTimer: Timer?

    init(prefs: Preferences) {
        self.prefs = prefs
    }

    func start() {
        let watcher = StatusWatcher { [weak self] in
            Task { @MainActor in self?.reload() }
        }
        self.watcher = watcher
        watcher.start()
    }

    func stop() {
        watcher?.stop()
        watcher = nil
        decayTimer?.invalidate()
        decayTimer = nil
        interruptTimer?.invalidate()
        interruptTimer = nil
    }

    /// 重新读取目录并重算聚合状态
    func reload() {
        let now = Date()
        let staleInterval = max(60, prefs.staleMinutes * 60)

        let all = StatusPaths.readAll()
            .sorted { $0.updatedAt > $1.updatedAt }

        sessions = all

        var winner: SessionStatus?
        for session in all {
            let age = now.timeIntervalSince(session.updatedAt)
            let state = resolvedState(for: session, age: age, staleInterval: staleInterval)
            guard state != .idle else { continue }
            if let current = winner {
                let currentState = resolvedState(
                    for: current,
                    age: now.timeIntervalSince(current.updatedAt),
                    staleInterval: staleInterval
                )
                if state.priority > currentState.priority { winner = session }
            } else {
                winner = session
            }
        }

        let newState: TrafficState = winner.map {
            resolvedState(
                for: $0,
                age: now.timeIntervalSince($0.updatedAt),
                staleInterval: staleInterval
            )
        } ?? .idle

        if newState != effectiveState {
            effectiveState = newState
            onStateChange?(newState, winner)
        }

        Self.debugLog(sessions: all, now: now, resolved: newState, staleInterval: staleInterval) { session, age in
            self.resolvedState(for: session, age: age, staleInterval: staleInterval)
        }

        scheduleDecayIfNeeded(state: newState, sessions: all, now: now)
        updateInterruptPolling(state: newState, sessions: all)
    }

    /// Claude Code 没有取消事件，只能盯着对话记录。
    /// 只在灯亮着（running/waiting）时轮询，空闲时把定时器停掉。
    private func updateInterruptPolling(state: TrafficState, sessions: [SessionStatus]) {
        let needsPolling = (state == .running || state == .waiting)
            && sessions.contains { $0.transcriptPath != nil }

        guard needsPolling else {
            interruptTimer?.invalidate()
            interruptTimer = nil
            return
        }
        guard interruptTimer == nil else { return }

        interruptTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkForInterrupts() }
        }
    }

    private func checkForInterrupts() {
        var changed = false
        for session in sessions {
            guard let path = session.transcriptPath,
                  let interrupt = TranscriptInspector.lastInterrupt(atPath: path)
            else { continue }
            if lastInterrupt[session.sessionID] != interrupt {
                lastInterrupt[session.sessionID] = interrupt
                changed = true
            }
        }
        if changed { reload() }
    }

    /// 把落盘的事件按当前设置重新映射，并套用绿灯保持 / 黄灯陈旧规则
    private func resolvedState(for session: SessionStatus, age: TimeInterval, staleInterval: TimeInterval) -> TrafficState {
        // 用户按了 Ctrl+C：中断发生在最后一个 hook 事件之后，说明这一轮已经被掐断了
        if let interrupt = lastInterrupt[session.sessionID], interrupt > session.updatedAt {
            return .idle
        }
        let mapped = HookEventMapping.state(
            event: session.event,
            notificationType: nil,
            treatPreToolUseAsWaiting: prefs.treatPreToolUseAsWaiting
        )
        // Notification 事件的 waiting 判定在 hook 侧已经做过，这里以落盘状态为准
        let base = session.event == "Notification" ? session.state : mapped

        switch base {
        case .finished:
            return age <= prefs.greenHoldSeconds ? .finished : .idle
        case .running, .waiting:
            return age <= staleInterval ? base : .idle
        case .idle:
            return .idle
        }
    }

    /// 绿灯到点、黄灯超时都需要一次主动重算 —— 文件系统不会再有事件了
    private func scheduleDecayIfNeeded(state: TrafficState, sessions: [SessionStatus], now: Date) {
        decayTimer?.invalidate()
        decayTimer = nil

        let staleInterval = max(60, prefs.staleMinutes * 60)
        var deadlines: [TimeInterval] = []
        for session in sessions {
            let age = now.timeIntervalSince(session.updatedAt)
            switch session.state {
            case .finished:
                deadlines.append(prefs.greenHoldSeconds - age)
            case .running, .waiting:
                deadlines.append(staleInterval - age)
            case .idle:
                break
            }
        }

        guard let next = deadlines.filter({ $0 > 0 }).min() else { return }
        decayTimer = Timer.scheduledTimer(withTimeInterval: next + 0.2, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    /// 设 NEONNOTIFY_DEBUG=1 时把每次重算的输入和结论打到 stderr，
    /// 用来排查「灯色和状态文件对不上」这类问题。
    private static let isDebug = ProcessInfo.processInfo.environment["NEONNOTIFY_DEBUG"] == "1"

    private static func debugLog(
        sessions: [SessionStatus],
        now: Date,
        resolved: TrafficState,
        staleInterval: TimeInterval,
        resolver: (SessionStatus, TimeInterval) -> TrafficState
    ) {
        guard isDebug else { return }
        let detail = sessions.map { session -> String in
            let age = now.timeIntervalSince(session.updatedAt)
            return String(
                format: "%@[%@ 落盘=%@ 判定=%@ age=%.1fs]",
                session.sessionID.prefix(8).description,
                session.event,
                session.state.rawValue,
                resolver(session, age).rawValue,
                age
            )
        }.joined(separator: " ")
        NSLog("[NeonNotify] 聚合=\(resolved.rawValue) 会话数=\(sessions.count) \(detail)")
    }

    /// 设置面板的"清空状态"，也用于卸载 hook 后收尾
    func clearAll() {
        for session in sessions {
            StatusPaths.remove(sessionID: session.sessionID)
        }
        reload()
    }
}
