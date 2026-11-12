import AppKit

/// Overlay 的全部绘制状态（矩形均为 AppKit 全局屏幕坐标，由 view 自行转换）
struct OverlayModel {
    /// 布局图标条：每项 { 图标rect, 布局 }（布局用于绘制迷你区域预览）
    var strip: [(rect: CGRect, layout: TidyLayout)] = []
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
        // 展开态：整屏暗纱 + 落点分区
        if let veil = model.veilRect {
            let v = convert(veil)
            NSColor.black.withAlphaComponent(0.18).setFill()
            v.fill()

            for (i, zone) in model.zones.enumerated() {
                let z = convert(zone)
                let hovered = (i == model.hoveredZoneIndex)
                let path = NSBezierPath(roundedRect: z.insetBy(dx: 3, dy: 3), xRadius: 10, yRadius: 10)
                if hovered {
                    NSColor.controlAccentColor.withAlphaComponent(0.34).setFill()
                    path.fill()
                    NSColor.white.withAlphaComponent(0.95).setStroke()
                    path.lineWidth = 3
                } else {
                    NSColor.white.withAlphaComponent(0.07).setFill()
                    path.fill()
                    NSColor.white.withAlphaComponent(0.7).setStroke()
                    path.lineWidth = 2
                }
                path.stroke()
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
                                    showName: Prefs.showLayoutNames)
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
    /// 布局图标尺寸：目标为整条不超过原版的 ~512pt（窄屏自适应缩放）
    static let iconMaxWidth: CGFloat = 110
    static let iconMinWidth: CGFloat = 56
    static let iconAspectRatio: CGFloat = 0.58   // 高/宽
    static let thumbSpacing: CGFloat = 10
    static let stripPadding: CGFloat = 12
    static let stripTopGap: CGFloat = 10
    static let stripHitInset: CGFloat = 6        // 命中外扩，更容易瞄准
}

/// 单个布局图标的绘制（overlay 条 / 定位预览 / 快速布局面板共用，保证视觉一致）。
/// 视觉对齐原版 Layout Icons：蓝色壁纸渐变底 + 网格线 + 深色区域块。
enum LayoutIconRenderer {
    /// 在当前绘图上下文中绘制布局图标。rect 为当前视图坐标系矩形。
    /// flipped：所在视图是否翻转坐标（y 向下）——区域块的 y 映射随之变化。
    static func draw(layout: TidyLayout, in rect: CGRect, flipped: Bool,
                     hovered: Bool = false, showName: Bool = false) {
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

        // 1) 壁纸渐变底（模拟原版默认蓝色壁纸）
        let space = NSColorSpace.deviceRGB
        let grad = NSGradient(colors: [NSColor(red: 0.62, green: 0.78, blue: 0.94, alpha: 1),
                                       NSColor(red: 0.36, green: 0.55, blue: 0.82, alpha: 1),
                                       NSColor(red: 0.22, green: 0.38, blue: 0.68, alpha: 1)],
                              atLocations: [0, 0.55, 1],
                              colorSpace: space)
        // 渐变方向：顶亮底深。翻转视图 angle 90=向上绘制……统一用两点式保证方向
        grad?.draw(from: NSPoint(x: rect.minX, y: rect.maxY),   // 顶（两种坐标系都是视觉顶）
                   to: NSPoint(x: rect.minX, y: rect.minY),
                   options: [])

        // 2) 网格线（cols×rows，细白线）
        let cw = rect.width / CGFloat(layout.cols)
        let ch = rect.height / CGFloat(layout.rows)
        NSColor.white.withAlphaComponent(0.22).setStroke()
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

        // 3) 区域块：深色藏青圆角块 + 淡蓝描边（对齐原版区域单元的凹陷观感）
        for nr in layout.normalizedRects {
            let cellPath = NSBezierPath(roundedRect: cellRect(nr).insetBy(dx: 1.5, dy: 1.5),
                                        xRadius: 4, yRadius: 4)
            NSColor(red: 0.07, green: 0.11, blue: 0.18, alpha: 0.92).setFill()
            cellPath.fill()
            NSColor(red: 0.62, green: 0.75, blue: 0.9, alpha: 0.55).setStroke()
            cellPath.lineWidth = 1
            cellPath.stroke()
        }

        // 悬停增亮（对齐原版：选中图标变亮）
        if hovered {
            NSColor.white.withAlphaComponent(0.16).setFill()
            rect.fill(using: .sourceOver)
        }
        NSGraphicsContext.restoreGraphicsState()

        // 外框
        let border = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        if hovered {
            NSColor.white.withAlphaComponent(0.95).setStroke()
            border.lineWidth = 2
        } else {
            NSColor.white.withAlphaComponent(0.7).setStroke()
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
