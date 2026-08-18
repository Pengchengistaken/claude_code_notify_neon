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

            // 流水的缺口：把灯带连同辉光一起按比例挖暗
            if prefs.marqueeStyle == .stream {
                streamNotch()
            }
        }
        // 缺口用 destinationOut 挖，必须先把上面两层圈进同一个合成组，
        // 否则它会一路挖穿到透明的窗口底
        .compositingGroup()
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
        // 换流动样式会整个换掉缺口层，同理要重新点火
        .onChange(of: prefs.marqueeStyle) { _, _ in armAnimations() }
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

            // 流水样式靠遮罩压暗做流动，不叠白色高光 —— Claude Code 那条线也没有
            if includeMarquee, prefs.marqueeStyle == .sweep {
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

    // MARK: 流水（Claude Code 终端顶部那条线）

    /// 缺口单侧斜坡的长度（pt）
    private static let streamRampPoints: Double = 680
    /// 缺口前进速度（pt/秒）
    private static let streamPointsPerSecond: Double = 1140

    /// Claude Code 正在运行时终端顶部那条绿色流水灯的复刻。
    ///
    /// 逐帧采样那条线量出来的形状（Retina 屏采到的像素值已折算成 pt）：
    ///   · 颜色自始至终不变，只有亮度被整体缩放 —— 每个采样点都是同一个绿 (117,252,76) 的等比暗化
    ///   · 一个压到全黑的缺口匀速扫过，两侧各接约 680pt 的线性斜坡，其余是满亮的平台
    ///   · 缺口约 1140pt/秒 前进（1710pt 宽的终端，1.5 秒扫完一屏）
    ///
    /// 所以这里不叠白光，而是用 destinationOut 按 alpha 把灯带挖暗：alpha 是等比缩放，
    /// 色相分毫不动，彩虹也好黄红绿也好都照原样保留。
    ///
    /// 缺口层必须留在正常的视图树里，不能拿去当 .mask —— SwiftUI 会照常渲染遮罩的内容，
    /// 但不驱动它里面的动画，缺口会定在原地不动（实测转速为 0）。
    private func streamNotch() -> some View {
        GeometryReader { geo in
            // 和彩虹圈同理：rotationEffect 转的是整个视图矩形，得先撑到对角线大小的正方形，
            // 否则转起来四角会露空
            let side = hypot(geo.size.width, geo.size.height)
            let perimeter = 2 * (geo.size.width + geo.size.height)
            AngularGradient(gradient: streamGradient(perimeter: perimeter), center: .center)
                .frame(width: side, height: side)
                .rotationEffect(.degrees(isSpinning ? 360 * prefs.direction.sign : 0))
                .animation(streamAnimation(perimeter: perimeter), value: isSpinning)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .blendMode(.destinationOut)
    }

    /// 缺口放在 0.5：中心不透明（挖得最狠），两侧线性收到全透明（原样不动）。
    /// 端点一律用「透明的白」而不是 Color.clear —— clear 是透明的黑，插值会把中间灰掉。
    private func streamGradient(perimeter: Double) -> Gradient {
        // 缺口的物理尺寸是固定的，所以屏幕越大，它在整圈里占的比例越小
        let ramp = min(0.5, Self.streamRampPoints / max(perimeter, 1))
        return Gradient(stops: [
            .init(color: .white.opacity(0), location: 0),
            .init(color: .white.opacity(0), location: 0.5 - ramp),
            .init(color: .white.opacity(prefs.streamDepth), location: 0.5),
            .init(color: .white.opacity(0), location: 0.5 + ramp),
            .init(color: .white.opacity(0), location: 1),
        ])
    }

    /// 缺口按固定的线速度走，转一圈要多久由这块屏幕的周长决定。
    /// 这里刻意不乘状态倍率：流水的节奏就是 Claude Code 的节奏，
    /// 黄红绿本来已经靠颜色和呼吸区分开了。
    ///
    /// 匀速的是角速度，不是沿边走的线速度 —— 角向渐变扫矩形，边中间慢、拐角快。
    /// 实测在 1710×1107pt 的屏上是 1240～3210px/秒，平均正好落在 2280 上，
    /// 横穿顶边约 1.5 秒，和终端里那条线对得上。想让线速度也严格匀速，
    /// 就得按路径长度参数化（`trim`）逐帧重算路径，为这点差别不值得把 CPU 搭进去。
    private func streamAnimation(perimeter: Double) -> Animation {
        let pointsPerSecond = max(1, Self.streamPointsPerSecond * prefs.speed)
        return .linear(duration: perimeter / pointsPerSecond).repeatForever(autoreverses: false)
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
