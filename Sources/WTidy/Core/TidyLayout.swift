import Foundation
import CoreGraphics

/// 用户可编辑的分屏布局——对齐原版 Window Tidy 的 Layouts 模型：
/// 网格（默认 6×6）+ 一个或多个区域，区域用 1-based 单元坐标 (x1,y1)-(x2,y2)，y1 为顶行。
/// 内置布局只是预置数据，用户可在设置里增删改排序。
/// scope：作用域（-1=所有屏幕，≥0=指定 displayID），对齐原版布局的 "All Screens" 概念。
struct TidyLayout: Codable, Equatable {
    struct Region: Codable, Equatable {
        var x1: Int, y1: Int, x2: Int, y2: Int

        init(_ x1: Int, _ y1: Int, _ x2: Int, _ y2: Int) {
            self.x1 = x1; self.y1 = y1; self.x2 = x2; self.y2 = y2
        }

        func contains(cellX cx: Int, cellY cy: Int) -> Bool {
            (x1...x2).contains(cx) && (y1...y2).contains(cy)
        }

        /// 到某单元的曼哈顿距离（稀疏网格就近选区用）
        func distance(toCellX cx: Int, cellY cy: Int) -> Int {
            let dx = max(max(x1 - cx, 0), cx - x2)
            let dy = max(max(y1 - cy, 0), cy - y2)
            return dx + dy
        }
    }

    var id: String
    var name: String
    var cols: Int
    var rows: Int
    var regions: [Region]
    var scope: Int   // -1 = 所有屏幕（默认）；≥0 = 指定 CGDirectDisplayID

    init(id: String, name: String, cols: Int, rows: Int, regions: [Region], scope: Int = -1) {
        self.id = id
        self.name = name
        self.cols = cols
        self.rows = rows
        self.regions = regions
        self.scope = scope
    }

    /// 兼容旧版持久化 JSON（无 scope 字段时回退 -1）
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        cols = try c.decode(Int.self, forKey: .cols)
        rows = try c.decode(Int.self, forKey: .rows)
        regions = try c.decode([Region].self, forKey: .regions)
        scope = try c.decodeIfPresent(Int.self, forKey: .scope) ?? -1
    }

    /// 归一化区域矩形（原点左上，0..1）——贴屏换算与缩略图共用
    var normalizedRects: [CGRect] {
        let cw = 1.0 / CGFloat(cols)
        let ch = 1.0 / CGFloat(rows)
        return regions.map { r in
            CGRect(x: CGFloat(r.x1 - 1) * cw,
                   y: CGFloat(r.y1 - 1) * ch,
                   width: CGFloat(r.x2 - r.x1 + 1) * cw,
                   height: CGFloat(r.y2 - r.y1 + 1) * ch)
        }
    }

    static func == (lhs: TidyLayout, rhs: TidyLayout) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.cols == rhs.cols
            && lhs.rows == rhs.rows && lhs.regions == rhs.regions
    }

    /// 自动分组（对齐原版 AutoGroupLayouts）：两个同网格布局的区域互不重叠
    /// 且互补合并后不超过网格 → 可合并为一个图标（图标内投影选区）。
    static func groupable(_ a: TidyLayout, _ b: TidyLayout) -> Bool {
        guard a.cols == b.cols, a.rows == b.rows, a.scope == b.scope else { return false }
        let all = a.regions + b.regions
        var occupied = Set<String>()
        for r in all {
            for x in r.x1...r.x2 {
                for y in r.y1...r.y2 {
                    let key = "\(x),\(y)"
                    if occupied.contains(key) { return false }  // 重叠不可分组
                    occupied.insert(key)
                }
            }
        }
        return true
    }

    /// 合并为一个布局（供自动分组），id 取二者拼接以保持可追溯
    static func merged(_ a: TidyLayout, _ b: TidyLayout) -> TidyLayout {
        TidyLayout(id: a.id + "+" + b.id,
                   name: a.name + " / " + b.name,
                   cols: a.cols,
                   rows: a.rows,
                   regions: a.regions + b.regions,
                   scope: a.scope)
    }

    /// 内置布局（顺序即图标条顺序；id 稳定，快捷键依赖它）
    static let builtins: [TidyLayout] = [
        .init(id: "halves",         name: "左右半屏", cols: 2, rows: 1, regions: [.init(1, 1, 1, 1), .init(2, 1, 2, 1)]),
        .init(id: "vertical",       name: "上下半屏", cols: 1, rows: 2, regions: [.init(1, 1, 1, 1), .init(1, 2, 1, 2)]),
        .init(id: "thirds",         name: "三等分",   cols: 3, rows: 1, regions: [.init(1, 1, 1, 1), .init(2, 1, 2, 1), .init(3, 1, 3, 1)]),
        .init(id: "twoThirdsLeft",  name: "左 2/3",   cols: 3, rows: 1, regions: [.init(1, 1, 2, 1)]),
        .init(id: "twoThirdsRight", name: "右 2/3",   cols: 3, rows: 1, regions: [.init(2, 1, 3, 1)]),
        .init(id: "quarters",       name: "四分",     cols: 2, rows: 2, regions: [.init(1, 1, 1, 1), .init(2, 1, 2, 1), .init(1, 2, 1, 2), .init(2, 2, 2, 2)]),
        .init(id: "full",           name: "最大化",   cols: 1, rows: 1, regions: [.init(1, 1, 1, 1)]),
        .init(id: "center",         name: "居中",     cols: 6, rows: 6, regions: [.init(2, 2, 5, 5)]),  // 原版 Centre：(2,2)-(5,5)
    ]
}

/// 布局列表持久化（UserDefaults JSON）；变更后广播 prefsChanged 让快捷键/条即时刷新
enum LayoutStore {
    private static let key = "layoutList"

    static var layouts: [TidyLayout] {
        get {
            if let data = UserDefaults.standard.data(forKey: key),
               let list = try? JSONDecoder().decode([TidyLayout].self, from: data), !list.isEmpty {
                return list
            }
            return TidyLayout.builtins
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: key)
                NotificationCenter.default.post(name: .prefsChanged, object: nil)
            }
        }
    }

    static func reset() { layouts = TidyLayout.builtins }

    static func layout(id: String) -> TidyLayout? {
        layouts.first { $0.id == id }
    }

    /// 图标条/快速布局面板实际展示的布局列表：
    /// 1) 按作用域过滤（-1 所有屏幕 或 匹配指定 displayID）
    /// 2) 自动分组（对齐原版 AutoGroupLayouts）：连续的同网格互补布局合并为一个图标
    static func displayLayouts(for displayID: CGDirectDisplayID?) -> [TidyLayout] {
        var scoped = layouts
        if let display = displayID {
            scoped = scoped.filter { $0.scope == -1 || $0.scope == Int(display) }
        }
        guard Prefs.autoGroupLayouts else { return scoped }

        var mergedList: [TidyLayout] = []
        var index = 0
        while index < scoped.count {
            var current = scoped[index]
            var next = index + 1
            while next < scoped.count, TidyLayout.groupable(current, scoped[next]) {
                current = TidyLayout.merged(current, scoped[next])
                next += 1
            }
            mergedList.append(current)
            index = next
        }
        return mergedList
    }
}
