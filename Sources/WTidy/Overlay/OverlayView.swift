import AppKit

/// Overlay 的全部绘制状态（矩形均为 AppKit 全局屏幕坐标，由 view 自行转换）
struct OverlayModel {
    /// 顶部布局缩略图条：每项 { 缩略图rect, 其内迷你分区rects }
    var strip: [(rect: CGRect, miniZones: [CGRect])] = []
    var hoveredStripIndex: Int? = nil

    /// 展开态：整屏暗纱 + 当前布局分区
    var veilRect: CGRect? = nil
    var zones: [CGRect] = []
    var hoveredZoneIndex: Int? = nil
}

/// 翻转坐标的绘制视图：整屏分区高亮 + 顶部布局条。
/// 交互模仿原版 Window Tidy：拖动瞬间整屏展开分区，拖到哪个分区哪个高亮，松手吸附。
final class OverlayView: NSView {
    var model = OverlayModel() {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // 展开态：整屏暗纱 + 分区
        if let veil = model.veilRect {
            let v = convert(veil)
            NSColor.black.withAlphaComponent(0.22).setFill()
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
                    NSColor.white.withAlphaComponent(0.08).setFill()
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

        // 底卡
        let cardPath = NSBezierPath(roundedRect: card, xRadius: 16, yRadius: 16)
        NSColor.black.withAlphaComponent(0.58).setFill()
        cardPath.fill()

        for (i, item) in model.strip.enumerated() {
            let r = rects[i]
            let hovered = (i == model.hoveredStripIndex)
            let thumb = NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10)
            if hovered {
                NSColor.controlAccentColor.withAlphaComponent(0.8).setFill()
            } else {
                NSColor.white.withAlphaComponent(0.18).setFill()
            }
            thumb.fill()
            NSColor.white.withAlphaComponent(0.8).setStroke()
            thumb.lineWidth = 1.5
            thumb.stroke()

            // 迷你分区线
            for mini in item.miniZones {
                let m = convert(mini)
                let miniPath = NSBezierPath(roundedRect: m.insetBy(dx: 2, dy: 2), xRadius: 5, yRadius: 5)
                if hovered {
                    NSColor.white.withAlphaComponent(0.92).setFill()
                } else {
                    NSColor.white.withAlphaComponent(0.5).setFill()
                }
                miniPath.fill()
            }
        }
    }

    /// 全局（屏幕）坐标 → 本视图坐标
    private func convert(_ globalRect: CGRect) -> CGRect {
        guard let win = window else { return globalRect }
        let inWindow = win.convertFromScreen(globalRect)
        return self.convert(inWindow, from: nil)
    }
}

enum OverlayMetrics {
    /// 布局缩略图尺寸（约为旧版的两倍，易瞄准；屏幕过窄时自适应缩小）
    static let thumbSize = CGSize(width: 124, height: 78)
    static let thumbSpacing: CGFloat = 14
    static let stripPadding: CGFloat = 14
    static let stripTopGap: CGFloat = 14
}
