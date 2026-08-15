import AppKit
import SwiftUI

/// 覆盖整块屏幕的透明穿透窗口：不接收事件、不抢焦点、跟随所有 Space。
final class OverlayWindow: NSWindow {
    init(screen: NSScreen, level: NSWindow.Level) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        // 灯带是装饰，不该出现在截图/录屏之外的任何交互里
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        self.level = level
        // 用 screen.frame 而不是 visibleFrame，才能盖住菜单栏与 Dock 区域
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
