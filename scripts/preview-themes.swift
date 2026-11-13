import AppKit

// 主题预览：复刻 LayoutIconRenderer 的 .dark 绘制逻辑，把四套 StripTheme
// 画成一排图标（常规 / 悬停 / 投影命中），输出 PNG 供人工审美评估。
// 用法：swift scripts/preview-themes.swift <out.png> [dark|light]
// 第二参数选底色：dark = 深灰底（模拟深色壁纸/深色外观），light = 浅米灰底（模拟浅色壁纸/浅色外观）

struct Theme {
    let name: String
    let bg: [NSColor]
    let cellFill: NSColor
    let cellStroke: NSColor
    let activeFill: NSColor
    let activeStroke: NSColor
}

let themes: [Theme] = [
    Theme(name: "墨蓝 ink",
          bg: [NSColor(red: 0.13, green: 0.17, blue: 0.26, alpha: 1),
               NSColor(red: 0.09, green: 0.12, blue: 0.19, alpha: 1)],
          cellFill: NSColor(red: 0.44, green: 0.65, blue: 0.94, alpha: 0.92),
          cellStroke: NSColor.white.withAlphaComponent(0.30),
          activeFill: NSColor(red: 0.95, green: 0.97, blue: 1.00, alpha: 0.97),
          activeStroke: NSColor(red: 0.30, green: 0.55, blue: 0.95, alpha: 1)),
    Theme(name: "石墨 graphite",
          bg: [NSColor(red: 0.15, green: 0.15, blue: 0.16, alpha: 1),
               NSColor(red: 0.08, green: 0.08, blue: 0.095, alpha: 1)],
          cellFill: NSColor(red: 0.66, green: 0.66, blue: 0.70, alpha: 0.55),
          cellStroke: NSColor.white.withAlphaComponent(0.30),
          activeFill: NSColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.97),
          activeStroke: NSColor(red: 0.92, green: 0.93, blue: 0.96, alpha: 1)),
    Theme(name: "青碧 teal",
          bg: [NSColor(red: 0.05, green: 0.17, blue: 0.19, alpha: 1),
               NSColor(red: 0.03, green: 0.11, blue: 0.13, alpha: 1)],
          cellFill: NSColor(red: 0.25, green: 0.78, blue: 0.74, alpha: 0.92),
          cellStroke: NSColor.white.withAlphaComponent(0.30),
          activeFill: NSColor(red: 0.75, green: 1.00, blue: 0.95, alpha: 0.97),
          activeStroke: NSColor(red: 0.10, green: 0.65, blue: 0.60, alpha: 1)),
    Theme(name: "紫罗兰 violet",
          bg: [NSColor(red: 0.16, green: 0.10, blue: 0.25, alpha: 1),
               NSColor(red: 0.10, green: 0.06, blue: 0.17, alpha: 1)],
          cellFill: NSColor(red: 0.71, green: 0.55, blue: 0.95, alpha: 0.92),
          cellStroke: NSColor.white.withAlphaComponent(0.30),
          activeFill: NSColor(red: 0.90, green: 0.82, blue: 1.00, alpha: 0.97),
          activeStroke: NSColor(red: 0.55, green: 0.35, blue: 0.90, alpha: 1)),
]

// 归一化区域（原点左上）：左右半屏 / 三分（命中中区） / 2x2 四格（命中右下）
let layouts: [[CGRect]] = [
    [CGRect(x: 0, y: 0, width: 0.5, height: 1), CGRect(x: 0.5, y: 0, width: 0.5, height: 1)],
    [CGRect(x: 0, y: 0, width: 1.0/3, height: 1), CGRect(x: 1.0/3, y: 0, width: 1.0/3, height: 1), CGRect(x: 2.0/3, y: 0, width: 1.0/3, height: 1)],
    [CGRect(x: 0, y: 0, width: 0.5, height: 0.5), CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
     CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5), CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)],
]
let states: [(String, Bool, Int?)] = [("常规", false, nil), ("悬停", true, nil), ("投影命中", false, 1)]

let iconW: CGFloat = 150, iconH: CGFloat = 87
let pad: CGFloat = 24, gap: CGFloat = 16, labelH: CGFloat = 20
let cols = states.count, rows = themes.count
let W = pad * 2 + CGFloat(cols) * (iconW * CGFloat(layouts.count) + gap * CGFloat(layouts.count - 1)) + gap * CGFloat(cols - 1)
let H = pad * 2 + CGFloat(rows) * (iconH + labelH + gap)

let img = NSImage(size: NSSize(width: W, height: H))
img.lockFocus()
// 浅色底取带暖调的米灰（贴近真实浅色壁纸观感），深色底取中性灰
let lightBackdrop = CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "light"
(lightBackdrop ? NSColor(red: 0.88, green: 0.87, blue: 0.84, alpha: 1)
              : NSColor(white: 0.5, alpha: 1)).setFill()
NSRect(x: 0, y: 0, width: W, height: H).fill()

let labelAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 12, weight: .medium),
    .foregroundColor: lightBackdrop ? NSColor(white: 0.25, alpha: 1) : NSColor.white,
]

for (ti, theme) in themes.enumerated() {
    let rowTop = H - pad - CGFloat(ti) * (iconH + labelH + gap)   // NSImage 非翻转，自上而下排
    NSAttributedString(string: theme.name, attributes: labelAttrs)
        .draw(at: NSPoint(x: pad, y: rowTop - labelH - iconH - 4))
    var x = pad
    for (stateName, hovered, active) in states {
        for (li, regions) in layouts.enumerated() {
            let rect = NSRect(x: x, y: rowTop - labelH - iconH, width: iconW, height: iconH)
            let activeRegion = (li == 0) ? nil : active   // 第一个布局不演示命中，保持常规对照
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).addClip()
            let grad = NSGradient(colors: theme.bg, atLocations: [0, 1], colorSpace: .deviceRGB)
            grad?.draw(from: NSPoint(x: rect.minX, y: rect.maxY),
                       to: NSPoint(x: rect.minX, y: rect.minY), options: [])
            NSColor.white.withAlphaComponent(0.28).setStroke()
            let grid = NSBezierPath()
            grid.lineWidth = 0.5
            for c in 1..<6 {
                let gx = rect.minX + rect.width / 6 * CGFloat(c)
                grid.move(to: NSPoint(x: gx, y: rect.minY)); grid.line(to: NSPoint(x: gx, y: rect.maxY))
                let gy = rect.minY + rect.height / 6 * CGFloat(c)
                grid.move(to: NSPoint(x: rect.minX, y: gy)); grid.line(to: NSPoint(x: rect.maxX, y: gy))
            }
            grid.stroke()
            for (ri, nr) in regions.enumerated() {
                let cr = CGRect(x: rect.minX + nr.minX * rect.width,
                                y: rect.minY + nr.minY * rect.height,
                                width: nr.width * rect.width, height: nr.height * rect.height)
                let p = NSBezierPath(roundedRect: cr.insetBy(dx: 1.5, dy: 1.5), xRadius: 4, yRadius: 4)
                if ri == activeRegion {
                    theme.activeFill.setFill(); theme.activeStroke.setStroke()
                } else {
                    var dim = theme.cellFill
                    if activeRegion != nil { dim = dim.withAlphaComponent(dim.alphaComponent * 0.40) }
                    dim.setFill(); theme.cellStroke.setStroke()
                }
                p.lineWidth = 1; p.fill(); p.stroke()
            }
            NSGraphicsContext.restoreGraphicsState()
            let border = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
            if hovered { NSColor.white.withAlphaComponent(0.95).setStroke(); border.lineWidth = 2 }
            else { NSColor.white.withAlphaComponent(0.70).setStroke(); border.lineWidth = 1 }
            border.stroke()
            x += iconW + gap
        }
        NSAttributedString(string: stateName, attributes: labelAttrs)
            .draw(at: NSPoint(x: x - gap - 60, y: rowTop - labelH))
        x += gap - gap  // 状态间隔已在循环内累加
    }
}
img.unlockFocus()

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/themes.png"
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("written: \(out) \(Int(W))x\(Int(H))")
