import NeonCore
import SwiftUI

/// Claude Code 通知设置：一键装/卸 hooks、三色行为、实时会话自检。
struct ClaudeSettingsView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject private var prefs: Preferences
    @ObservedObject private var store: StatusStore

    @State private var isInstalled = HookInstaller.isInstalled()
    @State private var hasStalePath = HookInstaller.hasStalePath()
    @State private var banner: Banner?
    @State private var showPreview = false

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        self.prefs = coordinator.prefs
        self.store = coordinator.store
    }

    private struct Banner: Identifiable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

    var body: some View {
        Form {
            Section {
                Toggle("开启 Claude Code 通知", isOn: $prefs.claudeEnabled)
            }

            Section("Hooks") {
                HStack(spacing: 8) {
                    Circle()
                        .fill(isInstalled ? Color.green : Color.secondary)
                        .frame(width: 8, height: 8)
                    Text(installStatusText)
                    Spacer()
                    if isInstalled {
                        Button("卸载 hooks") { uninstall() }
                    } else {
                        Button("安装 hooks") { install() }
                            .buttonStyle(.borderedProminent)
                    }
                }

                if hasStalePath {
                    Label("检测到指向其它位置的旧 hook，app 可能被移动过，请重新安装。",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Text("hooks 写入 ~/.claude/settings.json，改动前会自动备份。**需要重开 Claude Code 会话才会生效。**")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                DisclosureGroup("查看将写入的配置", isExpanded: $showPreview) {
                    ScrollView {
                        Text(HookInstaller.previewJSON())
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 140)
                }

                if let banner {
                    Text(banner.text)
                        .font(.caption)
                        .foregroundStyle(banner.isError ? .red : .green)
                }
            }

            Section("行为") {
                Toggle("完成时撒花", isOn: $prefs.confettiEnabled)
                Toggle("发送系统通知", isOn: $prefs.notificationsEnabled)
                Picker("🔴 等待确认提示音", selection: $prefs.waitingSound) {
                    ForEach(AlertSound.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("🟢 运行完成提示音", selection: $prefs.finishedSound) {
                    ForEach(AlertSound.allCases) { Text($0.displayName).tag($0) }
                }
                LabeledContent("绿灯保持") {
                    Stepper("\(Int(prefs.greenHoldSeconds)) 秒", value: $prefs.greenHoldSeconds, in: 2...60, step: 1)
                }
                LabeledContent("黄灯超时视为空闲") {
                    Stepper("\(Int(prefs.staleMinutes)) 分钟", value: $prefs.staleMinutes, in: 1...120, step: 1)
                }
                Toggle("把 PreToolUse 也当作等待确认", isOn: $prefs.treatPreToolUseAsWaiting)
                Text("默认关闭：当前 Claude Code 有精确的权限询问事件，用它判断红灯更准。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("当前状态") {
                HStack {
                    Text("\(store.effectiveState.emoji) \(store.effectiveState.displayName)")
                        .font(.headline)
                    Spacer()
                    ForEach([TrafficState.running, .waiting, .finished, .idle], id: \.self) { state in
                        Button(state.emoji) { coordinator.preview(state: state) }
                            .help("预览\(state.displayName)")
                    }
                }

                if store.sessions.isEmpty {
                    Text("暂无会话。安装 hooks 并重开一个 Claude Code 会话后，这里会实时显示。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.sessions, id: \.sessionID) { session in
                        HStack {
                            Text(session.state.emoji)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.projectName ?? session.sessionID)
                                    .font(.callout)
                                Text("\(session.event) · \(session.updatedAt.formatted(date: .omitted, time: .standard))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    Button("清空状态记录") { store.clearAll() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 620)
        .onAppear(perform: refreshInstallState)
    }

    private var installStatusText: String {
        isInstalled ? "已安装到 ~/.claude/settings.json" : "未安装"
    }

    private func refreshInstallState() {
        isInstalled = HookInstaller.isInstalled()
        hasStalePath = HookInstaller.hasStalePath()
    }

    private func install() {
        do {
            let backup = try HookInstaller.install()
            let suffix = backup.map { "，已备份到 \($0.lastPathComponent)" } ?? ""
            banner = Banner(text: "安装成功\(suffix)。请重开 Claude Code 会话。", isError: false)
        } catch {
            banner = Banner(text: error.localizedDescription, isError: true)
        }
        refreshInstallState()
    }

    private func uninstall() {
        do {
            let backup = try HookInstaller.uninstall()
            let suffix = backup.map { "，已备份到 \($0.lastPathComponent)" } ?? ""
            banner = Banner(text: "已卸载\(suffix)。", isError: false)
            store.clearAll()
        } catch {
            banner = Banner(text: error.localizedDescription, isError: true)
        }
        refreshInstallState()
    }
}
