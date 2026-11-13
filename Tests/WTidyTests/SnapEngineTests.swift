import Testing
import CoreGraphics
import Foundation
import Carbon.HIToolbox
@testable import WTidy

// CLT 工具链不带 XCTest，使用 Swift Testing（Testing.framework + 宏插件随 CLT 分发）

private func close(_ a: CGFloat, _ b: CGFloat, eps: CGFloat = 0.001) -> Bool {
    abs(a - b) < eps
}

// 套件内测试共享 LayoutStore 全局状态，必须串行执行；
// 且测试进程的 UserDefaults 会跨运行持久化——每个测试前重置为内置布局
@Suite(.serialized)
struct SnapEngineTests {
    init() {
        LayoutStore.reset()
    }
    // 模拟屏：1920×1080，可见区去掉顶部 25pt 菜单栏
    let visible = CGRect(x: 0, y: 0, width: 1920, height: 1055)

    // MARK: - 坐标换算

    @Test func coordinateFlipRoundTrip() {
        let h: CGFloat = 1080
        let ns = CGRect(x: 100, y: 200, width: 300, height: 400)
        let ax = ScreenGeometry.axRect(fromNS: ns, primaryScreenHeight: h)
        // AX 原点在左上：y = h - maxY
        #expect(ax.minY == 480)
        let back = ScreenGeometry.nsRect(fromAX: ax, primaryScreenHeight: h)
        #expect(back == ns)
    }

    @Test func pointFlip() {
        let h: CGFloat = 900
        #expect(ScreenGeometry.axPoint(fromNS: CGPoint(x: 10, y: 890), primaryScreenHeight: h).y == 10)
        #expect(ScreenGeometry.nsPoint(fromAX: CGPoint(x: 10, y: 0), primaryScreenHeight: h).y == 900)
    }

    // MARK: - 归一化区域 → 屏幕分区

    @Test func halvesZones() {
        let layout = LayoutStore.layout(id: "halves")!
        let zones = SnapEngine.zoneRects(for: layout, in: visible)
        #expect(layout.regions.count == 2)
        #expect(close(zones[0].width, 960))
        #expect(close(zones[1].minX, 960))
        #expect(close(zones[0].height, visible.height))
        // zone0 为左半：AppKit 坐标 min/max 应覆盖整屏
        #expect(close(zones[0].minY, 0) && close(zones[0].maxY, visible.height))
    }

    @Test func verticalHalvesTopFirst() {
        let layout = LayoutStore.layout(id: "vertical")!
        let zones = SnapEngine.zoneRects(for: layout, in: visible)
        #expect(zones.count == 2)
        // zone 0 是顶行：AppKit 坐标顶行 maxY = 屏顶
        #expect(close(zones[0].maxY, visible.maxY))
        #expect(close(zones[1].minY, visible.minY))
    }

    @Test func thirdsEqualWidths() {
        let layout = LayoutStore.layout(id: "thirds")!
        let zones = SnapEngine.zoneRects(for: layout, in: visible)
        #expect(zones.count == 3)
        #expect(close(zones[0].width, 640))
        #expect(close(zones[2].maxX, visible.maxX))
    }

    @Test func quartersGridOrder() {
        let layout = LayoutStore.layout(id: "quarters")!
        let zones = SnapEngine.zoneRects(for: layout, in: visible)
        #expect(zones.count == 4)
        // 顺序：左上、右上、左下、右下
        #expect(close(zones[0].minX, 0))
        #expect(close(zones[0].maxY, visible.maxY))       // 顶行贴顶
        #expect(close(zones[0].minY, visible.midY))       // 顶行下缘在中线
        #expect(close(zones[1].minX, visible.midX))
        #expect(close(zones[2].minY, visible.minY))       // 底行贴底
        #expect(close(zones[3].maxX, visible.maxX))
    }

    @Test func twoThirdsSplitLayouts() {
        // 左 1/3 + 右 2/3：两个区域，宽度 640 / 1280
        let narrowWide = LayoutStore.layout(id: "narrowWide")!
        let zonesNW = SnapEngine.zoneRects(for: narrowWide, in: visible)
        #expect(zonesNW.count == 2)
        #expect(close(zonesNW[0].width, 640))
        #expect(close(zonesNW[1].width, 1280, eps: 0.5))
        #expect(close(zonesNW[1].maxX, visible.maxX))

        // 左 2/3 + 右 1/3
        let wideNarrow = LayoutStore.layout(id: "wideNarrow")!
        let zonesWN = SnapEngine.zoneRects(for: wideNarrow, in: visible)
        #expect(zonesWN.count == 2)
        #expect(close(zonesWN[0].width, 1280, eps: 0.5))
        #expect(close(zonesWN[1].width, 640))
        #expect(close(zonesWN[1].maxX, visible.maxX))

        // 投影：窄宽图标瞄左=左1/3、瞄右=右2/3
        #expect(SnapEngine.zoneIndexInIcon(nx: 0.1, ny: 0.5, layout: narrowWide) == 0)
        #expect(SnapEngine.zoneIndexInIcon(nx: 0.9, ny: 0.5, layout: narrowWide) == 1)
    }

    @Test func centerRegionMatchesOriginal() {
        // 原版 Centre：6×6 网格 (2,2)-(5,5) → 归一化 1/6..5/6
        let center = LayoutStore.layout(id: "center")!
        let zones = SnapEngine.zoneRects(for: center, in: visible)
        #expect(zones.count == 1)
        #expect(close(zones[0].width, visible.width * 4 / 6))
        #expect(close(zones[0].height, visible.height * 4 / 6))
        #expect(close(zones[0].midX, visible.midX))
    }

    @Test func gapInsets() {
        let layout = LayoutStore.layout(id: "halves")!
        let gap: CGFloat = 8
        let zones = SnapEngine.zoneRects(for: layout, in: visible, gap: gap)
        // 每个分区四周各缩 gap/2 = 4
        #expect(zones[0].minX == visible.minX + 4)
        #expect(close(zones[0].maxX, 960 - 4))
        #expect(close(zones[1].minX, 960 + 4))
        #expect(close(zones[1].maxX, visible.maxX - 4))
    }

    @Test func maximizeRectWithGap() {
        let r = SnapEngine.maximizeRect(in: visible, gap: 10)
        #expect(r.minX == visible.minX + 5)
        #expect(close(r.width, visible.width - 10))
    }

    // MARK: - 屏内命中

    @Test func zoneIndexHitAndMiss() {
        let layout = LayoutStore.layout(id: "halves")!
        let zones = SnapEngine.zoneRects(for: layout, in: visible)
        #expect(SnapEngine.zoneIndex(at: CGPoint(x: 100, y: 500), in: zones) == 0)
        #expect(SnapEngine.zoneIndex(at: CGPoint(x: 1500, y: 500), in: zones) == 1)
        #expect(SnapEngine.zoneIndex(at: CGPoint(x: -10, y: 500), in: zones) == nil)
    }

    // MARK: - 图标内投影（图标条瞄准的核心）

    @Test func projectionInHalvesIcon() {
        let layout = LayoutStore.layout(id: "halves")!
        #expect(SnapEngine.zoneIndexInIcon(nx: 0.2, ny: 0.5, layout: layout) == 0)  // 图标偏左 → 左半
        #expect(SnapEngine.zoneIndexInIcon(nx: 0.8, ny: 0.5, layout: layout) == 1)  // 偏右 → 右半
    }

    @Test func projectionInVerticalIcon() {
        let layout = LayoutStore.layout(id: "vertical")!
        #expect(SnapEngine.zoneIndexInIcon(nx: 0.5, ny: 0.2, layout: layout) == 0)  // 偏上 → 上半
        #expect(SnapEngine.zoneIndexInIcon(nx: 0.5, ny: 0.8, layout: layout) == 1)  // 偏下 → 下半
    }

    @Test func projectionInThirdsAndQuarters() {
        let thirds = LayoutStore.layout(id: "thirds")!
        #expect(SnapEngine.zoneIndexInIcon(nx: 0.1, ny: 0.5, layout: thirds) == 0)
        #expect(SnapEngine.zoneIndexInIcon(nx: 0.5, ny: 0.5, layout: thirds) == 1)
        #expect(SnapEngine.zoneIndexInIcon(nx: 0.9, ny: 0.5, layout: thirds) == 2)

        let quarters = LayoutStore.layout(id: "quarters")!
        #expect(SnapEngine.zoneIndexInIcon(nx: 0.3, ny: 0.2, layout: quarters) == 0) // 左上
        #expect(SnapEngine.zoneIndexInIcon(nx: 0.8, ny: 0.2, layout: quarters) == 1) // 右上
        #expect(SnapEngine.zoneIndexInIcon(nx: 0.3, ny: 0.8, layout: quarters) == 2) // 左下
        #expect(SnapEngine.zoneIndexInIcon(nx: 0.8, ny: 0.8, layout: quarters) == 3) // 右下
    }

    @Test func projectionSingleRegionAndSparse() {
        let full = LayoutStore.layout(id: "full")!
        #expect(SnapEngine.zoneIndexInIcon(nx: 0.7, ny: 0.3, layout: full) == 0)

        // 稀疏网格：center 在 6×6 上只占 (2,2)-(5,5)，光标落角落也应就近命中区域 0
        let center = LayoutStore.layout(id: "center")!
        #expect(SnapEngine.zoneIndexInIcon(nx: 0.0, ny: 0.0, layout: center) == 0)
        #expect(SnapEngine.zoneIndexInIcon(nx: 0.95, ny: 0.95, layout: center) == 0)
    }

    // MARK: - 布局存储

    @Test func layoutStoreRoundTripAndBuiltinIds() {
        let original = LayoutStore.layouts
        defer { LayoutStore.layouts = original }

        var list = original
        list.append(TidyLayout(id: "test-x", name: "测试", cols: 4, rows: 4, regions: [.init(1, 1, 2, 2)]))
        LayoutStore.layouts = list
        #expect(LayoutStore.layout(id: "test-x")?.name == "测试")
        #expect(LayoutStore.layout(id: "test-x")?.normalizedRects.first?.minX == 0)
        #expect(close(LayoutStore.layout(id: "test-x")!.normalizedRects[0].width, 0.5))

        LayoutStore.reset()
        #expect(LayoutStore.layouts.count == TidyLayout.builtins.count)
    }

    @Test func staleBuiltinEntriesCanonicalized() {
        // 历史迭代的内置布局残留：id 不在当前内置表、但结构与 wideNarrow 全等、
        // 名称是历史内置默认名（「左 2/3」）→ 读取时应收编为 wideNarrow（保留区域快捷键）
        var stale = TidyLayout(id: "user-made", name: "左 2/3", cols: 3, rows: 1,
                               regions: [.init(3, 1, 3, 1), .init(1, 1, 2, 1)])   // 区域乱序画出
        stale.regionHotkeys[0] = .init(keyCode: 44, modifiers: cmdKey | optionKey)
        // 结构同内置但名称是自定义 → 永不收编（避免吞掉用户故意改名的布局）
        let custom = TidyLayout(id: "custom-x", name: "我的布局", cols: 3, rows: 1,
                                regions: [.init(1, 1, 2, 1), .init(3, 1, 3, 1)])
        LayoutStore.layouts = [stale, custom]
        let list = LayoutStore.layouts
        #expect(list.count == 2)
        #expect(list[0].id == "wideNarrow")
        #expect(list[0].name == L("左 2/3 + 右 1/3"))
        #expect(list[0].regionHotkeys[0]?.keyCode == 44)
        #expect(list[1].id == "custom-x")
        #expect(list[1].name == "我的布局")
    }

    // MARK: - 内置区域快捷键

    @Test func builtinRegionHotkeyDefaults() {
        // 每个内置布局的每个区域都要预置默认快捷键；组合互不重复、下标不越界；
        // 一律 ⌥⌘ 两修饰键（用户定案 2026-11-13：宁短勿长，太长不如拖拽）；
        // 且不与固定动作 ⌃⌥⌘C（保持尺寸居中）/ ⌃⌥⌘Z（恢复）交叠
        var seen = Set<String>()
        for layout in TidyLayout.builtins {
            #expect(layout.regionHotkeys.count == layout.regions.count,
                    "\(layout.id) 应每个区域都预置快捷键")
            for (region, hk) in layout.regionHotkeys {
                #expect(layout.regions.indices.contains(region), "\(layout.id) 快捷键下标 \(region) 越界")
                #expect(hk.keyCode > 0)
                #expect(hk.modifiers == cmdKey | optionKey, "\(layout.id) 区域\(region) 默认修饰键应为 ⌥⌘")
                let key = "\(hk.keyCode):\(hk.modifiers)"
                #expect(!seen.contains(key), "\(layout.id) 区域\(region) 组合重复：\(key)")
                seen.insert(key)
            }
        }
        #expect(seen.count == 17)
        for action in SnapAction.allCases {
            #expect(!seen.contains("\(action.defaultKeyCode):\(action.defaultModifiers)"),
                    "内置默认与固定动作 \(action.rawValue) 撞组合")
        }
    }

    @Test func builtinDefaultConflictOwner() {
        // ⌥⌘← 是内置默认「左右半屏 · 区域 1」——录到别处必须报冲突
        let owner = HotkeyManager.shared.conflictOwner(keyCode: 123, modifiers: cmdKey | optionKey,
                                                       excluding: "any", region: 0)
        #expect(owner == LayoutStore.layout(id: "halves")!.name + " · " + LF("区域 %d", 1))
        // 固定动作只剩两个：⌃⌥⌘C / ⌃⌥⌘Z
        #expect(HotkeyManager.shared.conflictOwner(keyCode: 8, modifiers: cmdKey | optionKey | controlKey,
                                                   excluding: "any", region: 0) == SnapAction.center.displayName)
        #expect(HotkeyManager.shared.conflictOwner(keyCode: 6, modifiers: cmdKey | optionKey | controlKey,
                                                   excluding: "any", region: 0) == SnapAction.restore.displayName)
        // 未占用的组合不报（Y 不在任何默认表里）
        #expect(HotkeyManager.shared.conflictOwner(keyCode: 16, modifiers: cmdKey | optionKey,
                                                   excluding: "any", region: 0) == nil)
    }

    @Test func seedBuiltinRegionHotkeysForLegacyList() {
        // 旧版持久化列表（regionHotkeys 字段出现前写入）：内置布局空表 → 启动时一次性补默认
        let savedMarker = UserDefaults.standard.object(forKey: "regionHotkeysSeeded.v2")
        defer {
            if let m = savedMarker { UserDefaults.standard.set(m, forKey: "regionHotkeysSeeded.v2") }
            else { UserDefaults.standard.removeObject(forKey: "regionHotkeysSeeded.v2") }
        }
        // 五种存量形态：
        // halves —— 从没录过 → 两个区域都补
        // thirds —— 用户只录了区域 0（⌥⌘→，恰是 halves 右半的默认组合）→ 自己录的不动，补其余区域
        // vertical —— 用户把分区改成了三行 → 结构已变，不补
        // narrowWide —— 区域先后与内置表相反（右 2/3 在前）→ 按几何位置补，不看下标
        //   （2026-11-13 用户截图：首版按下标比较，这种布局整个被跳过，仍显示「录制」）
        // custom-x —— 自定义布局 → 不补
        let legacy = """
        [{"id":"halves","name":"左右半屏","cols":2,"rows":1,"regions":[{"x1":1,"y1":1,"x2":1,"y2":1},{"x1":2,"y1":1,"x2":2,"y2":1}]},
         {"id":"thirds","name":"三等分","cols":3,"rows":1,"regions":[{"x1":1,"y1":1,"x2":1,"y2":1},{"x1":2,"y1":1,"x2":2,"y2":1},{"x1":3,"y1":1,"x2":3,"y2":1}],"regionHotkeys":{"0":{"keyCode":124,"modifiers":\(cmdKey | optionKey)}}},
         {"id":"vertical","name":"上下半屏","cols":1,"rows":3,"regions":[{"x1":1,"y1":1,"x2":1,"y2":1},{"x1":1,"y1":2,"x2":1,"y2":3}]},
         {"id":"narrowWide","name":"左 1/3 + 右 2/3","cols":3,"rows":1,"regions":[{"x1":2,"y1":1,"x2":3,"y2":1},{"x1":1,"y1":1,"x2":1,"y2":1}]},
         {"id":"custom-x","name":"我的","cols":6,"rows":6,"regions":[{"x1":2,"y1":2,"x2":5,"y2":5}]}]
        """
        UserDefaults.standard.set(Data(legacy.utf8), forKey: "layoutList")
        UserDefaults.standard.removeObject(forKey: "regionHotkeysSeeded.v2")

        LayoutStore.seedBuiltinRegionHotkeysIfNeeded()

        let list = LayoutStore.layouts
        let builtin = { (id: String) in TidyLayout.builtins.first { $0.id == id }! }
        #expect(list.map(\.id) == ["halves", "thirds", "vertical", "narrowWide", "custom-x"])
        // halves：左半补 ⌥⌘←；右半的默认 ⌥⌘→ 已被用户录给 thirds 区域 0 → 跳过，不制造冲突
        #expect(list[0].regionHotkeys[0] == builtin("halves").regionHotkeys[0])
        #expect(list[0].regionHotkeys[1] == nil)
        // thirds：用户录的区域 0 原样保留，区域 1/2 补默认
        #expect(list[1].regionHotkeys[0] == .init(keyCode: 124, modifiers: cmdKey | optionKey))
        #expect(list[1].regionHotkeys[1] == builtin("thirds").regionHotkeys[1])
        #expect(list[1].regionHotkeys[2] == builtin("thirds").regionHotkeys[2])
        #expect(list[2].regionHotkeys.isEmpty)   // 网格改过的内置布局不补
        // narrowWide：本列表区域 0 是右 2/3 → 拿内置表区域 1 的 ⌥⌘.；区域 1 是左 1/3 → ⌥⌘,
        #expect(list[3].regionHotkeys[0] == builtin("narrowWide").regionHotkeys[1])
        #expect(list[3].regionHotkeys[1] == builtin("narrowWide").regionHotkeys[0])
        #expect(list[3].builtinRegionIndex(0) == 1)
        #expect(list[3].builtinRegionIndex(1) == 0)
        #expect(list[2].builtinRegionIndex(1) == nil)   // 网格已改：对不上内置表
        #expect(list[4].regionHotkeys.isEmpty)   // 自定义布局不补
        #expect(list[4].builtinRegionIndex(0) == nil)

        // 幂等：之后用户清空（setter 置补种标记）→ 再跑不回种
        var cleared = list
        cleared[0].regionHotkeys = [:]
        LayoutStore.layouts = cleared
        LayoutStore.seedBuiltinRegionHotkeysIfNeeded()
        #expect(LayoutStore.layouts[0].regionHotkeys.isEmpty)
    }

    // MARK: - 自动分组（原版 AutoGroupLayouts）

    @Test func autoGroupMerge() {
        let saved = Prefs.autoGroupLayouts
        defer { Prefs.autoGroupLayouts = saved }

        // 左半 + 右半 自定义布局：互补可合并
        let left = TidyLayout(id: "L", name: "左半", cols: 2, rows: 1, regions: [.init(1, 1, 1, 1)])
        let right = TidyLayout(id: "R", name: "右半", cols: 2, rows: 1, regions: [.init(2, 1, 2, 1)])
        #expect(TidyLayout.groupable(left, right))
        let merged = TidyLayout.merged(left, right)
        #expect(merged.regions.count == 2)
        #expect(merged.normalizedRects.count == 2)

        // 窄宽 + 宽窄 区域互相重叠 → 不可合并
        let narrowWide = TidyLayout.builtins.first { $0.id == "narrowWide" }!
        let wideNarrow = TidyLayout.builtins.first { $0.id == "wideNarrow" }!
        #expect(!TidyLayout.groupable(narrowWide, wideNarrow))

        // 作用域不同 → 不可合并
        var scopedRight = right
        scopedRight.scope = 5
        #expect(!TidyLayout.groupable(left, scopedRight))
    }

    @Test func displayLayoutsScopeFilterAndGroup() {
        let savedLayouts = LayoutStore.layouts
        let savedGroup = Prefs.autoGroupLayouts
        defer {
            LayoutStore.layouts = savedLayouts
            Prefs.autoGroupLayouts = savedGroup
        }

        let left = TidyLayout(id: "L", name: "左半", cols: 2, rows: 1, regions: [.init(1, 1, 1, 1)])
        let right = TidyLayout(id: "R", name: "右半", cols: 2, rows: 1, regions: [.init(2, 1, 2, 1)])
        let scopedOnly = TidyLayout(id: "S", name: "屏专属", cols: 2, rows: 1,
                                    regions: [.init(1, 1, 2, 1)], scope: 12345)

        // 1) 自动分组：同网格互补布局合并为一个图标
        Prefs.autoGroupLayouts = true
        LayoutStore.layouts = [left, right]
        let all = LayoutStore.displayLayouts(for: nil)
        #expect(all.count == 1)
        #expect(all[0].id == "L+R")
        #expect(all[0].regions.count == 2)

        // 2) 作用域过滤：scope=12345 的布局只出现在该屏；不同 scope 不参与合并
        LayoutStore.layouts = [left, scopedOnly]
        let onScreen = LayoutStore.displayLayouts(for: 12345)
        #expect(onScreen.count == 2)                      // L(所有屏) + S(本屏)
        let other = LayoutStore.displayLayouts(for: 99999)
        #expect(other.count == 1 && other[0].id == "L")   // S 不在别的屏展示

        // 3) 关闭自动分组：不合并
        Prefs.autoGroupLayouts = false
        LayoutStore.layouts = [left, right]
        #expect(LayoutStore.displayLayouts(for: nil).count == 2)
    }

    @Test func scopeDecodeCompatWithoutField() {
        // 旧版持久化 JSON 无 scope 字段 → 解码回退 -1
        let json = #"{"id":"x","name":"旧","cols":2,"rows":1,"regions":[{"x1":1,"y1":1,"x2":1,"y2":1}]}"#
        let decoded = try? JSONDecoder().decode(TidyLayout.self, from: Data(json.utf8))
        #expect(decoded?.scope == -1)
        #expect(decoded?.name == "旧")
    }

    // MARK: - 居中

    @Test func centeredRect() {
        let r = SnapEngine.centeredRect(size: CGSize(width: 800, height: 600), in: visible)
        #expect(close(r.midX, visible.midX, eps: 0.5))
        #expect(close(r.midY, visible.midY, eps: 0.5))
    }

    @Test func centeredRectClampsOversized() {
        let r = SnapEngine.centeredRect(size: CGSize(width: 4000, height: 3000), in: visible)
        #expect(r.width == visible.width)
        #expect(r.height == visible.height)
    }

    // MARK: - 恢复记忆

    @Test func frameMemory() {
        var mem = FrameMemory()
        let f = CGRect(x: 1, y: 2, width: 3, height: 4)
        #expect(mem.recall(key: "a") == nil)
        mem.remember(key: "a", frame: f)
        #expect(mem.recall(key: "a") == f)
        mem.remove(key: "a")
        #expect(mem.recall(key: "a") == nil)
    }

    // MARK: - 图标条几何（定位页参数）

    private func withPrefs<T>(_ changes: () -> Void, _ body: () -> T) -> T {
        let saved = (Prefs.stripPosX, Prefs.stripPosY, Prefs.stripMargin, Prefs.stripMaxWidth, Prefs.stripVertical)
        changes()
        let result = body()
        Prefs.stripPosX = saved.0
        Prefs.stripPosY = saved.1
        Prefs.stripMargin = saved.2
        Prefs.stripMaxWidth = saved.3
        Prefs.stripVertical = saved.4
        return result
    }

    @Test func stripGeometryPositionFactors() {
        withPrefs({
            Prefs.stripPosX = 0.5
            Prefs.stripPosY = 0
            Prefs.stripMargin = 0
            Prefs.stripVertical = false
        }) {
            let vf = CGRect(x: 0, y: 0, width: 1600, height: 1000)
            let rects = StripGeometry.iconRects(layoutCount: 8, in: vf)
            #expect(rects.count == 8)
            // 横排：全部图标同一水平线；条顶贴 vf 顶，图标再缩进底卡内边距(12pt)
            let first = rects[0]
            #expect(close(first.maxY, vf.height - 12))
            let union = rects.reduce(rects[0]) { $0.union($1) }
            // 居中（posX=0.5）：左右对称
            #expect(close(union.midX, vf.width / 2, eps: 1))
        }

        withPrefs({
            Prefs.stripPosX = 0
            Prefs.stripMargin = 10
            Prefs.stripVertical = true
        }) {
            let vf = CGRect(x: 0, y: 0, width: 1600, height: 1000)
            let rects = StripGeometry.iconRects(layoutCount: 4, in: vf)
            // 纵排：x 相同，纵向排布，贴左（posX=0）且留边距
            #expect(rects.allSatisfy { close($0.minX, rects[0].minX) })
            #expect(rects[0].minX >= 10)
            #expect(close(rects[0].maxY, vf.height - 10 - 12, eps: 1))   // 贴顶（posY=0）减边距与底卡内边距
            #expect(rects[1].maxY < rects[0].minY + 0.001)          // 依次向下
        }
    }

    // MARK: - 快捷键冲突检测（HotkeyManager.conflictOwner）
    // 注意：必须放在本串行套件内——独立套件会与 SnapEngineTests 并行，其 init() 的
    // LayoutStore.reset() 会与本测试的写入交错（实测并行竞态导致断言失败）

    @Test func legacyActivationShortcutFieldIgnored() {
        // 布局级快捷键已删（2026-11-13 用户定案：只要区域级）：
        // 旧 JSON 里的 activationKeyCode/Modifiers 字段由 Codable 静默忽略，解码不报错
        let json = #"{"id":"x","name":"旧","cols":2,"rows":1,"regions":[{"x1":1,"y1":1,"x2":1,"y2":1}],"activationKeyCode":44,"activationModifiers":5}"#
        let decoded = try? JSONDecoder().decode(TidyLayout.self, from: Data(json.utf8))
        #expect(decoded?.name == "旧")
    }

    @Test func regionShortcutConflictSemantics() {
        var list = LayoutStore.layouts
        // 布局 A 的区域 0 录了 ⌥⌘S
        list[0].regionHotkeys[0] = .init(keyCode: 1, modifiers: cmdKey | optionKey)
        LayoutStore.layouts = list

        let expected = LayoutStore.layouts[0].name + " · " + LF("区域 %d", 1)
        // 同布局另一区域录同一组合 → 冲突，占用者名带区域号
        #expect(HotkeyManager.shared.conflictOwner(keyCode: 1, modifiers: cmdKey | optionKey,
                                                   excluding: list[0].id, region: 1) == expected)
        // 豁免精确同位（重录自己）
        #expect(HotkeyManager.shared.conflictOwner(keyCode: 1, modifiers: cmdKey | optionKey,
                                                   excluding: list[0].id, region: 0) == nil)
        // 其他布局撞车同样报
        #expect(HotkeyManager.shared.conflictOwner(keyCode: 1, modifiers: cmdKey | optionKey,
                                                   excluding: "other", region: 0) == expected)
    }

    @Test func regionHotkeysPersistenceRoundTrip() {
        var list = LayoutStore.layouts
        list[1].regionHotkeys[2] = .init(keyCode: 20, modifiers: cmdKey | controlKey)
        LayoutStore.layouts = list
        // 重新读取（走 UserDefaults JSON 往返），区域快捷键必须存活
        let reread = LayoutStore.layouts
        #expect(reread[1].regionHotkeys[2] == .init(keyCode: 20, modifiers: cmdKey | controlKey))
        // 旧 JSON（无 regionHotkeys 字段）解码回退为空表——由 init(from:) 的 decodeIfPresent 保证
    }
}
