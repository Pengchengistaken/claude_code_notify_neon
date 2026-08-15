import Foundation
import ServiceManagement

/// 开机启动。
///
/// 计划里提到的 LaunchAtLogin-Legacy 需要内嵌 helper app + Xcode 的 Copy Files
/// 阶段，SwiftPM 脚本打包做不到；本 app 最低要求 macOS 14，直接用 SMAppService
/// 即可，无额外依赖。
enum LaunchAtLogin {
    static var isEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
            } catch {
                NSLog("[NeonNotify] 开机启动设置失败: \(error.localizedDescription)")
            }
        }
    }

    /// 未打包运行（swift run）时 SMAppService 用不了，界面上要禁用开关
    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }
}
