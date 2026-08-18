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

            // 流水的缺口：把灯带连同辉光一起按比例挖暗。
            // 单独拆成一个只吃值类型入参的 View —— 见 StreamNotch 里的说明，
            // 它必须不受 store 每 2 秒轮询对话记录触发的重绘影响
            if prefs.marqueeStyle == .stream {
                StreamNotch(
                    cornerRadius: prefs.cornerRadius,
                    stripWidth: prefs.stripWidth,
                    depth: prefs.streamDepth,
                    speed: prefs.speed,
                    directionSign: prefs.direction.sign
                )
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
        // 流水缺口不在这里管：它自己在 StreamNotch 里点火，跟着灯色重新点火只会让它瞬移回起点。
        .onChange(of: appearance) { _, _ in armAnimations() }
    }

    /// 红灯是"该你操作了"的信号，必须立刻到位。
    /// 用 0.45 秒淡入的话，彩虹和红色会交叠成半秒多的混色，看着像出了故障。
    ///
    /// 其余方向也一样短：彩虹走的是 AngularGradient、黄红绿走的是 ColorfulX，两种视图
    /// 换不过去，只能交叉淡入淡出 —— 淡入时间一长，中间那段就是彩虹和纯色各画一半叠在
    /// 一起。而黄↔红↔绿之间用的是同一个 ColorfulView，颜色由它自己的 transitionSpeed
    /// 接管，本来就不吃这个时长，所以统一压短只会去掉混色，不会牺牲别处的顺滑。
    private func transitionAnimation(to appearance: StripAppearance) -> Animation {
        appearance == .waiting ? .easeOut(duration: 0.1) : .easeInOut(duration: 0.15)
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
                RainbowRing(
                    colors: appearance.colors,
                    directionSign: prefs.direction.sign,
                    degreesPerSecond: max(0.5, 12.0 * prefs.speed * appearance.speedMultiplier)
                )
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

/// 流水的缺口：一段全黑的窗口沿灯带匀速绕圈，把灯带连同辉光一起挖暗。
///
/// Claude Code 正在运行时终端顶部那条绿色流水灯的复刻。逐帧采样量出来的形状是：
/// 颜色自始至终不变，只有亮度被整体缩放；一个压到全黑的缺口匀速扫过；约 1140pt/秒。
/// 所以这里不叠白光，而是用 `destinationOut` 按 alpha 挖暗 —— alpha 是等比缩放，
/// 色相分毫不动，彩虹也好黄红绿也好都原样保留。
///
/// **为什么单独拆成一个 View。** 缺口要靠 `repeatForever` 一直跑，而 `StatusStore`
/// 每 2 秒轮询一次对话记录（检测 Ctrl+C 中断），每次都会让 `StripView` 重绘。
/// 缺口留在 `StripView` 里时，重绘会打断正在跑的 `repeatForever`：实测缺口每次只来得及
/// 扫完顶边（约 1.5 秒）就被打回起点，右边、底边、左边根本轮不到 —— 四条边里只有顶边
/// 见得到黑块。拆成只吃值类型入参的独立 View 之后，这些入参不随轮询改变，
/// SwiftUI 就不会重新求值它的 body，动画才跑得完整整一圈。
///
/// **动画只能用 `trim`，不能用 `rotationEffect`。** 这一层带 `.blendMode`，
/// SwiftUI 为了做混合会把它离屏光栅化，里面的旋转动画不被 CoreAnimation 驱动 ——
/// 逐帧互相关实测位移恒为 0，缺口一动不动钉在 `rotationEffect == 0` 的位置
/// （角向渐变的 0.5 落在 9 点钟方向，所以停在左边缘正中，看着就像「跑一半断了」）。
/// 这和 `.mask()` 里动画不跑是同一类坑。`trim` 不吃这一套，而且它按路径真实弧长
/// 参数化，线性动画就是严格匀速绕圈，四条边和四个角一视同仁。
private struct StreamNotch: View {
    let cornerRadius: Double
    let stripWidth: Double
    let depth: Double
    let speed: Double
    let directionSign: Double

    /// 缺口挖到全黑那一段的弧长（pt）。
    /// 要比 `edgeSoften` 宽出好几倍，否则模糊会把中心一起糊亮，缺口就不是全黑了。
    private static let coreArc: Double = 520
    /// 首尾软化的宽度（pt），靠模糊做出来。实测斜坡约 150pt。
    ///
    /// 原版那条线是两侧各约 680pt 的线性斜坡，比这里柔得多。试过往那个方向靠
    /// （模糊 150pt、核心跟着涨到 760pt，量出来斜坡 446pt），实际看着反而不好看：
    /// 斜坡一宽，整个缺口就要占掉近三成周长，暗的部分太多。所以这里刻意留得比原版硬。
    private static let edgeSoften: Double = 60
    /// 缺口前进速度（pt/秒）
    private static let pointsPerSecond: Double = 1140

    @State private var isStreaming = false

    var body: some View {
        GeometryReader { geo in
            let perimeter = 2 * (geo.size.width + geo.size.height)
            let half = min(0.5, Self.coreArc / 2 / max(perimeter, 1))
            let lap = (isStreaming ? 1.0 : 0.0) * directionSign
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            // 笔画要远粗于灯带，也要远粗于模糊半径：这样灯带整个落在粗带正中间，
            // 模糊只糊掉首尾两端，不会把挖暗的深浅一起摊薄。
            // （模糊是保总量的，摊薄过一次，缺口的峰值 alpha 掉到千分之一，直接看不见。）
            let thickness = max(stripWidth * 6, Self.edgeSoften * 6)

            ZStack {
                // `trim` 的值超出 0...1 是钳到边界而不是取模，缺口压在路径首尾接缝上时，
                // 单独一份只画得出接缝这一侧的半个。错开整整一圈的副本补上另一半，
                // 而且 -1 和 +1 两侧都得有 —— repeatForever 每跑完一圈会把进度从 1 弹回 0，
                // 只放一侧的话，弹回去那一瞬缺口就只剩半个宽度。
                ForEach([-1.0, 0.0, 1.0], id: \.self) { base in
                    shape
                        .trim(from: CGFloat(base + lap - half), to: CGFloat(base + lap + half))
                        .stroke(Color.white.opacity(depth), lineWidth: thickness)
                }
            }
            .animation(animation(perimeter: perimeter), value: isStreaming)
            .blur(radius: Self.edgeSoften)
        }
        .blendMode(.destinationOut)
        .onAppear(perform: arm)
        // 方向和速度换掉的是动画本身，得重新点火才生效
        .onChange(of: directionSign) { _, _ in arm() }
        .onChange(of: speed) { _, _ in arm() }
    }

    /// repeatForever 只在绑定值变化时启动，所以要先归零再置起。
    private func arm() {
        isStreaming = false
        DispatchQueue.main.async { isStreaming = true }
    }

    /// 缺口按固定的线速度绕圈，转一圈要多久由这块屏幕的周长决定。
    /// 刻意不乘状态倍率：流水的节奏就是 Claude Code 的节奏，
    /// 黄红绿本来已经靠颜色和呼吸区分开了。
    private func animation(perimeter: Double) -> Animation {
        let speed = max(1, Self.pointsPerSecond * self.speed)
        return .linear(duration: perimeter / speed).repeatForever(autoreverses: false)
    }
}

/// 空闲时的彩虹：绕一圈的角向渐变，慢慢转。
/// 任何时刻整圈都是完整光谱，不会像 ColorfulX 的色块那样飘到暖色区、跟运行中的黄灯撞色。
///
/// **为什么单独拆成一个 View。** 和 `StreamNotch` 同一个原因：这一圈被
/// `.mask(borderShape)` 和 `.compositingGroup()` 包着，`repeatForever` 一旦被外层重绘
/// 打断就再也接不上，整圈颜色定格 —— 实测每个点位的色相 11 秒里只挪了 0.6°，
/// 按 12°/秒 本该扫过约 130°。看上去就是「彩虹不流动，只有黑色缺口在动」。
/// 拆成只吃值类型入参的独立 View 之后，外层怎么重绘都不会让它重新求值，动画才转得下去。
private struct RainbowRing: View {
    let colors: [Color]
    let directionSign: Double
    let degreesPerSecond: Double

    @State private var isSpinning = false

    var body: some View {
        GeometryReader { geo in
            // rotationEffect 转的是整个视图矩形。屏幕不是正方形，直接转会让四角露空，
            // 所以把渐变层撑到对角线大小的正方形再转。
            let side = hypot(geo.size.width, geo.size.height)
            AngularGradient(colors: colors, center: .center)
                .frame(width: side, height: side)
                .rotationEffect(.degrees(isSpinning ? 360 * directionSign : 0))
                .animation(
                    .linear(duration: 360.0 / max(0.5, degreesPerSecond))
                        .repeatForever(autoreverses: false),
                    value: isSpinning
                )
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .onAppear(perform: arm)
        // 换方向或速度就是换掉动画本身，得重新点火才生效
        .onChange(of: directionSign) { _, _ in arm() }
        .onChange(of: degreesPerSecond) { _, _ in arm() }
    }

    /// repeatForever 只在绑定值变化时启动，所以要先归零再置起。
    /// 整圈彩虹 0° 和 360° 视觉上等价，归零不会看到跳变。
    private func arm() {
        isSpinning = false
        DispatchQueue.main.async { isSpinning = true }
    }
}
