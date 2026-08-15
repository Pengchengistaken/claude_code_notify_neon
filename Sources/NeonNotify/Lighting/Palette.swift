import ColorfulX
import NeonCore
import SwiftUI

/// 可选的默认配色（空闲时的彩虹灯带），直接复用 ColorfulX 的预设
enum ColorfulPresetOption: String, CaseIterable, Identifiable {
    case colorful, neon, aurora, starry, sunrise, sunset, ocean, love, jelly, spring, summer, autumn, winter

    var id: String { rawValue }

    var preset: ColorfulPreset {
        ColorfulPreset(rawValue: rawValue) ?? .colorful
    }

    var displayName: String {
        switch self {
        case .colorful: return "彩虹"
        case .neon: return "霓虹"
        case .aurora: return "极光"
        case .starry: return "星空"
        case .sunrise: return "日出"
        case .sunset: return "日落"
        case .ocean: return "海洋"
        case .love: return "热恋"
        case .jelly: return "果冻"
        case .spring: return "春"
        case .summer: return "夏"
        case .autumn: return "秋"
        case .winter: return "冬"
        }
    }

    var colors: [Color] {
        // 「彩虹」不用 ColorfulX 的 colorful 预设：那套是 alpha 0.5 的粉彩色，
        // masked 成细灯带后几乎看不出颜色。这里用高饱和的自定义色板。
        if self == .colorful { return Self.vividRainbow }
        // 其余预设也统一转成不透明，半透明会让灯带发灰
        return preset.colors.map { Color(nsColor: $0).opacity(1) }
    }

    /// 「彩虹」用角向渐变而不是 ColorfulX 的随机色块。
    ///
    /// ColorfulX 把颜色当成在平面上游走的色块，灯带只取屏幕最外一圈，
    /// 某些时刻整圈会被一两个暖色块占满 —— 看起来就跟「运行中」的黄灯撞色。
    /// 角向渐变保证任何时刻绕一圈都能看到完整光谱。
    var usesAngularRing: Bool { self == .colorful }

    /// 首尾同色，绕一圈无缝
    static let ringGradient: [Color] = vividRainbow + [vividRainbow[0]]

    static let vividRainbow: [Color] = [
        Color(red: 1.00, green: 0.15, blue: 0.35),
        Color(red: 1.00, green: 0.55, blue: 0.05),
        Color(red: 1.00, green: 0.90, blue: 0.10),
        Color(red: 0.15, green: 0.95, blue: 0.45),
        Color(red: 0.05, green: 0.80, blue: 1.00),
        Color(red: 0.45, green: 0.30, blue: 1.00),
        Color(red: 1.00, green: 0.25, blue: 0.85),
    ]
}

/// 某个交通灯状态对应的完整灯效参数
struct StripAppearance: Equatable {
    var colors: [Color]
    /// true 时底色用角向彩虹渐变而不是 ColorfulX 的色块
    var angularRing: Bool = false
    /// 颜色流动速度倍率
    var speedMultiplier: Double
    /// 跑马灯高光旋转速度倍率
    var marqueeMultiplier: Double
    /// 呼吸幅度，0 表示不呼吸
    var breathAmount: Double
    /// 呼吸周期（秒）
    var breathPeriod: Double

    static func idle(preset: ColorfulPresetOption) -> StripAppearance {
        StripAppearance(
            colors: preset.usesAngularRing ? ColorfulPresetOption.ringGradient : preset.colors,
            angularRing: preset.usesAngularRing,
            speedMultiplier: 1.0,
            marqueeMultiplier: 1.0,
            breathAmount: 0,
            breathPeriod: 4
        )
    }

    /// 🟡 正在运行：琥珀色稳定流动
    static let running = StripAppearance(
        colors: [
            Color(red: 1.00, green: 0.70, blue: 0.00),
            Color(red: 1.00, green: 0.84, blue: 0.31),
            Color(red: 1.00, green: 0.56, blue: 0.00),
            Color(red: 1.00, green: 0.92, blue: 0.70),
        ],
        speedMultiplier: 1.5,
        marqueeMultiplier: 1.8,
        breathAmount: 0.12,
        breathPeriod: 2.4
    )

    /// 🔴 等待确认：红色快速呼吸，最抓眼
    static let waiting = StripAppearance(
        colors: [
            Color(red: 1.00, green: 0.09, blue: 0.27),
            Color(red: 1.00, green: 0.32, blue: 0.32),
            Color(red: 0.84, green: 0.00, blue: 0.00),
            Color(red: 1.00, green: 0.54, blue: 0.50),
        ],
        speedMultiplier: 2.2,
        marqueeMultiplier: 2.6,
        breathAmount: 0.45,
        breathPeriod: 1.1
    )

    /// 🟢 运行完成：绿色扫光
    static let finished = StripAppearance(
        colors: [
            Color(red: 0.00, green: 0.90, blue: 0.46),
            Color(red: 0.41, green: 0.94, blue: 0.68),
            Color(red: 0.00, green: 0.78, blue: 0.32),
            Color(red: 0.73, green: 0.96, blue: 0.79),
        ],
        speedMultiplier: 1.6,
        marqueeMultiplier: 2.2,
        breathAmount: 0.10,
        breathPeriod: 2.0
    )

    static func appearance(for state: TrafficState, preset: ColorfulPresetOption) -> StripAppearance {
        switch state {
        case .idle: return .idle(preset: preset)
        case .running: return .running
        case .waiting: return .waiting
        case .finished: return .finished
        }
    }
}

extension TrafficState {
    /// 菜单与设置面板里用的指示色
    var indicatorColor: Color {
        switch self {
        case .idle: return .secondary
        case .running: return .yellow
        case .waiting: return .red
        case .finished: return .green
        }
    }

    var emoji: String {
        switch self {
        case .idle: return "⚪️"
        case .running: return "🟡"
        case .waiting: return "🔴"
        case .finished: return "🟢"
        }
    }
}
