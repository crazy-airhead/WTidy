import CoreGraphics

// MARK: - 坐标换算（纯函数，可单元测试）
//
// AppKit 屏幕坐标：原点在主显示器左下角，y 向上。
// Accessibility (AX) 坐标：原点在主显示器左上角，y 向下。
// 两者以主显示器高度 h 为轴翻转。

enum ScreenGeometry {
    /// AppKit rect → AX rect
    static func axRect(fromNS rect: CGRect, primaryScreenHeight h: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: h - rect.maxY, width: rect.width, height: rect.height)
    }

    /// AX rect → AppKit rect
    static func nsRect(fromAX rect: CGRect, primaryScreenHeight h: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: h - rect.maxY, width: rect.width, height: rect.height)
    }

    static func axPoint(fromNS p: CGPoint, primaryScreenHeight h: CGFloat) -> CGPoint {
        CGPoint(x: p.x, y: h - p.y)
    }

    static func nsPoint(fromAX p: CGPoint, primaryScreenHeight h: CGFloat) -> CGPoint {
        CGPoint(x: p.x, y: h - p.y)
    }
}

// MARK: - 布局引擎（基于 TidyLayout 的归一化区域）

enum SnapEngine {
    /// 归一化区域矩形（原点左上 0..1）→ 屏幕可用区域内的分区矩形（AppKit 全局坐标）。
    /// gap：相邻窗口间隙；每个分区向内收缩 gap/2，再裁剪回屏幕区域。
    static func zoneRects(normalized rects: [CGRect], in screen: CGRect, gap: CGFloat = 0) -> [CGRect] {
        let inset = max(0, gap) / 2
        return rects.map { nr in
            let w = nr.width * screen.width
            let h = nr.height * screen.height
            let x = screen.minX + nr.minX * screen.width
            let top = screen.maxY - nr.minY * screen.height   // nr 原点在左上
            let r = CGRect(x: x, y: top - h, width: w, height: h)
            let i = r.insetBy(dx: inset, dy: inset)
            guard !i.isNull, i.width > 0, i.height > 0 else { return .null }
            return i.intersection(screen)
        }
    }

    /// 计算某布局在某屏幕可用区域内的分区（AppKit 全局坐标）
    static func zoneRects(for layout: TidyLayout, in screen: CGRect, gap: CGFloat = 0) -> [CGRect] {
        zoneRects(normalized: layout.normalizedRects, in: screen, gap: gap)
    }

    /// 点命中了哪个分区（从前往后，避免间隙处命中）
    static func zoneIndex(at point: CGPoint, in zones: [CGRect]) -> Int? {
        zones.firstIndex { !$0.isNull && $0.contains(point) }
    }

    /// 图标内投影选区：光标在布局缩略图内的归一化位置 (nx, ny)（原点左上）
    /// → 折算到布局网格单元 → 命中的区域下标（稀疏网格取最近区域）。
    /// 这是「图标条内瞄准」的核心：比如左右半屏图标，光标偏左高亮左半，偏右高亮右半。
    static func zoneIndexInIcon(nx: CGFloat, ny: CGFloat, layout: TidyLayout) -> Int? {
        guard layout.cols > 0, layout.rows > 0, !layout.regions.isEmpty else { return nil }
        let cx = min(layout.cols, max(1, Int(nx * CGFloat(layout.cols)) + 1))
        let cy = min(layout.rows, max(1, Int(ny * CGFloat(layout.rows)) + 1))
        if let i = layout.regions.firstIndex(where: { $0.contains(cellX: cx, cellY: cy) }) {
            return i
        }
        var best: (index: Int, distance: Int)? = nil
        for (i, r) in layout.regions.enumerated() {
            let d = r.distance(toCellX: cx, cellY: cy)
            if best == nil || d < best!.distance {
                best = (i, d)
            }
        }
        return best?.index
    }

    /// 保持窗口尺寸居中（用于「居中」动作），必要时缩到屏幕内
    static func centeredRect(size: CGSize, in screen: CGRect) -> CGRect {
        var sz = size
        sz.width = min(sz.width, screen.width)
        sz.height = min(sz.height, screen.height)
        return CGRect(x: screen.midX - sz.width / 2,
                      y: screen.midY - sz.height / 2,
                      width: sz.width, height: sz.height).integral
    }

    /// 「最大化」（非全屏）：铺满 visibleFrame
    static func maximizeRect(in screen: CGRect, gap: CGFloat = 0) -> CGRect {
        zoneRects(normalized: [CGRect(x: 0, y: 0, width: 1, height: 1)], in: screen, gap: gap).first ?? screen
    }
}

// MARK: - 恢复位置记忆

/// 记录窗口被吸附前的原始 frame，⌃⌥⌘Z 恢复用。纯值类型，可测试。
struct FrameMemory {
    private(set) var store: [String: CGRect] = [:]

    mutating func remember(key: String, frame: CGRect) {
        store[key] = frame
    }

    mutating func recall(key: String) -> CGRect? {
        store[key]
    }

    mutating func remove(key: String) {
        store.removeValue(forKey: key)
    }
}
