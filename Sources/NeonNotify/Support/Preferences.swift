import AppKit
import Combine
import NeonCore
import SwiftUI

/// 灯带在哪些显示器上显示
enum DisplayMode: String, CaseIterable, Identifiable {
    case all
    case primaryOnly
    case exceptPrimary

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "全部显示器"
        case .primaryOnly: return "仅主显示器"
        case .exceptPrimary: return "除主显示器以外"
        }
    }
}

/// 灯带窗口层级
enum StripLevel: String, CaseIterable, Identifiable {
    case aboveAll
    case belowAll

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .aboveAll: return "所有窗口顶部"
        case .belowAll: return "所有窗口底部"
        }
    }

    var windowLevel: NSWindow.Level {
        switch self {
        // .screenSaver 能盖住菜单栏；再 +1 避免被其它同级窗口压住
        case .aboveAll: return NSWindow.Level(NSWindow.Level.screenSaver.rawValue + 1)
        case .belowAll: return NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        }
    }
}

/// 跑马灯流动方向
enum FlowDirection: String, CaseIterable, Identifiable {
    case clockwise
    case counterClockwise

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .clockwise: return "顺时针"
        case .counterClockwise: return "逆时针"
        }
    }

    var sign: Double { self == .clockwise ? 1 : -1 }
}

/// 提示音选择
enum AlertSound: String, CaseIterable, Identifiable {
    case none, ping, glass, submarine, hero, funk, blow, purr

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "静音"
        case .ping: return "Ping"
        case .glass: return "Glass"
        case .submarine: return "Submarine"
        case .hero: return "Hero"
        case .funk: return "Funk"
        case .blow: return "Blow"
        case .purr: return "Purr"
        }
    }

    /// 系统内置音效名，与 /System/Library/Sounds 对应
    var systemSoundName: String? {
        switch self {
        case .none: return nil
        default: return displayName
        }
    }
}

/// 全局偏好设置。UserDefaults 落盘，@Published 驱动所有 SwiftUI 视图刷新。
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults: UserDefaults
    /// 初始化期间不要回写，避免把默认值当成用户设置
    private var isLoading = true

    // MARK: 灯效

    @Published var lightingEnabled: Bool = true { didSet { save(oldValue != lightingEnabled) } }
    @Published var presetID: String = ColorfulPresetOption.colorful.rawValue { didSet { save(oldValue != presetID) } }
    @Published var stripWidth: Double = 6 { didSet { save(oldValue != stripWidth) } }
    @Published var cornerRadius: Double = 28 { didSet { save(oldValue != cornerRadius) } }
    @Published var glow: Double = 1.4 { didSet { save(oldValue != glow) } }
    @Published var speed: Double = 1.0 { didSet { save(oldValue != speed) } }
    // 白色高光叠太多会把彩虹冲成白色，默认只留一点流动感
    @Published var marqueeIntensity: Double = 0.25 { didSet { save(oldValue != marqueeIntensity) } }
    @Published var direction: FlowDirection = .clockwise { didSet { save(oldValue != direction) } }
    @Published var displayMode: DisplayMode = .all { didSet { save(oldValue != displayMode) } }
    @Published var level: StripLevel = .aboveAll { didSet { save(oldValue != level) } }

    // MARK: Claude Code

    @Published var claudeEnabled: Bool = true { didSet { save(oldValue != claudeEnabled) } }
    @Published var treatPreToolUseAsWaiting: Bool = false { didSet { save(oldValue != treatPreToolUseAsWaiting) } }
    @Published var greenHoldSeconds: Double = 6 { didSet { save(oldValue != greenHoldSeconds) } }
    // Stop 事件正常都会来，这个超时只是给「进程被 kill」兜底；
    // 设太长的话一旦漏掉一次 Stop，黄灯会挂很久
    @Published var staleMinutes: Double = 3 { didSet { save(oldValue != staleMinutes) } }
    @Published var confettiEnabled: Bool = true { didSet { save(oldValue != confettiEnabled) } }
    @Published var notificationsEnabled: Bool = true { didSet { save(oldValue != notificationsEnabled) } }
    @Published var waitingSound: AlertSound = .ping { didSet { save(oldValue != waitingSound) } }
    @Published var finishedSound: AlertSound = .glass { didSet { save(oldValue != finishedSound) } }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
        isLoading = false
    }

    // MARK: 读写

    private func load() {
        lightingEnabled = bool("lightingEnabled", default: true)
        presetID = defaults.string(forKey: "presetID") ?? ColorfulPresetOption.colorful.rawValue
        stripWidth = double("stripWidth", default: 6)
        cornerRadius = double("cornerRadius", default: 28)
        glow = double("glow", default: 1.4)
        speed = double("speed", default: 1.0)
        marqueeIntensity = double("marqueeIntensity", default: 0.25)
        direction = FlowDirection(rawValue: defaults.string(forKey: "direction") ?? "") ?? .clockwise
        displayMode = DisplayMode(rawValue: defaults.string(forKey: "displayMode") ?? "") ?? .all
        level = StripLevel(rawValue: defaults.string(forKey: "level") ?? "") ?? .aboveAll

        claudeEnabled = bool("claudeEnabled", default: true)
        treatPreToolUseAsWaiting = bool("treatPreToolUseAsWaiting", default: false)
        greenHoldSeconds = double("greenHoldSeconds", default: 6)
        staleMinutes = double("staleMinutes", default: 3)
        confettiEnabled = bool("confettiEnabled", default: true)
        notificationsEnabled = bool("notificationsEnabled", default: true)
        waitingSound = AlertSound(rawValue: defaults.string(forKey: "waitingSound") ?? "") ?? .ping
        finishedSound = AlertSound(rawValue: defaults.string(forKey: "finishedSound") ?? "") ?? .glass
    }

    private func save(_ changed: Bool) {
        guard !isLoading, changed else { return }
        defaults.set(lightingEnabled, forKey: "lightingEnabled")
        defaults.set(presetID, forKey: "presetID")
        defaults.set(stripWidth, forKey: "stripWidth")
        defaults.set(cornerRadius, forKey: "cornerRadius")
        defaults.set(glow, forKey: "glow")
        defaults.set(speed, forKey: "speed")
        defaults.set(marqueeIntensity, forKey: "marqueeIntensity")
        defaults.set(direction.rawValue, forKey: "direction")
        defaults.set(displayMode.rawValue, forKey: "displayMode")
        defaults.set(level.rawValue, forKey: "level")

        defaults.set(claudeEnabled, forKey: "claudeEnabled")
        defaults.set(treatPreToolUseAsWaiting, forKey: "treatPreToolUseAsWaiting")
        defaults.set(greenHoldSeconds, forKey: "greenHoldSeconds")
        defaults.set(staleMinutes, forKey: "staleMinutes")
        defaults.set(confettiEnabled, forKey: "confettiEnabled")
        defaults.set(notificationsEnabled, forKey: "notificationsEnabled")
        defaults.set(waitingSound.rawValue, forKey: "waitingSound")
        defaults.set(finishedSound.rawValue, forKey: "finishedSound")
    }

    private func bool(_ key: String, default fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }

    private func double(_ key: String, default fallback: Double) -> Double {
        defaults.object(forKey: key) as? Double ?? fallback
    }

    /// 恢复灯效默认值（对齐 Strip Light 的 "Restore Lighting to defaults"）
    func restoreLightingDefaults() {
        presetID = ColorfulPresetOption.colorful.rawValue
        stripWidth = 6
        cornerRadius = 28
        glow = 1.4
        speed = 1.0
        marqueeIntensity = 0.25
        direction = .clockwise
    }
}
