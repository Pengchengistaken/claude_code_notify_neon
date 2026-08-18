import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        TabView {
            GeneralSettingsView(prefs: coordinator.prefs)
                .tabItem { Label("通用", systemImage: "gearshape") }

            LightingSettingsView(prefs: coordinator.prefs)
                .tabItem { Label("灯效", systemImage: "light.beacon.max") }

            ClaudeSettingsView(coordinator: coordinator)
                .tabItem { Label("Claude Code", systemImage: "bell.badge") }

            AboutView()
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 520)
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var prefs: Preferences
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section {
                Toggle("开机时自动启动", isOn: $launchAtLogin)
                    .disabled(!LaunchAtLogin.isAvailable)
                    .onChange(of: launchAtLogin) { _, newValue in
                        LaunchAtLogin.isEnabled = newValue
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                if !LaunchAtLogin.isAvailable {
                    Text("需要以打包后的 NeonNotify.app 运行才能设置开机启动。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("灯带显示位置") {
                Picker("显示器", selection: $prefs.displayMode) {
                    ForEach(DisplayMode.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("窗口层级", selection: $prefs.level) {
                    ForEach(StripLevel.allCases) { Text($0.displayName).tag($0) }
                }
                Text("放在所有窗口顶部时灯带会盖住菜单栏，但永远不会拦截鼠标点击。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 300)
    }
}

private struct LightingSettingsView: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Form {
            Section {
                Toggle("开启灯光", isOn: $prefs.lightingEnabled)
                Picker("默认配色", selection: $prefs.presetID) {
                    ForEach(ColorfulPresetOption.allCases) { Text($0.displayName).tag($0.rawValue) }
                }
                Text("这是空闲时的配色。开启 Claude Code 通知后，运行中/等待确认/已完成会临时切换成黄红绿。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("灯带") {
                LabeledSlider(title: "宽度", value: $prefs.stripWidth, range: 1...40, unit: "pt")
                LabeledSlider(title: "屏幕圆角", value: $prefs.cornerRadius, range: 0...80, unit: "pt")
                LabeledSlider(title: "光晕", value: $prefs.glow, range: 0...4, unit: "×")
            }

            Section("动态") {
                LabeledSlider(title: "速度", value: $prefs.speed, range: 0.1...4, unit: "×")
                Picker("流动样式", selection: $prefs.marqueeStyle) {
                    ForEach(MarqueeStyle.allCases) { Text($0.displayName).tag($0) }
                }
                switch prefs.marqueeStyle {
                case .sweep:
                    LabeledSlider(title: "跑马灯强度", value: $prefs.marqueeIntensity, range: 0...1, unit: "")
                case .stream:
                    LabeledSlider(title: "缺口深度", value: $prefs.streamDepth, range: 0...1, unit: "")
                    Text("复刻 Claude Code 运行时终端顶部那条流水灯：颜色不变，一个渐暗的缺口匀速扫过整圈。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker("方向", selection: $prefs.direction) {
                    ForEach(FlowDirection.allCases) { Text($0.displayName).tag($0) }
                }
            }

            Section {
                Button("恢复灯效默认值") { prefs.restoreLightingDefaults() }
            }
        }
        .formStyle(.grouped)
        .frame(height: 460)
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String

    var body: some View {
        HStack {
            Text(title)
            Slider(value: $value, in: range)
            Text(String(format: unit == "pt" ? "%.0f%@" : "%.2f%@", value, unit))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
    }
}

private struct AboutView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "light.beacon.max.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("NeonNotify")
                .font(.title2.bold())
            Text("环绕屏幕的霓虹灯带，同时也是 Claude Code 的交通灯。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Divider().padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text("开源致谢").font(.headline)
                Link("ColorfulX", destination: URL(string: "https://github.com/Lakr233/ColorfulX")!)
                Link("ConfettiSwiftUI", destination: URL(string: "https://github.com/simibac/ConfettiSwiftUI")!)
                Link("SettingsAccess", destination: URL(string: "https://github.com/orchetect/SettingsAccess")!)
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
        .frame(height: 380)
    }
}
