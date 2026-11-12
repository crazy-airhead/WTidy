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

// MARK: - 分屏布局

struct SnapLayout: Equatable {
    enum Kind: Equatable {
        case columns(Int)          // n 等分竖列（2 = 左右半，3 = 三等分）
        case rows(Int)             // n 等分横行（2 = 上下半）
        case grid(cols: Int, rows: Int) // 网格（2x2 = 四分）
        case columnSplit(leftRatio: CGFloat) // 不等双列（2/3+1/3 等）
        case full
    }

    let id: String
    let kind: Kind
    var zoneCount: Int {
        switch kind {
        case .columns(let n): return n
        case .rows(let n): return n
        case .grid(let c, let r): return c * r
        case .columnSplit: return 2
        case .full: return 1
        }
    }

    /// 顶部缩略图条里展示的布局（顺序即展示顺序）
    static let strip: [SnapLayout] = [
        SnapLayout(id: "halves", kind: .columns(2)),        // 左右半
        SnapLayout(id: "vertical", kind: .rows(2)),         // 上下半
        SnapLayout(id: "thirds", kind: .columns(3)),        // 三等分
        SnapLayout(id: "twoThirdsLeft", kind: .columnSplit(leftRatio: 2.0 / 3.0)),
        SnapLayout(id: "twoThirdsRight", kind: .columnSplit(leftRatio: 1.0 / 3.0)),
        SnapLayout(id: "quarters", kind: .grid(cols: 2, rows: 2)),
        SnapLayout(id: "full", kind: .full),
    ]
}

// MARK: - 布局引擎

enum SnapEngine {
    /// 计算某布局在某屏幕可用区域内的所有分区矩形（AppKit 全局坐标）。
    /// gap：相邻窗口间隙；每个分区向内收缩 gap/2，再裁剪回屏幕区域。
    static func zoneRects(for layout: SnapLayout, in screen: CGRect, gap: CGFloat = 0) -> [CGRect] {
        let inset = max(0, gap) / 2
        func clamp(_ r: CGRect) -> CGRect {
            let i = r.insetBy(dx: inset, dy: inset)
            guard !i.isNull, i.width > 0, i.height > 0 else { return .null }
            return i.intersection(screen)
        }

        switch layout.kind {
        case .columns(let n):
            guard n > 0 else { return [] }
            let w = screen.width / CGFloat(n)
            return (0..<n).map { clamp(CGRect(x: screen.minX + w * CGFloat($0), y: screen.minY, width: w, height: screen.height)) }

        case .rows(let n):
            guard n > 0 else { return [] }
            let hgt = screen.height / CGFloat(n)
            return (0..<n).map {
                // rows(0) 是顶行
                CGRect(x: screen.minX, y: screen.maxY - hgt * CGFloat($0 + 1), width: screen.width, height: hgt)
            }.map(clamp)

        case .grid(let c, let r):
            guard c > 0, r > 0 else { return [] }
            let w = screen.width / CGFloat(c)
            let hgt = screen.height / CGFloat(r)
            var rects: [CGRect] = []
            for row in 0..<r {
                for col in 0..<c {
                    rects.append(CGRect(x: screen.minX + w * CGFloat(col),
                                        y: screen.maxY - hgt * CGFloat(row + 1),
                                        width: w, height: hgt))
                }
            }
            return rects.map(clamp)

        case .columnSplit(let leftRatio):
            let w = screen.width * leftRatio
            return [
                clamp(CGRect(x: screen.minX, y: screen.minY, width: w, height: screen.height)),
                clamp(CGRect(x: screen.minX + w, y: screen.minY, width: screen.width - w, height: screen.height)),
            ]

        case .full:
            return [clamp(screen)]
        }
    }

    /// 点命中了哪个分区（从前往后，避免间隙处命中）
    static func zoneIndex(at point: CGPoint, in zones: [CGRect]) -> Int? {
        zones.firstIndex { !$0.isNull && $0.contains(point) }
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

    /// 「最大化」（非全屏）：铺满 visibleFrame，等价 full 布局
    static func maximizeRect(in screen: CGRect, gap: CGFloat = 0) -> CGRect {
        zoneRects(for: SnapLayout(id: "full", kind: .full), in: screen, gap: gap).first ?? screen
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
