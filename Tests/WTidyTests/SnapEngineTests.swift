import Testing
import CoreGraphics
@testable import WTidy

// CLT 工具链不带 XCTest，使用 Swift Testing（Testing.framework + 宏插件随 CLT 分发）

private func close(_ a: CGFloat, _ b: CGFloat, eps: CGFloat = 0.001) -> Bool {
    abs(a - b) < eps
}

struct SnapEngineTests {
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

    @Test func twoThirdsSingleRegion() {
        let left = LayoutStore.layout(id: "twoThirdsLeft")!
        let zonesL = SnapEngine.zoneRects(for: left, in: visible)
        #expect(zonesL.count == 1)
        #expect(close(zonesL[0].width, 1280, eps: 0.5))

        let right = LayoutStore.layout(id: "twoThirdsRight")!
        let zonesR = SnapEngine.zoneRects(for: right, in: visible)
        #expect(zonesR.count == 1)
        #expect(close(zonesR[0].width, 1280, eps: 0.5))
        #expect(close(zonesR[0].maxX, visible.maxX))
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

    // MARK: - 快捷键映射

    @Test func layoutAndZoneMapping() {
        #expect(OverlayController.layoutAndZone(for: .leftHalf)?.1 == 0)
        #expect(OverlayController.layoutAndZone(for: .rightHalf)?.0.id == "halves")
        #expect(OverlayController.layoutAndZone(for: .twoThirdsRight)?.0.id == "twoThirdsRight")
        #expect(OverlayController.layoutAndZone(for: .twoThirdsRight)?.1 == 0)
        #expect(OverlayController.layoutAndZone(for: .center) == nil)
        #expect(OverlayController.layoutAndZone(for: .restore) == nil)
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
}
