import Foundation
import CoreGraphics
import Carbon.HIToolbox

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
    /// 每区域快捷键（regions 下标 → 组合）：按下直接把前台窗口吸到该区域，跳过投影选区。
    /// 布局级快捷键已删（2026-11-13 用户定案：只要区域级）——旧 JSON 里的该字段由 Codable 静默忽略
    var regionHotkeys: [Int: RegionHotkey]

    /// 区域快捷键组合（keyCode 用 Carbon 键码；modifiers 为 Carbon 修饰键位掩码）
    struct RegionHotkey: Codable, Equatable {
        var keyCode: Int
        var modifiers: Int
    }

    init(id: String, name: String, cols: Int, rows: Int, regions: [Region], scope: Int = -1,
         regionHotkeys: [Int: RegionHotkey] = [:]) {
        self.id = id
        self.name = name
        self.cols = cols
        self.rows = rows
        self.regions = regions
        self.scope = scope
        self.regionHotkeys = regionHotkeys
    }

    /// 兼容旧版持久化 JSON（无 scope/regionHotkeys 字段时回退默认）
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        cols = try c.decode(Int.self, forKey: .cols)
        rows = try c.decode(Int.self, forKey: .rows)
        regions = try c.decode([Region].self, forKey: .regions)
        scope = try c.decodeIfPresent(Int.self, forKey: .scope) ?? -1
        regionHotkeys = try c.decodeIfPresent([Int: RegionHotkey].self, forKey: .regionHotkeys) ?? [:]
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

    /// 本布局第 index 个区域在内置表里的下标——按几何位置对应，不看先后
    /// （用户列表里区域的先后可能与内置表不同：重画过、或由历史条目收编而来）。
    /// 不是内置布局、网格被改过、或该区域不在内置表里时返回 nil。
    /// 内置默认快捷键与内置区域名都按内置表下标定义，取用前必须经此换算。
    func builtinRegionIndex(_ index: Int) -> Int? {
        guard regions.indices.contains(index),
              let builtin = TidyLayout.builtins.first(where: { $0.id == id }),
              builtin.cols == cols, builtin.rows == rows else { return nil }
        return builtin.regions.firstIndex(of: regions[index])
    }

    static func == (lhs: TidyLayout, rhs: TidyLayout) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.cols == rhs.cols
            && lhs.rows == rhs.rows && lhs.regions == rhs.regions
    }

    /// ⌥⌘（全部内置区域快捷键的默认修饰键——用户定案：尽可能短，
    /// 三修饰键按起来不如拖拽，2026-11-13）
    private static let cmdOpt = cmdKey | optionKey

    /// 内置布局（顺序即图标条顺序；id 稳定，快捷键依赖它）。
    /// 共 8 个：一个布局 = 一套完整分区方案（窄宽/宽窄是各自含两个区域的双区布局）。
    /// 每个区域随布局预置默认快捷键（2026-11-13 起，「固定方向快捷键」收编进来），
    /// 一律 ⌥⌘ 两修饰键（用户要求：宁短勿长，太长不如拖拽）：
    /// - ← → ↑ ↓ 四个半屏方向
    /// - [ \ ] 三等分（左中右）；, . 窄宽（左1/3、右2/3）；; ' 宽窄（左2/3、右1/3）——
    ///   右手键位从左到右自然排列（[ < \ < ]，, < . < ; < '）
    /// - 1/2/3/4 四分（按阅读顺序：左上/右上/左下/右下；不用 U/I/J/K——⌥⌘I/J/U 是浏览器
    ///   开发者工具的检查器/控制台/查看源码）；F 最大化；M 居中区域
    /// - 17 个组合互不重复，全 ⌥⌘ 家族与固定动作 ⌃⌥⌘C（居中保持尺寸）/ ⌃⌥⌘Z（恢复）零交叠
    /// keyCode 用 Carbon 键码；用户可整行改录或清除，清除后不回种（见 LayoutStore 补种）。
    static let builtins: [TidyLayout] = [
        .init(id: "halves",       name: L("左右半屏"),        cols: 2, rows: 1, regions: [.init(1, 1, 1, 1), .init(2, 1, 2, 1)],
              regionHotkeys: [0: .init(keyCode: 123, modifiers: cmdOpt),   // ⌥⌘←
                              1: .init(keyCode: 124, modifiers: cmdOpt)]), // ⌥⌘→
        .init(id: "vertical",     name: L("上下半屏"),        cols: 1, rows: 2, regions: [.init(1, 1, 1, 1), .init(1, 2, 1, 2)],
              regionHotkeys: [0: .init(keyCode: 126, modifiers: cmdOpt),   // ⌥⌘↑
                              1: .init(keyCode: 125, modifiers: cmdOpt)]), // ⌥⌘↓
        .init(id: "thirds",       name: L("三等分"),          cols: 3, rows: 1, regions: [.init(1, 1, 1, 1), .init(2, 1, 2, 1), .init(3, 1, 3, 1)],
              regionHotkeys: [0: .init(keyCode: 33, modifiers: cmdOpt),    // ⌥⌘[
                              1: .init(keyCode: 42, modifiers: cmdOpt),    // ⌥⌘\
                              2: .init(keyCode: 30, modifiers: cmdOpt)]),  // ⌥⌘]
        .init(id: "narrowWide",   name: L("左 1/3 + 右 2/3"), cols: 3, rows: 1, regions: [.init(1, 1, 1, 1), .init(2, 1, 3, 1)],
              regionHotkeys: [0: .init(keyCode: 43, modifiers: cmdOpt),    // ⌥⌘,
                              1: .init(keyCode: 47, modifiers: cmdOpt)]),  // ⌥⌘.
        .init(id: "wideNarrow",   name: L("左 2/3 + 右 1/3"), cols: 3, rows: 1, regions: [.init(1, 1, 2, 1), .init(3, 1, 3, 1)],
              regionHotkeys: [0: .init(keyCode: 41, modifiers: cmdOpt),    // ⌥⌘;
                              1: .init(keyCode: 39, modifiers: cmdOpt)]),  // ⌥⌘'
        .init(id: "quarters",     name: L("四分"),            cols: 2, rows: 2, regions: [.init(1, 1, 1, 1), .init(2, 1, 2, 1), .init(1, 2, 1, 2), .init(2, 2, 2, 2)],
              regionHotkeys: [0: .init(keyCode: 18, modifiers: cmdOpt),    // ⌥⌘1 左上
                              1: .init(keyCode: 19, modifiers: cmdOpt),    // ⌥⌘2 右上
                              2: .init(keyCode: 20, modifiers: cmdOpt),    // ⌥⌘3 左下
                              3: .init(keyCode: 21, modifiers: cmdOpt)]),  // ⌥⌘4 右下
        .init(id: "full",         name: L("最大化"),          cols: 1, rows: 1, regions: [.init(1, 1, 1, 1)],
              regionHotkeys: [0: .init(keyCode: 3, modifiers: cmdOpt)]),   // ⌥⌘F
        .init(id: "center",       name: L("居中"),            cols: 6, rows: 6, regions: [.init(2, 2, 5, 5)],   // 原版 Centre：(2,2)-(5,5)
              regionHotkeys: [0: .init(keyCode: 46, modifiers: cmdOpt)]),  // ⌥⌘M（区别于固定 ⌃⌥⌘C 保持尺寸居中）
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
    ///    （换 id+名，保留区域快捷键）；收编后与已有 id 冲突则放弃（防重复）。
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
                // 写回的 JSON 一定带 regionHotkeys 字段：此后空表 = 用户主动清空，不再补种
                UserDefaults.standard.set(true, forKey: seededKey)
                NotificationCenter.default.post(name: .prefsChanged, object: nil)
            }
        }
    }

    /// v2：首版补种按下标逐个比较区域，漏掉了区域先后与内置表不同的布局
    /// （2026-11-13 用户截图：「左 1/3 + 右 2/3」两个区域仍是「录制」）；换键让跑过首版的重补一次
    private static let seededKey = "regionHotkeysSeeded.v2"

    /// 内置区域快捷键一次性补种（启动时调用）：内置快捷键功能之前写入的列表里，
    /// 内置布局的区域没有快捷键 → 补上内置默认值。
    /// 只在「从未补种 且 已有持久化列表」时动手；全新安装直接读到带默认值的 builtins。
    /// 补种前不存在「默认值」，所以空区域一定是「从没设过」而非「用户清掉了」，按区域补是安全的：
    /// - 按几何位置对应内置区域（builtinRegionIndex），不看区域先后；
    ///   被用户改掉的区域对不上内置表，自然不补
    /// - 用户已录的区域不动；默认组合被用户录到别处的跳过（用户录的优先）
    static func seedBuiltinRegionHotkeysIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: seededKey) == nil else { return }
        defaults.set(true, forKey: seededKey)
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode([TidyLayout].self, from: data), !stored.isEmpty else { return }

        var list = canonicalized(stored)   // 先收编历史 id，否则陈旧条目认不出是内置布局
        var taken = Set(list.flatMap { $0.regionHotkeys.values }.filter { $0.keyCode > 0 }.map(comboKey))
        var seeded = 0
        for i in list.indices {
            guard let builtin = TidyLayout.builtins.first(where: { $0.id == list[i].id }) else { continue }
            for region in list[i].regions.indices where (list[i].regionHotkeys[region]?.keyCode ?? 0) <= 0 {
                guard let builtinRegion = list[i].builtinRegionIndex(region),
                      let hk = builtin.regionHotkeys[builtinRegion], !taken.contains(comboKey(hk)) else { continue }
                list[i].regionHotkeys[region] = hk
                taken.insert(comboKey(hk))
                seeded += 1
            }
        }
        guard seeded > 0, let out = try? JSONEncoder().encode(list) else { return }
        defaults.set(out, forKey: key)
        NotificationCenter.default.post(name: .prefsChanged, object: nil)
        AppLog.info("旧版布局列表补种内置区域快捷键 \(seeded) 个")
    }

    private static func comboKey(_ hk: TidyLayout.RegionHotkey) -> String {
        "\(hk.keyCode):\(hk.modifiers)"
    }

    static func reset() { layouts = TidyLayout.builtins }

    static func layout(id: String) -> TidyLayout? {
        layouts.first { $0.id == id }
    }

    /// 图标条/菜单实际展示的布局列表：按作用域过滤（-1 所有屏幕 或 匹配指定 displayID）。
    /// 原版的「自动分组」（相邻互补单区域布局合并成一个图标）已删（2026-11-13 用户定案）：
    /// 这里一个布局本就是多区域一体设计，默认内置布局也没有任何可合并的相邻对。
    static func displayLayouts(for displayID: CGDirectDisplayID?) -> [TidyLayout] {
        guard let display = displayID else { return layouts }
        return layouts.filter { $0.scope == -1 || $0.scope == Int(display) }
    }
}
