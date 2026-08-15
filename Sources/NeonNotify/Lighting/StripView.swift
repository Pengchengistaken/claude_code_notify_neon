import ColorfulX
import NeonCore
import SwiftUI

/// 环绕屏幕一圈的霓虹灯带。
///
/// 三层叠加：
///   1. ColorfulX 动画渐变作底色（配色呼吸）
///   2. 旋转的 AngularGradient 高光（跑马灯流动感）
///   3. 同样内容再模糊一份做辉光，向内外溢出
/// 最后用 `strokeBorder` 的圆角矩形遮罩，只留边框那一圈。
///
/// 动画全部交给 CoreAnimation 的 repeatForever，而不是 TimelineView 每帧重建视图树 ——
/// 后者在全屏尺寸下会让这个纯装饰的 app 常驻 12% CPU。
struct StripView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var store: StatusStore

    /// 驱动跑马灯高光绕圈；置为 true 后由 repeatForever 一直转下去
    @State private var isSpinning = false
    /// 驱动红灯/黄灯的呼吸
    @State private var isBreathing = false

    private var appearance: StripAppearance {
        let preset = ColorfulPresetOption(rawValue: prefs.presetID) ?? .colorful
        guard prefs.claudeEnabled else { return .idle(preset: preset) }
        return StripAppearance.appearance(for: store.effectiveState, preset: preset)
    }

    var body: some View {
        let appearance = appearance
        let width = prefs.stripWidth

        ZStack {
            // 辉光在下：同样的内容模糊一份，向灯带内外溢出。
            // 这里必须用普通叠加 —— 用 .plusLighter 加性叠加会让通道饱和溢出，
            // 整条灯带被压成一片均匀的亮黄色，彩虹就没了。
            // 辉光反正要被模糊掉，用很低的渲染分辨率和帧率画，高光也省掉。
            lightLayer(appearance: appearance, includeMarquee: false, renderScale: 0.15, frameLimit: 15)
                .mask(borderShape(width: width))
                .blur(radius: max(1, prefs.glow * width))
                .opacity(0.8)

            lightLayer(appearance: appearance)
                .mask(borderShape(width: width))
        }
        .opacity(breathOpacity(appearance: appearance))
        .animation(breathAnimation(appearance: appearance), value: isBreathing)
        .animation(transitionAnimation(to: appearance), value: appearance)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        // 必须是 compositingGroup 而不是 drawingGroup：
        // drawingGroup 会把 ColorfulX 的 Metal 内容离屏重新光栅化，颜色会坏掉 ——
        // 整条彩虹灯带被压成一片均匀的亮黄色。compositingGroup 只建立合成边界，
        // 颜色保持正确，同时让下面的混合模式不会溢到透明的窗口背景上。
        .compositingGroup()
        .onAppear(perform: armAnimations)
        // 状态切换会换掉底色视图，持续动画不会自己接上 —— 必须重新点火，
        // 否则灯带切回彩虹后就不转了（颜色定格）。
        .onChange(of: appearance) { _, _ in armAnimations() }
    }

    /// 红灯是"该你操作了"的信号，必须立刻到位。
    /// 用 0.45 秒淡入的话，彩虹和红色会交叠成半秒多的混色，看着像出了故障。
    private func transitionAnimation(to appearance: StripAppearance) -> Animation {
        appearance == .waiting ? .easeOut(duration: 0.1) : .easeInOut(duration: 0.45)
    }

    /// 点燃（或重新点燃）两个 repeatForever 动画。
    /// repeatForever 只在绑定的值发生变化时启动，所以要先归零再置起。
    private func armAnimations() {
        isSpinning = false
        isBreathing = false
        // 整圈彩虹 0° 和 360° 视觉上等价，归零不会看到跳变
        DispatchQueue.main.async {
            isSpinning = true
            isBreathing = true
        }
    }

    /// 底色 + 跑马灯高光
    private func lightLayer(
        appearance: StripAppearance,
        includeMarquee: Bool = true,
        renderScale: Double = 0.5,
        frameLimit: Int = 30
    ) -> some View {
        ZStack {
            if appearance.angularRing {
                // 彩虹：绕一圈的角向渐变，任何时刻整圈都是完整光谱，
                // 不会像色块那样飘到暖色区、跟运行中的黄灯撞色
                rainbowRing(appearance: appearance)
            } else {
                ColorfulView(
                    color: .constant(appearance.colors),
                    speed: .constant(prefs.speed * appearance.speedMultiplier),
                    bias: .constant(0.002),
                    noise: .constant(0),
                    transitionSpeed: .constant(6),
                    frameLimit: .constant(frameLimit),
                    // 灯带只占屏幕边缘一圈，降低渲染分辨率省 GPU
                    renderScale: .constant(renderScale)
                )
            }

            if includeMarquee {
                marqueeHighlight(appearance: appearance)
                    .blendMode(.plusLighter)
                    .opacity(prefs.marqueeIntensity)
            }
        }
        // 把加性混合关在这一层里，否则它会和透明的窗口背景相混，整条灯带会消失
        .compositingGroup()
    }

    /// 整圈的彩虹，慢慢转。比 ColorfulX 的色块便宜得多，也不需要 Metal。
    private func rainbowRing(appearance: StripAppearance) -> some View {
        GeometryReader { geo in
            // rotationEffect 转的是整个视图矩形。屏幕不是正方形，直接转会让四角露空，
            // 所以把渐变层撑到对角线大小的正方形再转。
            let side = hypot(geo.size.width, geo.size.height)
            AngularGradient(colors: appearance.colors, center: .center)
                .frame(width: side, height: side)
                .rotationEffect(.degrees(isSpinning ? 360 * prefs.direction.sign : 0))
                .animation(ringAnimation(appearance: appearance), value: isSpinning)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }

    private func ringAnimation(appearance: StripAppearance) -> Animation {
        // 彩虹整圈转得比高光慢得多，12°/秒 看着刚好
        let degreesPerSecond = max(0.5, 12.0 * prefs.speed * appearance.speedMultiplier)
        return .linear(duration: 360.0 / degreesPerSecond).repeatForever(autoreverses: false)
    }

    /// 绕圈跑的一段亮弧，这是"跑马灯"的来源。
    /// 转一整圈是无缝的，所以直接用 rotationEffect + 线性 repeatForever。
    private func marqueeHighlight(appearance: StripAppearance) -> some View {
        AngularGradient(
            gradient: Gradient(stops: [
                .init(color: .white.opacity(0.0), location: 0.00),
                .init(color: .white.opacity(0.9), location: 0.06),
                .init(color: .white.opacity(0.0), location: 0.22),
                .init(color: .white.opacity(0.0), location: 0.50),
                .init(color: .white.opacity(0.55), location: 0.56),
                .init(color: .white.opacity(0.0), location: 0.72),
                .init(color: .white.opacity(0.0), location: 1.00),
            ]),
            center: .center,
            angle: .zero
        )
        .rotationEffect(.degrees(isSpinning ? 360 * prefs.direction.sign : 0))
        .animation(spinAnimation(appearance: appearance), value: isSpinning)
    }

    private func spinAnimation(appearance: StripAppearance) -> Animation {
        // 45°/秒 为基准，换算成转一圈需要的秒数
        let degreesPerSecond = max(1, 45.0 * prefs.speed * appearance.marqueeMultiplier)
        return .linear(duration: 360.0 / degreesPerSecond).repeatForever(autoreverses: false)
    }

    /// 圆角矩形描边作为遮罩。strokeBorder 是向内描边，灯带不会被屏幕边缘裁掉一半。
    private func borderShape(width: Double) -> some View {
        RoundedRectangle(cornerRadius: prefs.cornerRadius, style: .continuous)
            .strokeBorder(lineWidth: width)
    }

    /// 呼吸：在 1 和 1-amount 之间来回渐变
    private func breathOpacity(appearance: StripAppearance) -> Double {
        guard appearance.breathAmount > 0 else { return 1 }
        return isBreathing ? 1 - appearance.breathAmount : 1
    }

    private func breathAnimation(appearance: StripAppearance) -> Animation? {
        guard appearance.breathAmount > 0 else { return nil }
        return .easeInOut(duration: appearance.breathPeriod / 2).repeatForever(autoreverses: true)
    }
}
