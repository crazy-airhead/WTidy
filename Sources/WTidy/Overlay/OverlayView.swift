import AppKit

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

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // 设置页改偏好即时生效：拖拽中 overlay 可见时同步重绘（背景/主题/名称等）
        NotificationCenter.default.addObserver(self, selector: #selector(prefsChanged),
                                               name: .prefsChanged, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func prefsChanged() { needsDisplay = true }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // 展开态（屏幕最终选择区）：不加蒙板、不填充——只画边框。
        // 选中的分区 = 粗亮边框（黑外衬 4 + 白线 3）；未选中 = 细暗边框。
        if model.veilRect != nil {
            for (i, zone) in model.zones.enumerated() {
                let z = convert(zone)
                let hovered = (i == model.hoveredZoneIndex)
                let path = NSBezierPath(roundedRect: z.insetBy(dx: 3, dy: 3),
                                        xRadius: Design.Radius.zone, yRadius: Design.Radius.zone)
                if hovered {
                    let outer = NSBezierPath(roundedRect: z.insetBy(dx: 2, dy: 2),
                                             xRadius: Design.Radius.zone, yRadius: Design.Radius.zone)
                    Design.Color.zoneHoverShadow.setStroke()
                    outer.lineWidth = 4
                    outer.stroke()
                    Design.Color.zoneHoverLine.setStroke()
                    path.lineWidth = 3
                    path.stroke()
                } else {
                    let outer = NSBezierPath(roundedRect: z.insetBy(dx: 2, dy: 2),
                                             xRadius: Design.Radius.zone, yRadius: Design.Radius.zone)
                    Design.Color.zoneIdleShadow.setStroke()
                    outer.lineWidth = 2
                    outer.stroke()
                    Design.Color.zoneIdleLine.setStroke()
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
        // 图标条本体不画底卡/边框（原版语义：「背景」是每个布局图标的背景，不是整条的底）；
        // 每个图标各自铺底：默认背景=主题渐变，「使用桌面壁纸」=本屏壁纸+压暗蒙板
        let wallpaper = Prefs.stripBackground == 1 ? wallpaperImage() : nil
        for (i, item) in model.strip.enumerated() {
            LayoutIconRenderer.draw(layout: item.layout,
                                    in: rects[i],
                                    flipped: true,   // 本视图翻转坐标
                                    hovered: i == model.hoveredStripIndex,
                                    showName: Prefs.showLayoutNames,
                                    activeRegion: item.activeRegion,
                                    wallpaper: wallpaper)
        }
    }

    /// 桌面壁纸缓存（key = 屏幕 UUID + 壁纸路径），避免 30Hz 重取；
    /// 换壁纸后 URL 变化 → key 变化，旧条目自然失效，无需监听系统通知
    private static var wallpaperCache: [String: NSImage] = [:]

    private func wallpaperImage() -> NSImage? {
        guard let win = window, let screen = win.screen ?? NSScreen.main else { return nil }
        let uuid = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        let key = "\(uuid)-\(url.path)"
        if let cached = Self.wallpaperCache[key] { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
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
/// - .dark：拖拽图标条与快速布局面板——主题深底 + 白网格 + 白色区域块；
///   「使用桌面壁纸」时底色换成本屏桌面壁纸（+ stripWallpaperVeil 蒙板）
/// - .light：设置页缩略图与屏幕位置预览——银蓝壁纸底 + 白网格 + 深色区域块（亮蓝描边）
enum LayoutIconRenderer {
    enum Style {
        case dark, light
    }

    /// 在当前绘图上下文中绘制布局图标。rect 为当前视图坐标系矩形。
    /// flipped：所在视图是否翻转坐标（y 向下）——区域块的 y 映射随之变化。
    /// theme：.dark 风格下的配色主题（行为页「图标条配色」）。
    /// activeRegion：投影命中的区域下标——该区域块以高亮色绘制（「拖到这里了」的即时反馈）。
    /// wallpaper：图标条「使用桌面壁纸」时传入——整图缩放铺进图标当底色（+压暗蒙板）；
    /// nil 时 .dark 铺主题渐变、.light 铺浅色壁纸色带。
    static func draw(layout: TidyLayout, in rect: CGRect, flipped: Bool,
                     style: Style = .dark,
                     hovered: Bool = false, showName: Bool = false,
                     theme: StripTheme = .at(Prefs.stripTheme),
                     activeRegion: Int? = nil,
                     wallpaper: NSImage? = nil) {
        NSGraphicsContext.saveGraphicsState()
        let clip = NSBezierPath(roundedRect: rect,
                                xRadius: Design.Radius.icon, yRadius: Design.Radius.icon)
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

        // 1) 底色（视觉顶→底）：壁纸模式整图缩放铺壁纸 + 蒙板；
        //    否则 .dark 用主题底色，.light 用全应用唯一的浅色壁纸色带
        if let wallpaper {
            // 翻转视图必须 respectFlipped:true——默认 draw(in:from:) 在翻转视图里上下颠倒
            // （实测定论：翻转视图 img-default=倒、respectFlipped:true=正；非翻转视图两者皆正）
            wallpaper.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                           respectFlipped: flipped, hints: nil)
            Design.Color.stripWallpaperVeil.setFill()
            rect.fill(using: .sourceOver)
        } else {
            let colors: [NSColor]
            let locations: [CGFloat]
            switch style {
            case .dark:
                colors = theme.bgColors
                locations = [0, 1]
            case .light:
                colors = [Design.Color.wallpaperRampTop, Design.Color.wallpaperRampMid, Design.Color.wallpaperRampBottom]
                locations = Design.Color.wallpaperRampLocations
            }
            let grad = NSGradient(colors: colors, atLocations: locations, colorSpace: NSColorSpace.deviceRGB)
            // 视觉顶→底：翻转视图 minY 是视觉顶，非翻转视图 maxY 是视觉顶
            // （实测：翻转视图 from=minY 才首色在顶；from=maxY 的旧注释「两种坐标系都是视觉顶」是错的）
            let topY = flipped ? rect.minY : rect.maxY
            let bottomY = flipped ? rect.maxY : rect.minY
            grad?.draw(from: NSPoint(x: rect.minX, y: topY),
                       to: NSPoint(x: rect.minX, y: bottomY),
                       options: [])
        }

        // 2) 网格线（cols×rows，细线）
        let cw = rect.width / CGFloat(layout.cols)
        let ch = rect.height / CGFloat(layout.rows)
        (style == .dark ? Design.Color.gridLineDark : Design.Color.gridLineLight).setStroke()
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
        //    其余区域块压暗——图标内部的选中/未选中对比拉满。
        //    .dark 内缩 1.5 固定（拖拽条图标 52–87pt 高，占比 ≤3%）。
        //    .light 的 3pt 是 84pt 参考高度（列表缩略图）的目标值；更小的图标
        //    （定位页预览约 28pt 高）按高度 7% 收缩——绝对内缩会吃掉 40%+ 高度，
        //    区域块「漂浮」在卡片中央，rows=1 布局全部变形（2026-11-13 用户截图实测）。
        let cellInset = style == .dark ? Design.Spacing.cellInsetDark
                                       : min(Design.Spacing.cellInsetLight, rect.height * 0.07)
        for (ri, nr) in layout.normalizedRects.enumerated() {
            let cellPath = NSBezierPath(roundedRect: cellRect(nr).insetBy(dx: cellInset, dy: cellInset),
                                        xRadius: Design.Radius.cell, yRadius: Design.Radius.cell)
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
                Design.Color.cellInkFill.setFill()
                Design.Color.cellAccentStroke.setStroke()
            }
            cellPath.lineWidth = 1
            cellPath.fill()
            cellPath.stroke()
        }

        // 悬停选中：不加蒙板，仅边框高亮（内部区域块的点亮由 activeRegion 负责）
        NSGraphicsContext.restoreGraphicsState()

        // 外框
        let border = NSBezierPath(roundedRect: rect,
                                  xRadius: Design.Radius.icon, yRadius: Design.Radius.icon)
        if hovered {
            Design.Color.focusLine.setStroke()
            border.lineWidth = 2
        } else {
            (style == .dark ? Design.Color.iconBorderDarkIdle : Design.Color.iconBorderLightIdle).setStroke()
            border.lineWidth = 1
        }
        border.stroke()

        // 名称标注（Options：「Show layout names on Layout Icons」）
        if showName {
            let bandH = Design.Spacing.nameBandHeight
            let bandY = flipped ? rect.minY : rect.maxY - bandH
            let band = CGRect(x: rect.minX, y: bandY, width: rect.width, height: bandH)
            let bandPath = NSBezierPath(roundedRect: band,
                                        xRadius: Design.Radius.nameBand, yRadius: Design.Radius.nameBand)
            Design.Color.iconNameBandFill.setFill()
            bandPath.fill()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: Design.Font.iconName,
                .foregroundColor: Design.Color.nameBandText,
            ]
            let text = NSAttributedString(string: layout.name, attributes: attrs)
            let textSize = text.size()
            text.draw(at: CGPoint(x: band.midX - textSize.width / 2, y: band.midY - textSize.height / 2))
        }
    }
}
