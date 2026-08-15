import AppKit
import ConfettiSwiftUI
import SwiftUI

/// 运行完成时在屏幕上撒一波彩纸。
///
/// 用一个临时的全屏穿透窗口承载，动画结束后自动关掉，
/// 不给常驻灯带窗口增加负担。
@MainActor
final class ConfettiPresenter {
    private var window: OverlayWindow?
    private var dismissWorkItem: DispatchWorkItem?
    private let duration: TimeInterval = 4.5

    func celebrate(on screen: NSScreen? = NSScreen.main) {
        guard let screen else { return }
        dismiss()

        let window = OverlayWindow(
            screen: screen,
            level: NSWindow.Level(NSWindow.Level.screenSaver.rawValue + 2)
        )
        window.contentView = NSHostingView(rootView: ConfettiOverlay())
        window.orderFrontRegardless()
        self.window = window

        let item = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }

    func dismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        window?.orderOut(nil)
        window?.close()
        window = nil
    }
}

private struct ConfettiOverlay: View {
    @State private var trigger = 0

    var body: some View {
        // 炮口直接挂在撑满屏幕的容器上，从屏幕中心往下撒。
        // 别改成 .overlay(alignment: .top) 套一个 1x1 的锚点 —— 那样一颗粒子都不会画出来。
        Color.clear
            .confettiCannon(
                trigger: $trigger,
                num: 60,
                colors: [.red, .orange, .yellow, .green, .mint, .blue, .purple, .pink],
                confettiSize: 12,
                rainHeight: 1400,
                openingAngle: .degrees(20),
                closingAngle: .degrees(160),
                radius: 520,
                hapticFeedback: false
            )
            .allowsHitTesting(false)
            .ignoresSafeArea()
            .onAppear {
                // ConfettiSwiftUI 只有在它自己的 onAppear 跑完（firstAppear 置真）之后
                // 才会响应 trigger 变化。在这里同步自增会抢在它前面，那一发会被吞掉。
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { trigger += 1 }
            }
    }
}
