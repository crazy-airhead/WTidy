// 生成 WTidy 应用图标：「归位 · 条带合字标」定稿
// 结构：上排两窗格（左选中 = 实心白；右未选中 = 白玻璃半透明），
//       下排等高条带窗，深蓝 WTidy 字标压在白条上
// 视觉语言与原占位图同源：对角蓝渐变（左上亮 → 右下深）+ 实心白块 + 柔和蓝影，无描边
// 小尺寸（≤64px）走专用简化档：整像素对齐 + 间隙相对加大 + 去字标去投影，防亚像素发糊
// 用法: swift scripts/make-icon.swift <输出路径.icns>
import Foundation
import CoreGraphics
import CoreText
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

/// 系统字体半粗体（PingFang/SF 兜底 Helvetica）
func boldFont(_ size: CGFloat) -> CTFont {
    let base = CTFontCreateUIFontForLanguage(.system, size, nil)
        ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    return CTFontCreateCopyWithSymbolicTraits(base, size, nil, .traitBold, .traitBold) ?? base
}

/// 在给定矩形内居中绘制文本
func drawCenteredText(_ ctx: CGContext, _ text: String,
                      x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,
                      fontSize: CGFloat, ink: CGColor) {
    let attrs = [kCTFontAttributeName: boldFont(fontSize),
                 kCTForegroundColorAttributeName: ink] as CFDictionary
    guard let astr = CFAttributedStringCreate(nil, text as CFString, attrs) else { return }
    let line = CTLineCreateWithAttributedString(astr)
    let b = CTLineGetBoundsWithOptions(line, [.useOpticalBounds])
    ctx.textPosition = CGPoint(x: x + w / 2 - b.width / 2, y: y + h / 2 - b.midY)
    CTLineDraw(line, ctx)
}

/// 文本在设计宽度下的适配字号（以 fontSize=100 的测量宽度线性折算）
func fittedFontSize(_ text: String, targetWidth: CGFloat) -> CGFloat {
    let attrs = [kCTFontAttributeName: boldFont(100)] as CFDictionary
    guard let astr = CFAttributedStringCreate(nil, text as CFString, attrs) else { return 10 }
    let line = CTLineCreateWithAttributedString(astr)
    let width = CTLineGetBoundsWithOptions(line, [.useOpticalBounds]).width
    guard width > 0 else { return 10 }
    return 100 * targetWidth / width
}

func renderIcon(px: Int) -> CGImage? {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: px, height: px,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

    let s = CGFloat(px)
    // 小尺寸专用简化（Apple 小尺寸图标惯例）：整像素对齐、间隙相对加大、
    // 去字标（≤64px 时字宽不足 24px，必糊）、去投影（≤1px 的模糊只成灰雾）。
    // 阈值取 64px：Finder 小图标（16pt@2x=32px）与迷你 Dock 都落在简化档。
    let small = px <= 64
    let margin: CGFloat, bodyR: CGFloat, innerPad: CGFloat, gap: CGFloat
    switch px {
    case ..<32:  margin = 2; bodyR = 3;  innerPad = 2; gap = 2   // 16px：格 3、总高 8，双边缘对称
    case ..<64:  margin = 3; bodyR = 6;  innerPad = 4; gap = 2   // 32px：格 8、总高 18
    case ..<128: margin = 6; bodyR = 12; innerPad = 8; gap = 4   // 64px：格 16、总高 36
    default:     margin = s * 0.0977; bodyR = s * 0.181;         // 大尺寸走标准比例
                 innerPad = s * 0.1323; gap = s * 0.052
    }

    // ---- Big Sur 图标网格：1024 画布上 824 主体 ----
    let body = CGRect(x: margin, y: margin, width: s - margin * 2, height: s - margin * 2)
    let bodyPath = roundedRect(body, radius: bodyR)

    // ---- 背景：对角渐变（与原占位图同源的采样色：左上亮蓝 → 右下深蓝）----
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let background = CGGradient(colorsSpace: space, colors: [
        color(0.49, 0.66, 0.96),   // 左上：亮蓝
        color(0.31, 0.52, 0.90),   // 中段
        color(0.23, 0.44, 0.85),   // 右下：深蓝
    ] as CFArray, locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(background,
                           start: CGPoint(x: body.minX, y: body.maxY),
                           end: CGPoint(x: body.maxX, y: body.minY),
                           options: [])
    ctx.restoreGState()

    // ---- 结构：上排两窗格（等高）+ 下排条带窗（贯通两列）----
    let cell = small ? (body.width - innerPad * 2 - gap) / 2 : (s * 0.54 - gap) / 2
    let x0 = small ? margin + innerPad : s * 0.23
    let stripH = cell          // 条带与窗格等高
    let stripY = small ? margin + innerPad : s * 0.248  // 光学居中（总高 ≈0.54s）
    let rowY = stripY + stripH + gap
    let tileR = small ? max(1, s * 0.055) : s * 0.048

    // 上排左格：选中（实心近白 + 柔和蓝影）
    ctx.saveGState()
    if !small {
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.028,
                      color: color(0.08, 0.20, 0.48, 0.35))
    }
    ctx.addPath(roundedRect(CGRect(x: x0, y: rowY, width: cell, height: cell), radius: tileR))
    ctx.setFillColor(color(0.975, 0.985, 1.0))
    ctx.fillPath()
    ctx.restoreGState()

    // 上排右格：未选中（白玻璃半透明 + 轻投影；小尺寸提高不透明度保对比）
    let rx = x0 + cell + gap
    ctx.saveGState()
    if !small {
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.010), blur: s * 0.024,
                      color: color(0.08, 0.20, 0.48, 0.22))
    }
    ctx.addPath(roundedRect(CGRect(x: rx, y: rowY, width: cell, height: cell), radius: tileR))
    ctx.setFillColor(color(1, 1, 1, small ? 0.52 : 0.38))
    ctx.fillPath()
    ctx.restoreGState()

    // 下排条带窗：实心白（与窗格同材质同高度）
    let stripW = small ? body.width - innerPad * 2 : s * 0.54
    ctx.saveGState()
    if !small {
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.028,
                      color: color(0.08, 0.20, 0.48, 0.35))
    }
    ctx.addPath(roundedRect(CGRect(x: x0, y: stripY, width: stripW, height: stripH), radius: tileR))
    ctx.setFillColor(color(0.975, 0.985, 1.0))
    ctx.fillPath()
    ctx.restoreGState()

    // WTidy 字标：深蓝（取渐变底端色），按条带宽 64% 适配字号；小尺寸不画（必糊成噪点）
    if px >= 128 {
        drawCenteredText(ctx, "WTidy",
                         x: x0, y: stripY, w: stripW, h: stripH,
                         fontSize: fittedFontSize("WTidy", targetWidth: stripW * 0.64),
                         ink: color(0.23, 0.44, 0.85))
    }

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
    if let img = renderIcon(px: px) {
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
