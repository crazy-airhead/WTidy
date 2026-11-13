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
    /// 每布局激活快捷键（原版 Activation Shortcut；nil = 未设置）
    var activationKeyCode: Int?
    var activationModifiers: Int?

    init(id: String, name: String, cols: Int, rows: Int, regions: [Region], scope: Int = -1,
         activationKeyCode: Int? = nil, activationModifiers: Int? = nil) {
        self.id = id
        self.name = name
        self.cols = cols
        self.rows = rows
        self.regions = regions
        self.scope = scope
        self.activationKeyCode = activationKeyCode
        self.activationModifiers = activationModifiers
    }

    /// 兼容旧版持久化 JSON（无 scope/快捷键字段时回退默认）
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        cols = try c.decode(Int.self, forKey: .cols)
        rows = try c.decode(Int.self, forKey: .rows)
        regions = try c.decode([Region].self, forKey: .regions)
        scope = try c.decodeIfPresent(Int.self, forKey: .scope) ?? -1
        activationKeyCode = try c.decodeIfPresent(Int.self, forKey: .activationKeyCode)
        activationModifiers = try c.decodeIfPresent(Int.self, forKey: .activationModifiers)
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

    /// 内置布局（顺序即图标条顺序；id 稳定，快捷键依赖它）。
    /// 共 8 个：一个布局 = 一套完整分区方案（窄宽/宽窄是各自含两个区域的双区布局）。
    static let builtins: [TidyLayout] = [
        .init(id: "halves",       name: L("左右半屏"),        cols: 2, rows: 1, regions: [.init(1, 1, 1, 1), .init(2, 1, 2, 1)]),
        .init(id: "vertical",     name: L("上下半屏"),        cols: 1, rows: 2, regions: [.init(1, 1, 1, 1), .init(1, 2, 1, 2)]),
        .init(id: "thirds",       name: L("三等分"),          cols: 3, rows: 1, regions: [.init(1, 1, 1, 1), .init(2, 1, 2, 1), .init(3, 1, 3, 1)]),
        .init(id: "narrowWide",   name: L("左 1/3 + 右 2/3"), cols: 3, rows: 1, regions: [.init(1, 1, 1, 1), .init(2, 1, 3, 1)]),
        .init(id: "wideNarrow",   name: L("左 2/3 + 右 1/3"), cols: 3, rows: 1, regions: [.init(1, 1, 2, 1), .init(3, 1, 3, 1)]),
        .init(id: "quarters",     name: L("四分"),            cols: 2, rows: 2, regions: [.init(1, 1, 1, 1), .init(2, 1, 2, 1), .init(1, 2, 1, 2), .init(2, 2, 2, 2)]),
        .init(id: "full",         name: L("最大化"),          cols: 1, rows: 1, regions: [.init(1, 1, 1, 1)]),
        .init(id: "center",       name: L("居中"),            cols: 6, rows: 6, regions: [.init(2, 2, 5, 5)]),  // 原版 Centre：(2,2)-(5,5)
    ]
}

/// 布局列表持久化（UserDefaults JSON）；变更后广播 prefsChanged 让快捷键/条即时刷新
enum LayoutStore {
    private static let key = "layoutList"

    /// 历史迭代中的内置布局名称（46362f7 时代曾拆分为单区域条目，后合并为双区域）。
    /// 用户存储列表可能残留旧 id/旧名条目，id 本地化够不着 → 英文界面夹中文。
    private static let legacyBuiltinNames: Set<String> = ["左 1/3", "右 1/3", "左 2/3", "右 2/3"]

    /// 区域排序（收编迁移时做结构比较用，画区域顺序不影响判定）
    private static func regionOrder(_ a: TidyLayout.Region, _ b: TidyLayout.Region) -> Bool {
        (a.x1, a.y1, a.x2, a.y2) < (b.x1, b.y1, b.x2, b.y2)
    }

    /// 读取时的规范化：
    /// 1) 内置 id 条目——名称实时重译（JSON 存的是保存当时的语言，切语言后不重译会「英文界面夹中文」）；
    /// 2) 未知 id 但「结构恰好等于某内置 + 名称是历史/当前内置默认名」的陈旧条目——收编为该内置
    ///    （换 id+名，保留每布局激活快捷键）；收编后与已有 id 冲突则放弃（防重复）。
    ///    名称是自定义的布局永不收编，避免吞掉用户故意改名的自定义布局。
    private static func canonicalized(_ list: [TidyLayout]) -> [TidyLayout] {
        var result: [TidyLayout] = []
        var takenIds = Set<String>()
        for item in list {
            if let builtin = TidyLayout.builtins.first(where: { $0.id == item.id }) {
                var translated = item
                translated.name = builtin.name   // builtins 名称经 L() 求值，随启动语言
                result.append(translated)
                takenIds.insert(item.id)
                continue
            }
            let structureMatches = TidyLayout.builtins.first {
                $0.cols == item.cols && $0.rows == item.rows
                    && $0.regions.sorted(by: regionOrder) == item.regions.sorted(by: regionOrder)
            }
            let nameIsBuiltin = legacyBuiltinNames.contains(item.name)
                || TidyLayout.builtins.contains { $0.name == item.name }
            if let builtin = structureMatches, nameIsBuiltin, !takenIds.contains(builtin.id) {
                var migrated = item
                migrated.id = builtin.id
                migrated.name = builtin.name
                result.append(migrated)
                takenIds.insert(builtin.id)
                continue
            }
            result.append(item)
            takenIds.insert(item.id)
        }
        return result
    }

    static var layouts: [TidyLayout] {
        get {
            if let data = UserDefaults.standard.data(forKey: key),
               let list = try? JSONDecoder().decode([TidyLayout].self, from: data), !list.isEmpty {
                return canonicalized(list)
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
