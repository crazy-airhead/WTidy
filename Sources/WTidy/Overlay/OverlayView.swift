import AppKit

/// 拖拽图标条 / 快速布局面板的配色主题（行为页「图标条配色」可选）
enum StripTheme {
    case ink        // 墨蓝（默认）：深藏青底 + 雾蓝块
    case graphite   // 石墨
    case teal       // 青碧
    case violet     // 紫罗兰

    static func at(_ index: Int) -> StripTheme {
        [StripTheme.ink, .graphite, .teal, .violet][max(0, min(3, index))]
    }

    var bgColors: [NSColor] {
        switch self {
        case .ink:     return [NSColor(red: 0.13, green: 0.17, blue: 0.26, alpha: 1),
                               NSColor(red: 0.09, green: 0.12, blue: 0.19, alpha: 1)]
        case .graphite: return [NSColor(red: 0.18, green: 0.18, blue: 0.19, alpha: 1),
                                NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)]
        case .teal:    return [NSColor(red: 0.05, green: 0.17, blue: 0.19, alpha: 1),
                               NSColor(red: 0.03, green: 0.11, blue: 0.13, alpha: 1)]
        case .violet:  return [NSColor(red: 0.16, green: 0.10, blue: 0.25, alpha: 1),
                               NSColor(red: 0.10, green: 0.06, blue: 0.17, alpha: 1)]
        }
    }

    var cellFill: NSColor {
        switch self {
        case .ink:     return NSColor(red: 0.44, green: 0.65, blue: 0.94, alpha: 0.92)
        case .graphite: return NSColor(red: 0.82, green: 0.82, blue: 0.84, alpha: 0.88)
        case .teal:    return NSColor(red: 0.25, green: 0.78, blue: 0.74, alpha: 0.92)
        case .violet:  return NSColor(red: 0.71, green: 0.55, blue: 0.95, alpha: 0.92)
        }
    }

    var cellStroke: NSColor {
        NSColor.white.withAlphaComponent(0.30)
    }

    /// 悬停投影命中的区域块（亮色填充，与压暗的其余块强对比）
    var activeCellFill: NSColor {
        switch self {
        case .ink:     return NSColor(red: 0.95, green: 0.97, blue: 1.00, alpha: 0.97)
        case .graphite: return NSColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.97)
        case .teal:    return NSColor(red: 0.75, green: 1.00, blue: 0.95, alpha: 0.97)
        case .violet:  return NSColor(red: 0.90, green: 0.82, blue: 1.00, alpha: 0.97)
        }
    }

    /// 选中区域的描边（醒目强调色）
    var activeCellStroke: NSColor {
        switch self {
        case .ink:     return NSColor(red: 0.30, green: 0.55, blue: 0.95, alpha: 1)
        case .graphite: return NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1)
        case .teal:    return NSColor(red: 0.10, green: 0.65, blue: 0.60, alpha: 1)
        case .violet:  return NSColor(red: 0.55, green: 0.35, blue: 0.90, alpha: 1)
        }
    }
}

/// Overlay 的全部绘制状态（矩形均为 AppKit 全局屏幕坐标，由 view 自行转换）
struct OverlayModel {
    /// 顶部布局缩略图条：每项 { 图标rect, 布局, 投影命中的区域下标 }
    var strip: [(rect: CGRect, layout: TidyLayout, activeRegion: Int?)] = []
    var hoveredStripIndex: Int? = nil

    /// 展开态：整屏暗纱 + 当前布局分区落点预览
    var veilRect: CGRect? = nil
    var zones: [CGRect] = []
    var hoveredZoneIndex: Int? = nil
}

/// 翻转坐标的绘制视图。
/// 交互对齐原版 Window Tidy：拖动时先只出现紧凑布局图标条；
/// 光标在图标条内完成瞄准（图标内位置投影到布局区域），
/// 选中布局后整屏显示落点预览；松手吸附。
final class OverlayView: NSView {
    var model = OverlayModel() {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // 展开态（屏幕最终选择区）：不加蒙板、不填充——只画边框。
        // 选中的分区 = 粗亮边框（黑外衬 4 + 白线 3）；未选中 = 细暗边框。
        if model.veilRect != nil {
            for (i, zone) in model.zones.enumerated() {
                let z = convert(zone)
                let hovered = (i == model.hoveredZoneIndex)
                let path = NSBezierPath(roundedRect: z.insetBy(dx: 3, dy: 3), xRadius: 10, yRadius: 10)
                if hovered {
                    let outer = NSBezierPath(roundedRect: z.insetBy(dx: 2, dy: 2), xRadius: 10, yRadius: 10)
                    NSColor.black.withAlphaComponent(0.45).setStroke()
                    outer.lineWidth = 4
                    outer.stroke()
                    NSColor.white.withAlphaComponent(0.98).setStroke()
                    path.lineWidth = 3
                    path.stroke()
                } else {
                    let outer = NSBezierPath(roundedRect: z.insetBy(dx: 2, dy: 2), xRadius: 10, yRadius: 10)
                    NSColor.black.withAlphaComponent(0.22).setStroke()
                    outer.lineWidth = 2
                    outer.stroke()
                    NSColor.white.withAlphaComponent(0.45).setStroke()
                    path.lineWidth = 1.5
                    path.stroke()
                }
            }
        }

        drawStrip()
    }

    private func drawStrip() {
        guard !model.strip.isEmpty else { return }
        let rects = model.strip.map { convert($0.rect) }
        let union = rects.reduce(rects[0]) { $0.union($1) }
        let card = union.insetBy(dx: -OverlayMetrics.stripPadding, dy: -OverlayMetrics.stripPadding)

        // 底卡（对齐原版 Background：默认深色 / 桌面壁纸）
        let cardPath = NSBezierPath(roundedRect: card, xRadius: 14, yRadius: 14)
        if Prefs.stripBackground == 1, let wallpaper = wallpaperImage() {
            NSGraphicsContext.saveGraphicsState()
            let clip = NSBezierPath(roundedRect: card, xRadius: 14, yRadius: 14)
            clip.addClip()
            wallpaper.draw(in: card, from: .zero, operation: .sourceOver, fraction: 1)
            NSColor.black.withAlphaComponent(0.45).setFill()
            card.fill(using: .sourceOver)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            NSColor.black.withAlphaComponent(0.58).setFill()
            cardPath.fill()
        }

        for (i, item) in model.strip.enumerated() {
            LayoutIconRenderer.draw(layout: item.layout,
                                    in: rects[i],
                                    flipped: true,   // 本视图翻转坐标
                                    hovered: i == model.hoveredStripIndex,
                                    showName: Prefs.showLayoutNames,
                                    activeRegion: item.activeRegion)
        }
    }

    /// 桌面壁纸缓存（按屏幕 UUID），避免 30Hz 重取
    private static var wallpaperCache: [String: NSImage] = [:]

    private func wallpaperImage() -> NSImage? {
        guard let win = window, let screen = win.screen ?? NSScreen.main else { return nil }
        let uuid = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
        let key = "\(uuid)-\(screen.localizedName)"
        if let cached = Self.wallpaperCache[key] { return cached }
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let image = NSImage(contentsOf: url) else { return nil }
        Self.wallpaperCache[key] = image
        return image
    }

    /// 全局（屏幕）坐标 → 本视图坐标
    private func convert(_ globalRect: CGRect) -> CGRect {
        guard let win = window else { return globalRect }
        let inWindow = win.convertFromScreen(globalRect)
        return self.convert(inWindow, from: nil)
    }
}

enum OverlayMetrics {
    /// 布局图标尺寸：基准 150pt（对齐原版偏好预览中的大图标观感），收缩下限 90pt
    static let iconBaseWidth: CGFloat = 150
    static let iconMinWidth: CGFloat = 90
    static let iconAspectRatio: CGFloat = 0.58   // 高/宽
    static let thumbSpacing: CGFloat = 10
    static let stripPadding: CGFloat = 12
    static let stripTopGap: CGFloat = 10
    static let stripHitInset: CGFloat = 6        // 命中外扩，更容易瞄准
}

/// 单个布局图标的绘制（overlay 条 / 定位预览 / 快速布局面板共用，保证视觉一致）。
/// 两种风格（对齐原版的两处用法）：
/// - .dark：拖拽图标条与快速布局面板——深藏青底 + 白网格 + 白色区域块
/// - .light：设置页缩略图与屏幕位置预览——银蓝壁纸底 + 白网格 + 深色区域块（亮蓝描边）
enum LayoutIconRenderer {
    enum Style {
        case dark, light
    }

    /// 在当前绘图上下文中绘制布局图标。rect 为当前视图坐标系矩形。
    /// flipped：所在视图是否翻转坐标（y 向下）——区域块的 y 映射随之变化。
    /// theme：.dark 风格下的配色主题（行为页「图标条配色」）。
    /// activeRegion：投影命中的区域下标——该区域块以高亮色绘制（「拖到这里了」的即时反馈）。
    static func draw(layout: TidyLayout, in rect: CGRect, flipped: Bool,
                     style: Style = .dark,
                     hovered: Bool = false, showName: Bool = false,
                     theme: StripTheme = .at(Prefs.stripTheme),
                     activeRegion: Int? = nil) {
        NSGraphicsContext.saveGraphicsState()
        let clip = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        clip.addClip()

        func cellRect(_ nr: CGRect) -> CGRect {
            // nr 原点在左上。翻转视图（y 向下）：顶边 = minY + nr.minY*h；
            // 非翻转视图（y 向上，如 NSImage）：顶边 = minY + (1-nr.maxY)*h。
            let y = flipped ? rect.minY + nr.minY * rect.height
                            : rect.minY + (1 - nr.maxY) * rect.height
            return CGRect(x: rect.minX + nr.minX * rect.width,
                          y: y,
                          width: nr.width * rect.width,
                          height: nr.height * rect.height)
        }

        // 1) 底色渐变（视觉顶→底）
        let space = NSColorSpace.deviceRGB
        let colors: [NSColor]
        let locations: [CGFloat]
        switch style {
        case .dark:
            colors = theme.bgColors
            locations = [0, 1]
        case .light:
            colors = [NSColor(red: 0.80, green: 0.87, blue: 0.95, alpha: 1),
                      NSColor(red: 0.52, green: 0.67, blue: 0.86, alpha: 1),
                      NSColor(red: 0.34, green: 0.50, blue: 0.76, alpha: 1)]
            locations = [0, 0.55, 1]
        }
        let grad = NSGradient(colors: colors, atLocations: locations, colorSpace: space)
        grad?.draw(from: NSPoint(x: rect.minX, y: rect.maxY),   // 顶（两种坐标系都是视觉顶）
                   to: NSPoint(x: rect.minX, y: rect.minY),
                   options: [])

        // 2) 网格线（cols×rows，细线）
        let cw = rect.width / CGFloat(layout.cols)
        let ch = rect.height / CGFloat(layout.rows)
        NSColor.white.withAlphaComponent(style == .dark ? 0.28 : 0.40).setStroke()
        let grid = NSBezierPath()
        grid.lineWidth = 0.5
        for c in 1..<layout.cols {
            let x = rect.minX + cw * CGFloat(c)
            grid.move(to: CGPoint(x: x, y: rect.minY))
            grid.line(to: CGPoint(x: x, y: rect.maxY))
        }
        for r in 1..<layout.rows {
            let y = rect.minY + ch * CGFloat(r)
            grid.move(to: CGPoint(x: rect.minX, y: y))
            grid.line(to: CGPoint(x: rect.maxX, y: y))
        }
        grid.stroke()

        // 3) 区域块（定位框内部）：投影命中的区域块高亮成亮色，
        //    其余区域块压暗——图标内部的选中/未选中对比拉满
        for (ri, nr) in layout.normalizedRects.enumerated() {
            let cellPath = NSBezierPath(roundedRect: cellRect(nr).insetBy(dx: 1.5, dy: 1.5),
                                        xRadius: 4, yRadius: 4)
            switch style {
            case .dark:
                if ri == activeRegion {
                    theme.activeCellFill.setFill()
                    theme.activeCellStroke.setStroke()
                } else {
                    var dim = theme.cellFill
                    if activeRegion != nil {
                        dim = dim.withAlphaComponent(dim.alphaComponent * 0.40)   // 其余块压暗
                    }
                    dim.setFill()
                    theme.cellStroke.setStroke()
                }
            case .light:
                NSColor(red: 0.09, green: 0.14, blue: 0.23, alpha: 0.94).setFill()
                NSColor(red: 0.38, green: 0.68, blue: 0.95, alpha: 0.85).setStroke()
            }
            cellPath.lineWidth = 1
            cellPath.fill()
            cellPath.stroke()
        }

        // 悬停选中：不加蒙板，仅边框高亮（内部区域块的点亮由 activeRegion 负责）
        NSGraphicsContext.restoreGraphicsState()

        // 外框
        let border = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        if hovered {
            NSColor.white.withAlphaComponent(0.95).setStroke()
            border.lineWidth = 2
        } else {
            NSColor.white.withAlphaComponent(style == .dark ? 0.7 : 0.55).setStroke()
            border.lineWidth = 1
        }
        border.stroke()

        // 名称标注（Options：「Show layout names on Layout Icons」）
        if showName {
            let bandY = flipped ? rect.minY : rect.maxY - 15
            let band = CGRect(x: rect.minX, y: bandY, width: rect.width, height: 15)
            let bandPath = NSBezierPath(roundedRect: band, xRadius: 6, yRadius: 6)
            NSColor.black.withAlphaComponent(0.55).setFill()
            bandPath.fill()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.95),
            ]
            let text = NSAttributedString(string: layout.name, attributes: attrs)
            let textSize = text.size()
            text.draw(at: CGPoint(x: band.midX - textSize.width / 2, y: band.midY - textSize.height / 2))
        }
    }
}
