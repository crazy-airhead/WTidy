import CoreGraphics

/// 图标条几何（纯函数）——拖拽 overlay 与设置页「定位」预览共用同一份计算，
/// 保证「预览即真实」：预览画出来的位置比例就是拖拽时的实际位置。
enum StripGeometry {
    /// 计算图标矩形（点空间，AppKit 坐标，原点在 vf 左下）。
    /// 方向/位置系数/最大宽度/边距均来自「定位」页设置。
    static func iconRects(layoutCount: Int, in vf: CGRect) -> [CGRect] {
        guard layoutCount > 0, vf.width > 0, vf.height > 0 else { return [] }
        let count = CGFloat(layoutCount)
        let margin = CGFloat(Prefs.stripMargin)
        let maxWidth = CGFloat(Prefs.stripMaxWidth)
        let spacing = OverlayMetrics.thumbSpacing
        let pad = OverlayMetrics.stripPadding

        func fit(along extent: CGFloat) -> CGFloat {
            let available = extent - 2 * margin - (count - 1) * spacing
            // 基准 76pt（对齐原版观感）；空间不足时收缩，下限 68pt
            return max(OverlayMetrics.iconMinWidth, min(OverlayMetrics.iconBaseWidth, available / count))
        }

        let vertical = Prefs.stripVertical
        let w = vertical
            ? min(fit(along: maxWidth), vf.height * 0.6)
            : fit(along: min(maxWidth, vf.width))
        let h = w * OverlayMetrics.iconAspectRatio

        let totalW = vertical ? w + 2 * pad : count * w + (count - 1) * spacing + 2 * pad
        let totalH = vertical ? count * h + (count - 1) * spacing + 2 * pad : h + 2 * pad
        let freeW = max(0, vf.width - margin * 2 - totalW)
        let freeH = max(0, vf.height - margin * 2 - totalH)
        let originX = vf.minX + margin + CGFloat(Prefs.stripPosX) * freeW
        let topY = vf.maxY - margin - CGFloat(Prefs.stripPosY) * freeH   // 因子 0=贴顶

        return (0..<layoutCount).map { i in
            if vertical {
                let x = originX + pad
                let y = topY - pad - CGFloat(i) * (h + spacing) - h
                return CGRect(x: x, y: y, width: w, height: h)
            } else {
                let x = originX + pad + CGFloat(i) * (w + spacing)
                let y = topY - pad - h
                return CGRect(x: x, y: y, width: w, height: h)
            }
        }
    }
}
