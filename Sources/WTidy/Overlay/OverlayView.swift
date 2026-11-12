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

        // 底卡
        let cardPath = NSBezierPath(roundedRect: card, xRadius: 14, yRadius: 14)
        NSColor.black.withAlphaComponent(0.58).setFill()
        cardPath.fill()

        for (i, item) in model.strip.enumerated() {
            let r = rects[i]
            let hovered = (i == model.hoveredStripIndex)
            let thumb = NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8)
            if hovered {
                NSColor.controlAccentColor.withAlphaComponent(0.55).setFill()
            } else {
                NSColor.white.withAlphaComponent(0.16).setFill()
            }
            thumb.fill()
            NSColor.white.withAlphaComponent(0.75).setStroke()
            thumb.lineWidth = hovered ? 2 : 1
            thumb.stroke()

            // 迷你区域预览（归一化 → 图标内矩形，注意 y 翻转：nr 原点在左上）
            let inner = r.insetBy(dx: 5, dy: 5)
            for nr in item.layout.normalizedRects {
                let mini = CGRect(x: inner.minX + nr.minX * inner.width,
                                  y: inner.minY + (1 - nr.maxY) * inner.height,
                                  width: nr.width * inner.width,
                                  height: nr.height * inner.height)
                let miniPath = NSBezierPath(roundedRect: mini.insetBy(dx: 1.5, dy: 1.5), xRadius: 3, yRadius: 3)
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
    /// 布局图标尺寸：目标为整条不超过原版的 ~512pt（窄屏自适应缩放）
    static let iconMaxWidth: CGFloat = 110
    static let iconMinWidth: CGFloat = 56
    static let iconAspectRatio: CGFloat = 0.58   // 高/宽
    static let thumbSpacing: CGFloat = 10
    static let stripPadding: CGFloat = 12
    static let stripTopGap: CGFloat = 10
    static let stripHitInset: CGFloat = 6        // 命中外扩，更容易瞄准
}
