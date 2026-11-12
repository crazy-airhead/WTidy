import Testing
import CoreGraphics
@testable import WTidy

// CLT 工具链不带 XCTest，使用 Swift Testing（Testing.framework + 宏插件随 CLT 分发）

private func close(_ a: CGFloat, _ b: CGFloat, eps: CGFloat = 0.001) -> Bool {
    abs(a - b) < eps
}

struct SnapEngineTests {
    // 模拟屏：1920×1080，可见区去掉顶部 25pt 菜单栏
    let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
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

    // MARK: - 布局分区

    @Test func halves() {
        let zones = SnapEngine.zoneRects(for: SnapLayout(id: "halves", kind: .columns(2)), in: visible)
        #expect(zones.count == 2)
        #expect(close(zones[0].width, 960))
        #expect(close(zones[1].minX, 960))
        #expect(close(zones[0].height, visible.height))
    }

    @Test func verticalHalvesTopFirst() {
        let zones = SnapEngine.zoneRects(for: SnapLayout(id: "vertical", kind: .rows(2)), in: visible)
        #expect(zones.count == 2)
        // zone 0 是顶行
        #expect(close(zones[0].maxY, visible.maxY))
        #expect(close(zones[1].minY, visible.minY))
    }

    @Test func thirdsEqualWidths() {
        let zones = SnapEngine.zoneRects(for: SnapLayout(id: "thirds", kind: .columns(3)), in: visible)
        #expect(zones.count == 3)
        #expect(close(zones[0].width, 640))
        #expect(close(zones[2].maxX, visible.maxX))
    }

    @Test func quartersGrid() {
        let zones = SnapEngine.zoneRects(for: SnapLayout(id: "quarters", kind: .grid(cols: 2, rows: 2)), in: visible)
        #expect(zones.count == 4)
        // 顺序：左上、右上、左下、右下
        #expect(zones[0].minX == visible.minX)
        #expect(close(zones[0].maxY, visible.maxY))       // 顶行贴顶
        #expect(close(zones[0].minY, visible.midY))       // 顶行下缘在屏幕中线
        #expect(close(zones[1].minX, visible.midX))
        #expect(close(zones[2].minY, visible.minY))       // 底行贴底
        #expect(close(zones[3].maxX, visible.maxX))
        #expect(close(zones[3].minY, visible.minY))
    }

    @Test func twoThirdsSplit() {
        let zones = SnapEngine.zoneRects(for: SnapLayout(id: "twoThirdsLeft", kind: .columnSplit(leftRatio: 2.0 / 3.0)), in: visible)
        #expect(zones.count == 2)
        #expect(close(zones[0].width, 1280, eps: 0.5))
        #expect(close(zones[1].width, 640, eps: 0.5))
    }

    @Test func full() {
        let zones = SnapEngine.zoneRects(for: SnapLayout(id: "full", kind: .full), in: visible)
        #expect(zones == [visible])
    }

    // MARK: - 间隙

    @Test func gapInsets() {
        let gap: CGFloat = 8
        let zones = SnapEngine.zoneRects(for: SnapLayout(id: "halves", kind: .columns(2)), in: visible, gap: gap)
        // 每个分区四周各缩 gap/2 = 4
        #expect(zones[0].minX == visible.minX + 4)
        #expect(zones[0].minY == visible.minY + 4)
        #expect(close(zones[0].maxX, 960 - 4))
        // 两窗之间总共 8：zone0 右缩 4 + zone1 左缩 4
        #expect(close(zones[1].minX, 960 + 4))
        #expect(close(zones[1].maxX, visible.maxX - 4))
    }

    @Test func maximizeRectWithGap() {
        let r = SnapEngine.maximizeRect(in: visible, gap: 10)
        #expect(r.minX == visible.minX + 5)
        #expect(close(r.width, visible.width - 10))
    }

    // MARK: - 命中

    @Test func zoneIndexHitAndMiss() {
        let zones = SnapEngine.zoneRects(for: SnapLayout(id: "halves", kind: .columns(2)), in: visible)
        #expect(SnapEngine.zoneIndex(at: CGPoint(x: 100, y: 500), in: zones) == 0)
        #expect(SnapEngine.zoneIndex(at: CGPoint(x: 1500, y: 500), in: zones) == 1)
        #expect(SnapEngine.zoneIndex(at: CGPoint(x: -10, y: 500), in: zones) == nil)
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
        mem.remember(key: "a", frame: .zero)
        #expect(mem.recall(key: "a") == .zero)
        mem.remove(key: "a")
        #expect(mem.recall(key: "a") == nil)
    }

    // MARK: - 布局 ↔ 动作映射

    @Test func layoutAndZoneMapping() {
        #expect(OverlayController.layoutAndZone(for: .leftHalf)?.1 == 0)
        let twoThirds = OverlayController.layoutAndZone(for: .twoThirdsRight)
        #expect(twoThirds?.0.id == "twoThirdsRight")
        #expect(twoThirds?.1 == 1)
        #expect(OverlayController.layoutAndZone(for: .center) == nil)
        #expect(OverlayController.layoutAndZone(for: .restore) == nil)
    }
}
