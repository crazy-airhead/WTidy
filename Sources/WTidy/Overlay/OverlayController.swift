import AppKit

/// 总编排器：AX 事件 → 拖拽状态机 → Overlay 呈现 → 吸附应用；快捷键也走这里。
///
/// 交互对齐原版 Window Tidy：
/// 1. 拖动窗口 → 顶部只出现紧凑布局图标条（≤~512pt，好瞄准、鼠标行程短）
/// 2. 光标在图标条内瞄准：图标内的相对位置投影到布局区域
///    （如左右半屏图标，偏左=左半、偏右=右半），选中布局即整屏显示落点预览
/// 3. 松手：在图标上=吸到投影区域；已展开预览时松手在屏内分区上=吸到该分区；其余=不吸附
final class OverlayController: NSObject, WindowWatcherDelegate {
    let ax = AccessibilityService()
    let watcher = WindowWatcher()

    private var windows: [CGDirectDisplayID: OverlayWindow] = [:]
    private var activeScreen: NSScreen?
    private var activeScreenNumber: CGDirectDisplayID = 0
    private var activeLayout: TidyLayout?
    private var activeZoneIndex: Int?
    private var stripRectsGlobal: [CGRect] = []
    private var zonesGlobal: [CGRect] = []
    private var frameMemory = FrameMemory()

    /// 吸附成功回调（用于状态栏展示与日志），参数为人类可读描述
    var onSnapApplied: ((String) -> Void)?

    override init() {
        super.init()
        ax.delegate = { [weak self] event in
            self?.handleAXEvent(event)
        }
        watcher.delegate = self
    }

    func start() {
        ax.start()
    }

    // MARK: - AX 事件入口

    private func handleAXEvent(_ event: AccessibilityService.Event) {
        switch event {
        case .windowDidMove(let window):
            guard Prefs.dragEnabled else { return }
            guard let frame = window.nsFrame else { return }
            watcher.registerMove(window, frame: frame)

        case .focusedWindowChanged(let window):
            // 拖拽中途焦点切走 → 取消本次拖拽
            if watcher.isActive {
                AppLog.info("拖拽中焦点切换至 '\(window?.title ?? "nil")'，取消")
                watcher.cancel()
            }
        }
    }

    // MARK: - WindowWatcherDelegate

    func dragDidBegin(_ window: AXWindow, originalFrame: CGRect) {
        let cursor = NSEvent.mouseLocation
        guard let screen = screenForPoint(cursor) else { return }

        // 记住吸附前位置（只记第一次，多次吸附可一路恢复到最初）
        if frameMemory.recall(key: window.memoryKey) == nil {
            frameMemory.remember(key: window.memoryKey, frame: originalFrame)
        }

        activeScreen = screen
        activeScreenNumber = screenNumber(of: screen)
        activeLayout = nil
        activeZoneIndex = nil
        presentOverlay(on: screen, cursor: cursor)   // 仅图标条，落点预览待选中布局后出现
    }

    func dragTick(cursor: CGPoint) {
        // 拖到另一块屏：把 overlay 迁过去（已选布局保持，分区换算到新屏）
        if let screen = screenForPoint(cursor), screenNumber(of: screen) != activeScreenNumber {
            if let old = activeScreen {
                window(for: old).dismissOverlay()
            }
            activeScreen = screen
            activeScreenNumber = screenNumber(of: screen)
            if let layout = activeLayout {
                zonesGlobal = SnapEngine.zoneRects(for: layout, in: screen.visibleFrame, gap: Prefs.windowGap)
                activeZoneIndex = nil
            }
            presentOverlay(on: screen, cursor: cursor)
            return
        }
        updateHover(cursor: cursor)
    }

    func dragDidEnd(cursor: CGPoint, window: AXWindow?) {
        defer { dismissAll() }
        guard let win = window else { return }

        // 路径 1：松手在图标上 → 图标内投影选区（主路径，鼠标行程最短）
        if let i = stripIndex(at: cursor), LayoutStore.layouts.indices.contains(i) {
            let layout = LayoutStore.layouts[i]
            let r = stripRectsGlobal[i]
            let nx = (cursor.x - r.minX) / max(r.width, 1)
            let ny = (r.maxY - cursor.y) / max(r.height, 1)
            if let zi = SnapEngine.zoneIndexInIcon(nx: nx, ny: ny, layout: layout) {
                let zones = SnapEngine.zoneRects(for: layout, in: activeScreen?.visibleFrame ?? screenForPoint(cursor)?.visibleFrame ?? .zero, gap: Prefs.windowGap)
                if zones.indices.contains(zi), !zones[zi].isNull {
                    applyRect(zones[zi], to: win, layout: layout, zoneIndex: zi)
                    return
                }
            }
        }

        // 路径 2：已选中布局，松手在屏内分区上（精确路径）
        if let layout = activeLayout,
           let zi = SnapEngine.zoneIndex(at: cursor, in: zonesGlobal),
           !zonesGlobal[zi].isNull {
            applyRect(zonesGlobal[zi], to: win, layout: layout, zoneIndex: zi)
            return
        }

        AppLog.info("松手位置无分区，放弃吸附")
    }

    func dragDidCancel() {
        dismissAll()
    }

    // MARK: - Overlay 呈现与命中

    private func presentOverlay(on screen: NSScreen, cursor: CGPoint) {
        computeStripRects(screen: screen)
        updateHover(cursor: cursor)
        window(for: screen).presentOverlay()
    }

    private func updateHover(cursor: CGPoint) {
        guard let screen = activeScreen else { return }
        var model = OverlayModel()

        let hoveredStrip = stripIndex(at: cursor)
        if let i = hoveredStrip, LayoutStore.layouts.indices.contains(i) {
            let layout = LayoutStore.layouts[i]
            if activeLayout?.id != layout.id {
                activeLayout = layout
                zonesGlobal = SnapEngine.zoneRects(for: layout, in: screen.visibleFrame, gap: Prefs.windowGap)
            }
            // 图标内投影：光标在图标内的相对位置决定落点分区
            let r = stripRectsGlobal[i]
            let nx = (cursor.x - r.minX) / max(r.width, 1)
            let ny = (r.maxY - cursor.y) / max(r.height, 1)
            activeZoneIndex = SnapEngine.zoneIndexInIcon(nx: nx, ny: ny, layout: layout)
        } else if let layout = activeLayout, let cur = screenForPoint(cursor) {
            // 光标移入屏内：预览保持，可精确选区
            zonesGlobal = SnapEngine.zoneRects(for: layout, in: cur.visibleFrame, gap: Prefs.windowGap)
            activeZoneIndex = SnapEngine.zoneIndex(at: cursor, in: zonesGlobal)
        }

        model.strip = zip(stripRectsGlobal, LayoutStore.layouts).map { (rect: $0, layout: $1) }
        model.hoveredStripIndex = hoveredStrip

        if activeLayout != nil {
            model.veilRect = screen.frame
            model.zones = zonesGlobal
            model.hoveredZoneIndex = activeZoneIndex
        }

        window(for: screen).overlayView.model = model
    }

    /// 紧凑图标条：整条宽度不超过原版风格（~512-560pt），数量多时自适应
    private func computeStripRects(screen: NSScreen) {
        let vf = screen.visibleFrame
        let count = CGFloat(max(1, LayoutStore.layouts.count))
        let available = vf.width - 48
            - (count - 1) * OverlayMetrics.thumbSpacing
            - OverlayMetrics.stripPadding * 2
        let w = min(OverlayMetrics.iconMaxWidth,
                    max(OverlayMetrics.iconMinWidth, available / count))
        let h = w * OverlayMetrics.iconAspectRatio

        let total = count * w + (count - 1) * OverlayMetrics.thumbSpacing + OverlayMetrics.stripPadding * 2
        var x = vf.midX - total / 2 + OverlayMetrics.stripPadding
        let y = vf.maxY - OverlayMetrics.stripTopGap - h

        stripRectsGlobal = (0..<Int(count)).map { _ in
            let r = CGRect(x: x, y: y, width: w, height: h)
            x += w + OverlayMetrics.thumbSpacing
            return r
        }
    }

    private func stripIndex(at p: CGPoint) -> Int? {
        stripRectsGlobal.firstIndex { $0.insetBy(dx: OverlayMetrics.stripHitInset, dy: OverlayMetrics.stripHitInset).contains(p) }
    }

    private func dismissAll() {
        activeLayout = nil
        activeZoneIndex = nil
        zonesGlobal = []
        for (_, w) in windows { w.dismissOverlay() }
        if let s = activeScreen { window(for: s).overlayView.model = OverlayModel() }
        activeScreen = nil
    }

    /// 显示器热插拔时调用：丢弃全部窗口缓存（旧屏可能已不存在）
    func screenConfigurationChanged() {
        if watcher.isActive { watcher.cancel() } else { dismissAll() }
        for (_, w) in windows { w.dismissOverlay() }
        windows.removeAll()
    }

    private func window(for screen: NSScreen) -> OverlayWindow {
        let number = screenNumber(of: screen)
        if let existing = windows[number] { return existing }
        let w = OverlayWindow(screen: screen)
        windows[number] = w
        return w
    }

    // MARK: - 快捷键路径

    func snapFrontmost(_ action: SnapAction) {
        guard Prefs.hotkeysEnabled else { return }
        guard AccessibilityService.isTrusted else {
            AppLog.warn("快捷键触发但缺少辅助功能权限")
            return
        }
        guard let win = ax.frontmostWindow() else {
            AppLog.warn("快捷键触发但拿不到前台窗口")
            return
        }
        guard win.canSnap else {
            AppLog.warn("快捷键触发但窗口不可吸附 '\(win.title ?? "?")'")
            return
        }
        guard let screen = screenForWindow(win) else { return }
        let vf = screen.visibleFrame
        let gap = Prefs.windowGap

        switch action {
        case .restore:
            let key = win.memoryKey
            guard let original = frameMemory.recall(key: key) else {
                AppLog.info("恢复位置：没有 '\(win.title ?? "?")' 的历史记录")
                return
            }
            win.setNSFrame(original)
            frameMemory.remove(key: key)
            onSnapApplied?("恢复原位置 · \(screen.localizedName)")

        case .center:
            guard let size = win.nsFrame?.size else { return }
            rememberIfNeeded(win)
            let rect = SnapEngine.centeredRect(size: size, in: vf)
            win.setNSFrame(rect)
            onSnapApplied?("居中（保持尺寸） · \(screen.localizedName)")

        default:
            guard let (layout, zone) = Self.layoutAndZone(for: action) else { return }
            let zones = SnapEngine.zoneRects(for: layout, in: vf, gap: gap)
            guard zones.indices.contains(zone), !zones[zone].isNull else { return }
            rememberIfNeeded(win)
            win.setNSFrame(zones[zone])
            onSnapApplied?("\(zoneDisplayName(layout: layout, index: zone)) · \(screen.localizedName)")
        }
    }

    private func rememberIfNeeded(_ win: AXWindow) {
        guard let f = win.nsFrame else { return }
        if frameMemory.recall(key: win.memoryKey) == nil {
            frameMemory.remember(key: win.memoryKey, frame: f)
        }
    }

    /// 快捷键动作 → (布局, 区域下标)；布局从用户列表按稳定 id 查找（被删除则动作失效）
    static func layoutAndZone(for action: SnapAction) -> (TidyLayout, Int)? {
        func l(_ id: String) -> TidyLayout? { LayoutStore.layout(id: id) }
        switch action {
        case .leftHalf: guard let x = l("halves") else { return nil }; return (x, 0)
        case .rightHalf: guard let x = l("halves") else { return nil }; return (x, 1)
        case .topHalf: guard let x = l("vertical") else { return nil }; return (x, 0)
        case .bottomHalf: guard let x = l("vertical") else { return nil }; return (x, 1)
        case .leftThird: guard let x = l("thirds") else { return nil }; return (x, 0)
        case .middleThird: guard let x = l("thirds") else { return nil }; return (x, 1)
        case .rightThird: guard let x = l("thirds") else { return nil }; return (x, 2)
        case .twoThirdsLeft: guard let x = l("twoThirdsLeft") else { return nil }; return (x, 0)
        case .twoThirdsRight: guard let x = l("twoThirdsRight") else { return nil }; return (x, 0)
        case .maximize: guard let x = l("full") else { return nil }; return (x, 0)
        case .center, .restore: return nil
        }
    }

    func zoneDisplayName(layout: TidyLayout, index: Int) -> String {
        switch (layout.id, index) {
        case ("halves", 0): return "左半屏"
        case ("halves", 1): return "右半屏"
        case ("vertical", 0): return "上半屏"
        case ("vertical", 1): return "下半屏"
        case ("thirds", 0): return "左 1/3"
        case ("thirds", 1): return "中 1/3"
        case ("thirds", 2): return "右 1/3"
        case ("twoThirdsLeft", _): return "左 2/3"
        case ("twoThirdsRight", _): return "右 2/3"
        case ("quarters", 0): return "左上 1/4"
        case ("quarters", 1): return "右上 1/4"
        case ("quarters", 2): return "左下 1/4"
        case ("quarters", 3): return "右下 1/4"
        case ("full", _): return "最大化"
        case ("center", _): return "居中"
        default: return layout.regions.count > 1 ? "\(layout.name) 区域\(index + 1)" : layout.name
        }
    }

    // MARK: - 应用吸附（拖拽路径）

    private func applyRect(_ rect: CGRect, to win: AXWindow, layout: TidyLayout, zoneIndex: Int) {
        win.setNSFrame(rect)
        let screenName = activeScreen?.localizedName ?? "?"
        let desc = "\(zoneDisplayName(layout: layout, index: zoneIndex)) · \(screenName)"
        AppLog.info("SNAP '\(win.title ?? "?")' → \(desc) rect=\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))x\(Int(rect.height))")
        onSnapApplied?(desc)
    }

    // MARK: - 屏幕工具

    private func screenForPoint(_ p: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(p) } ?? NSScreen.main
    }

    private func screenForWindow(_ win: AXWindow) -> NSScreen? {
        guard let frame = win.nsFrame else { return screenForPoint(NSEvent.mouseLocation) }
        var best: (NSScreen, CGFloat)?
        for s in NSScreen.screens {
            let overlap = s.frame.intersection(frame)
            if !overlap.isNull && (best == nil || overlap.width * overlap.height > best!.1) {
                best = (s, overlap.width * overlap.height)
            }
        }
        return best?.0 ?? screenForPoint(NSEvent.mouseLocation)
    }

    private func screenNumber(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
    }
}
