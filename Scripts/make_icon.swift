// 生成 AppIcon：深色圆角底 + 一圈彩虹霓虹灯带 + 中间三色交通灯。
// 用法: swift Scripts/make_icon.swift <输出目录>
// 只在图标需要改动时手工跑，产物 Resources/AppIcon.icns 已入库。
import AppKit
import CoreGraphics
import CoreImage
import Foundation

let outputDirectory = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

let size = 1024.0
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: nil,
    width: Int(size),
    height: Int(size),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("无法创建绘图上下文") }

// macOS 图标留白：内容画在 824pt 的圆角方里
let inset = 100.0
let contentRect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let cornerRadius = contentRect.width * 0.2237  // Apple 的 squircle 比例

func roundedPath(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// 底：近黑的深灰，让霓虹显得亮
context.addPath(roundedPath(contentRect, cornerRadius))
context.setFillColor(CGColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1))
context.fillPath()

// 彩虹灯带：沿圆角边框描一圈，用分段的角度渐变近似
let stripWidth = contentRect.width * 0.085
let stripRect = contentRect.insetBy(dx: stripWidth / 2, dy: stripWidth / 2)
let stripRadius = cornerRadius - stripWidth / 2
let center = CGPoint(x: contentRect.midX, y: contentRect.midY)

let rainbow: [CGColor] = [
    CGColor(red: 1.00, green: 0.23, blue: 0.35, alpha: 1),
    CGColor(red: 1.00, green: 0.65, blue: 0.15, alpha: 1),
    CGColor(red: 1.00, green: 0.92, blue: 0.25, alpha: 1),
    CGColor(red: 0.25, green: 0.92, blue: 0.55, alpha: 1),
    CGColor(red: 0.20, green: 0.75, blue: 1.00, alpha: 1),
    CGColor(red: 0.55, green: 0.40, blue: 1.00, alpha: 1),
    CGColor(red: 1.00, green: 0.35, blue: 0.80, alpha: 1),
    CGColor(red: 1.00, green: 0.23, blue: 0.35, alpha: 1),
]

/// 把边框切成很多段，每段按该点相对中心的角度取色，得到"彩虹绕一圈"的效果。
/// 画进传入的上下文，方便单独渲染一份用于模糊的辉光层。
func drawStrip(into target: CGContext, lineWidth: CGFloat, alpha: CGFloat) {
    target.saveGState()
    target.setLineWidth(lineWidth)
    target.setLineCap(.round)

    let path = roundedPath(stripRect, stripRadius)
    var points: [CGPoint] = []
    path.applyWithBlock { element in
        let e = element.pointee
        switch e.type {
        case .moveToPoint, .addLineToPoint:
            points.append(e.points[0])
        case .addQuadCurveToPoint:
            points.append(e.points[0]); points.append(e.points[1])
        case .addCurveToPoint:
            points.append(e.points[0]); points.append(e.points[1]); points.append(e.points[2])
        default:
            break
        }
    }
    guard points.count > 1 else { target.restoreGState(); return }

    // 重采样成密集的点，保证描边连续
    var dense: [CGPoint] = []
    for index in 0..<points.count {
        let a = points[index]
        let b = points[(index + 1) % points.count]
        let steps = max(1, Int(hypot(b.x - a.x, b.y - a.y) / 2))
        for step in 0..<steps {
            let t = CGFloat(step) / CGFloat(steps)
            dense.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
        }
    }

    for index in 0..<dense.count {
        let a = dense[index]
        let b = dense[(index + 1) % dense.count]
        var angle = atan2(a.y - center.y, a.x - center.x)
        if angle < 0 { angle += 2 * .pi }
        let position = angle / (2 * .pi) * CGFloat(rainbow.count - 1)
        let lower = Int(position)
        let upper = min(lower + 1, rainbow.count - 1)
        let t = position - CGFloat(lower)
        let from = rainbow[lower].components ?? [0, 0, 0, 1]
        let to = rainbow[upper].components ?? [0, 0, 0, 1]
        target.setStrokeColor(CGColor(
            red: from[0] + (to[0] - from[0]) * t,
            green: from[1] + (to[1] - from[1]) * t,
            blue: from[2] + (to[2] - from[2]) * t,
            alpha: alpha
        ))
        target.beginPath()
        target.move(to: a)
        target.addLine(to: b)
        target.strokePath()
    }
    target.restoreGState()
}

/// 单独渲染一层灯带并做真高斯模糊，作为向内外溢出的辉光
func makeGlowImage() -> CGImage? {
    guard let layer = CGContext(
        data: nil,
        width: Int(size),
        height: Int(size),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    drawStrip(into: layer, lineWidth: stripWidth * 1.15, alpha: 1.0)
    guard let raw = layer.makeImage() else { return nil }

    let input = CIImage(cgImage: raw)
    guard let filter = CIFilter(name: "CIGaussianBlur") else { return raw }
    filter.setValue(input, forKey: kCIInputImageKey)
    filter.setValue(stripWidth * 0.9, forKey: kCIInputRadiusKey)
    guard let output = filter.outputImage else { return raw }
    let ciContext = CIContext(options: [.workingColorSpace: colorSpace])
    return ciContext.createCGImage(output, from: input.extent)
}

// 辉光在下，实心灯带在上
if let glow = makeGlowImage() {
    context.saveGState()
    context.setAlpha(0.9)
    context.draw(glow, in: CGRect(x: 0, y: 0, width: size, height: size))
    context.restoreGState()
}
drawStrip(into: context, lineWidth: stripWidth, alpha: 1.0)

// 中间的三色交通灯
let lampRadius = contentRect.width * 0.075
let gap = lampRadius * 2.7
let lamps: [(CGColor, CGFloat)] = [
    (CGColor(red: 1.00, green: 0.20, blue: 0.24, alpha: 1), gap),
    (CGColor(red: 1.00, green: 0.78, blue: 0.10, alpha: 1), 0),
    (CGColor(red: 0.16, green: 0.90, blue: 0.45, alpha: 1), -gap),
]
for (color, offset) in lamps {
    let rect = CGRect(
        x: center.x - lampRadius,
        y: center.y + offset - lampRadius,
        width: lampRadius * 2,
        height: lampRadius * 2
    )
    context.setShadow(offset: .zero, blur: lampRadius * 1.1, color: color.copy(alpha: 0.9))
    context.setFillColor(color)
    context.fillEllipse(in: rect)
}
context.setShadow(offset: .zero, blur: 0, color: nil)

guard let image = context.makeImage() else { fatalError("渲染失败") }

// 输出 iconset，再交给 iconutil 打包
let iconset = outputDirectory.appending(path: "AppIcon.iconset", directoryHint: .isDirectory)
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for variant in variants {
    guard let scaled = CGContext(
        data: nil,
        width: variant.pixels,
        height: variant.pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { continue }
    scaled.interpolationQuality = .high
    scaled.draw(image, in: CGRect(x: 0, y: 0, width: variant.pixels, height: variant.pixels))
    guard let output = scaled.makeImage() else { continue }
    let url = iconset.appending(path: "\(variant.name).png", directoryHint: .notDirectory)
    let bitmap = NSBitmapImageRep(cgImage: output)
    guard let data = bitmap.representation(using: .png, properties: [:]) else { continue }
    try data.write(to: url)
}

print(iconset.path)
