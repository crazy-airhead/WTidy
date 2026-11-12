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

/// 翻转坐标的绘制视图：画布局缩略图条 + 分屏分区高亮。
final class OverlayView: NSView {
    var model = OverlayModel() {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // 展开态：暗纱 + 分区
        if let veil = model.veilRect {
            let v = convert(veil)
            NSColor.black.withAlphaComponent(0.16).setFill()
            v.fill()

            for (i, zone) in model.zones.enumerated() {
                let z = convert(zone)
                let hovered = (i == model.hoveredZoneIndex)
                let path = NSBezierPath(roundedRect: z.insetBy(dx: 2, dy: 2), xRadius: 8, yRadius: 8)
                if hovered {
                    NSColor.controlAccentColor.withAlphaComponent(0.38).setFill()
                    path.fill()
                    NSColor.white.withAlphaComponent(0.95).setStroke()
                    path.lineWidth = 2
                    path.stroke()
                } else {
                    NSColor.white.withAlphaComponent(0.45).setStroke()
                    path.lineWidth = 1
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

        // 底卡
        let cardPath = NSBezierPath(roundedRect: card, xRadius: 14, yRadius: 14)
        NSColor.black.withAlphaComponent(0.55).setFill()
        cardPath.fill()

        for (i, item) in model.strip.enumerated() {
            let r = rects[i]
            let hovered = (i == model.hoveredStripIndex)
            let thumb = NSBezierPath(roundedRect: r, xRadius: 7, yRadius: 7)
            if hovered {
                NSColor.controlAccentColor.withAlphaComponent(0.75).setFill()
            } else {
                NSColor.white.withAlphaComponent(0.16).setFill()
            }
            thumb.fill()
            NSColor.white.withAlphaComponent(0.75).setStroke()
            thumb.lineWidth = 1
            thumb.stroke()

            // 迷你分区线
            for mini in item.miniZones {
                let m = convert(mini)
                let miniPath = NSBezierPath(roundedRect: m.insetBy(dx: 1.5, dy: 1.5), xRadius: 4, yRadius: 4)
                if hovered {
                    NSColor.white.withAlphaComponent(0.9).setFill()
                } else {
                    NSColor.white.withAlphaComponent(0.45).setFill()
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
    static let thumbSize = CGSize(width: 68, height: 44)
    static let thumbSpacing: CGFloat = 10
    static let stripPadding: CGFloat = 12
    static let stripTopGap: CGFloat = 10
    static let thumbInnerInset: CGFloat = 6
}
