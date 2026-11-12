// 生成 WTidy 应用图标：蓝紫渐变圆角方块 + 白色 2×2 网格
// 用法: swift scripts/make-icon.swift <输出路径.icns>
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let output = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: "AppIcon.icns")

func renderIcon(size: CGFloat) -> CGImage? {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

    let s = size
    let margin = s * 0.10
    let body = CGRect(x: margin, y: margin, width: s - margin * 2, height: s - margin * 2)
    let radius = s * 0.225

    // 渐变底
    let colors = [
        CGColor(red: 0.32, green: 0.52, blue: 0.96, alpha: 1),
        CGColor(red: 0.16, green: 0.32, blue: 0.80, alpha: 1),
    ] as CFArray
    let grad = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
    ctx.saveGState()
    let bodyPath = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(bodyPath)
    ctx.clip()
    ctx.drawLinearGradient(grad,
                           start: CGPoint(x: s * 0.2, y: s),
                           end: CGPoint(x: s * 0.8, y: 0),
                           options: [])
    // 顶部高光
    let hl = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.25),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(hl, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: s * 0.45), options: [])
    ctx.restoreGState()

    // 2×2 白色网格
    let inset = body.insetBy(dx: body.width * 0.18, dy: body.height * 0.18)
    let gap = inset.width * 0.08
    let cell = (inset.width - gap) / 2
    let cellRadius = cell * 0.22
    for ox in [0.0, 1.0] {
        for oy in [0.0, 1.0] {
            let r = CGRect(x: inset.minX + CGFloat(ox) * (cell + gap),
                           y: inset.minY + CGFloat(oy) * (cell + gap),
                           width: cell, height: cell)
            let p = CGPath(roundedRect: r, cornerWidth: cellRadius, cornerHeight: cellRadius, transform: nil)
            ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.02,
                          color: CGColor(red: 0, green: 0, blue: 0.2, alpha: 0.25))
            ctx.addPath(p)
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fillPath()
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
        }
    }
    return ctx.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// iconset 目录
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

// iconutil 生成 icns
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconsetDir.path, "-o", output.path]
try! proc.run()
proc.waitUntilExit()
guard proc.terminationStatus == 0 else { fatalError("iconutil 失败") }
try? fm.removeItem(at: iconsetDir)
print("图标已生成: \(output.path)")
