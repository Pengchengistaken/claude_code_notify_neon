// 调试工具：在与 app 相同的透明穿透全屏窗口里，并排试几种撒花布局，
// 定位为什么 ConfettiSwiftUI 的粒子没画出来。
// 用法: swift run strip-probe   （20 秒后自动退出）
import AppKit
import ConfettiSwiftUI
import SwiftUI

private let confettiColors: [Color] = [.red, .orange, .yellow, .green, .mint, .blue, .purple, .pink]

/// A：当前 app 的写法 —— 顶部对齐的 1x1 锚点
private struct VariantA: View {
    @State private var trigger = 0
    var body: some View {
        Color.clear
            .overlay(alignment: .top) {
                Color.clear
                    .frame(width: 1, height: 1)
                    .confettiCannon(
                        trigger: $trigger, num: 40, colors: confettiColors,
                        confettiSize: 12, rainHeight: 600,
                        openingAngle: .degrees(30), closingAngle: .degrees(150),
                        radius: 300, hapticFeedback: false
                    )
            }
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { trigger += 1 } }
    }
}

/// B：炮口直接挂在撑满的 Color.clear 上
private struct VariantB: View {
    @State private var trigger = 0
    var body: some View {
        Color.clear
            .confettiCannon(
                trigger: $trigger, num: 40, colors: confettiColors,
                confettiSize: 12, rainHeight: 600,
                openingAngle: .degrees(30), closingAngle: .degrees(150),
                radius: 300, hapticFeedback: false
            )
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { trigger += 1 } }
    }
}

/// C：锚点是个有实际尺寸的方块
private struct VariantC: View {
    @State private var trigger = 0
    var body: some View {
        Color.clear
            .overlay {
                Color.white.opacity(0.05)
                    .frame(width: 80, height: 80)
                    .confettiCannon(
                        trigger: $trigger, num: 40, colors: confettiColors,
                        confettiSize: 12, rainHeight: 600,
                        openingAngle: .degrees(30), closingAngle: .degrees(150),
                        radius: 300, hapticFeedback: false
                    )
            }
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { trigger += 1 } }
    }
}

/// D：全部用默认参数，触发延迟拉长到 1 秒
private struct VariantD: View {
    @State private var trigger = 0
    var body: some View {
        Color.clear
            .overlay {
                Color.clear
                    .frame(width: 1, height: 1)
                    .confettiCannon(trigger: $trigger, num: 40, hapticFeedback: false)
            }
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { trigger += 1 } }
    }
}

private struct ProbeView: View {
    var body: some View {
        HStack(spacing: 0) {
            VariantA()
            VariantB()
            VariantC()
            VariantD()
        }
        .allowsHitTesting(false)
    }
}

final class ProbeDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else { return }
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(NSWindow.Level.screenSaver.rawValue + 2)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.setFrame(screen.frame, display: false)
        window.contentView = NSHostingView(rootView: ProbeView())
        window.orderFrontRegardless()
        self.window = window

        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { NSApp.terminate(nil) }
    }
}

let app = NSApplication.shared
let delegate = ProbeDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
