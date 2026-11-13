// 生成 WTidy 应用图标：深青蓝渐变 + W 窗口轨迹，两端是吸附落点的窗口砖块
// 概念：W 是窗口被拖动的轨迹，两个波峰是吸附落点——左白右青（命中目标高亮）
// 用法: swift scripts/make-icon.swift <输出路径.icns>
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let output = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: "AppIcon.icns")

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: red, green: green, blue: blue, alpha: alpha)
}

func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// 圆角矩形窗口砖块：主体 + 顶部标题栏
func drawWindowTile(_ ctx: CGContext, rect: CGRect, radius: CGFloat,
                    fill: CGColor, barFill: CGColor, glow: CGColor?) {
    ctx.saveGState()
    if let glow {
        ctx.setShadow(offset: .zero, blur: rect.width * 0.30, color: glow)
    }
    ctx.addPath(roundedRect(rect, radius: radius))
    ctx.setFillColor(fill)
    ctx.fillPath()
    ctx.restoreGState()

    // 标题栏：顶部一条横杠
    let barWidth = rect.width * 0.44
    let barHeight = max(0.75, rect.width * 0.075)
    let bar = CGRect(x: rect.midX - barWidth / 2,
                     y: rect.maxY - rect.height * 0.30,
                     width: barWidth, height: barHeight)
    ctx.addPath(roundedRect(bar, radius: barHeight / 2))
    ctx.setFillColor(barFill)
    ctx.fillPath()
}

func renderIcon(size: CGFloat) -> CGImage? {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

    let s = size
    let margin = s * 0.055
    let body = CGRect(x: margin, y: margin, width: s - margin * 2, height: s - margin * 2)
    let bodyPath = roundedRect(body, radius: s * 0.2237)

    // ---- 背景 ----
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()

    let background = CGGradient(colorsSpace: space, colors: [
        color(0.35, 0.82, 0.93),   // 亮青
        color(0.20, 0.46, 0.88),   // 湛蓝
        color(0.07, 0.09, 0.28),   // 深海军蓝
    ] as CFArray, locations: [0, 0.52, 1])!
    ctx.drawLinearGradient(background,
                           start: CGPoint(x: s * 0.10, y: s * 0.96),
                           end: CGPoint(x: s * 0.90, y: s * 0.04),
                           options: [])

    // 顶部光晕
    let glow = CGGradient(colorsSpace: space, colors: [
        color(0.80, 0.99, 1, 0.20),
        color(0.80, 0.99, 1, 0),
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow,
                           startCenter: CGPoint(x: s * 0.22, y: s * 0.88), startRadius: 0,
                           endCenter: CGPoint(x: s * 0.22, y: s * 0.88), endRadius: s * 0.66,
                           options: [])

    // 底部压暗
    let lowerShade = CGGradient(colorsSpace: space, colors: [
        color(0.03, 0.04, 0.15, 0),
        color(0.03, 0.04, 0.15, 0.24),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(lowerShade,
                           start: CGPoint(x: s * 0.5, y: s * 0.44),
                           end: CGPoint(x: s * 0.5, y: s * 0.06),
                           options: [])
    ctx.restoreGState()

    // 边缘白描边
    ctx.addPath(bodyPath)
    ctx.setStrokeColor(color(1, 1, 1, 0.20))
    ctx.setLineWidth(max(0.75, s * 0.004))
    ctx.strokePath()

    // ---- W 轨迹 ----
    let w = CGMutablePath()
    w.move(to: CGPoint(x: s * 0.245, y: s * 0.665))
    w.addLine(to: CGPoint(x: s * 0.375, y: s * 0.305))
    w.addLine(to: CGPoint(x: s * 0.500, y: s * 0.510))
    w.addLine(to: CGPoint(x: s * 0.625, y: s * 0.305))
    w.addLine(to: CGPoint(x: s * 0.755, y: s * 0.665))

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.022,
                  color: color(0.02, 0.03, 0.12, 0.36))
    ctx.addPath(w)
    ctx.setStrokeColor(color(0.96, 0.985, 1))
    ctx.setLineWidth(s * 0.082)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.restoreGState()

    // ---- 两个窗口砖块（吸附落点）----
    let tile = s * 0.158
    let tileRadius = tile * 0.26
    let leftTile = CGRect(x: s * 0.245 - tile / 2, y: s * 0.665 - tile * 0.34,
                          width: tile, height: tile)
    let rightTile = CGRect(x: s * 0.755 - tile / 2, y: s * 0.665 - tile * 0.34,
                           width: tile, height: tile)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.018,
                  color: color(0.02, 0.03, 0.12, 0.32))
    ctx.addPath(roundedRect(leftTile, radius: tileRadius))
    ctx.setFillColor(color(0.96, 0.985, 1))
    ctx.fillPath()
    ctx.restoreGState()
    // 左砖标题栏
    let barW = tile * 0.44
    let barH = max(0.75, tile * 0.075)
    let leftBar = CGRect(x: leftTile.midX - barW / 2, y: leftTile.maxY - tile * 0.30,
                         width: barW, height: barH)
    ctx.addPath(roundedRect(leftBar, radius: barH / 2))
    ctx.setFillColor(color(0.13, 0.28, 0.52, 0.50))
    ctx.fillPath()

    // 右砖：命中目标，青色 + 发光
    drawWindowTile(ctx, rect: rightTile, radius: tileRadius,
                   fill: color(0.55, 1.0, 0.85),
                   barFill: color(0.04, 0.34, 0.32, 0.60),
                   glow: color(0.50, 1.0, 0.84, 0.75))

    return ctx.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let fm = FileManager.default
let iconsetDir = output.deletingLastPathComponent().appendingPathComponent("WTidy.iconset")
try? fm.removeItem(at: iconsetDir)
try! fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for (name, px) in sizes {
    if let img = renderIcon(size: CGFloat(px)) {
        writePNG(img, to: iconsetDir.appendingPathComponent(name))
    } else {
        fatalError("渲染失败 \(name)")
    }
}

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconsetDir.path, "-o", output.path]
try! proc.run()
proc.waitUntilExit()
guard proc.terminationStatus == 0 else { fatalError("iconutil 失败") }
try? fm.removeItem(at: iconsetDir)
print("图标已生成: \(output.path)")
