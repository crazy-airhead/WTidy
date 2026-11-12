import AppKit

/// 总编排器：AX 事件 → 拖拽状态机 → Overlay 呈现 → 吸附应用；快捷键也走这里。
final class OverlayController: NSObject, WindowWatcherDelegate {
    let ax = AccessibilityService()
    let watcher = WindowWatcher()

    private var windows: [CGDirectDisplayID: OverlayWindow] = [:]
    private var activeScreen: NSScreen?
    private var activeScreenNumber: CGDirectDisplayID = 0
    private var activeLayout: SnapLayout?
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
        presentOverlay(on: screen, cursor: cursor)
    }

    func dragTick(cursor: CGPoint) {
        // 拖到另一块屏：把 overlay 迁过去
        if let screen = screenForPoint(cursor), screenNumber(of: screen) != activeScreenNumber {
            if let old = activeScreen {
                window(for: old).dismissOverlay()
            }
            activeScreen = screen
            activeScreenNumber = screenNumber(of: screen)
            activeLayout = nil
            presentOverlay(on: screen, cursor: cursor)
            return
        }
        updateHover(cursor: cursor)
    }

    func dragDidEnd(cursor: CGPoint, window: AXWindow?) {
        defer { dismissAll() }

        guard let layout = activeLayout,
              let win = window,
              let idx = SnapEngine.zoneIndex(at: cursor, in: zonesGlobal),
              !zonesGlobal[idx].isNull else {
            AppLog.info("松手位置无分区，放弃吸附")
            return
        }
        let rect = zonesGlobal[idx]
        let name = zoneDisplayName(layout: layout, index: idx)
        applyRect(rect, to: win, name: name)
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

        // 命中缩略图？
        var hoveredStrip: Int? = nil
        for (i, r) in stripRectsGlobal.enumerated() where r.contains(cursor) {
            hoveredStrip = i
        }

        if let i = hoveredStrip {
            let layout = SnapLayout.strip[i]
            if activeLayout != layout {
                activeLayout = layout
                zonesGlobal = SnapEngine.zoneRects(for: layout, in: screen.visibleFrame, gap: Prefs.windowGap)
            }
        } else if activeLayout != nil, let screen = screenForPoint(cursor) {
            zonesGlobal = SnapEngine.zoneRects(for: activeLayout!, in: screen.visibleFrame, gap: Prefs.windowGap)
        }

        model.strip = zip(SnapLayout.strip, stripRectsGlobal).map { layout, rect in
            let inner = rect.insetBy(dx: OverlayMetrics.thumbInnerInset, dy: OverlayMetrics.thumbInnerInset)
            let mini = SnapEngine.zoneRects(for: layout, in: inner, gap: 0)
            return (rect: rect, miniZones: mini)
        }
        model.hoveredStripIndex = hoveredStrip

        if activeLayout != nil {
            model.veilRect = screen.frame
            model.zones = zonesGlobal
            model.hoveredZoneIndex = SnapEngine.zoneIndex(at: cursor, in: zonesGlobal)
        }

        window(for: screen).overlayView.model = model
    }

    private func computeStripRects(screen: NSScreen) {
        let vf = screen.visibleFrame
        let count = CGFloat(SnapLayout.strip.count)
        let total = count * OverlayMetrics.thumbSize.width
            + (count - 1) * OverlayMetrics.thumbSpacing
            + OverlayMetrics.stripPadding * 2
        var x = vf.midX - total / 2 + OverlayMetrics.stripPadding
        let y = vf.maxY - OverlayMetrics.stripTopGap - OverlayMetrics.thumbSize.height

        stripRectsGlobal = SnapLayout.strip.map { _ in
            let r = CGRect(x: x, y: y, width: OverlayMetrics.thumbSize.width, height: OverlayMetrics.thumbSize.height)
            x += OverlayMetrics.thumbSize.width + OverlayMetrics.thumbSpacing
            return r
        }
    }

    private func dismissAll() {
        activeLayout = nil
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
            onSnapApplied?("居中 · \(screen.localizedName)")

        default:
            guard let (layout, zone) = Self.layoutAndZone(for: action) else { return }
            let zones = SnapEngine.zoneRects(for: layout, in: vf, gap: gap)
            guard zones.indices.contains(zone), !zones[zone].isNull else { return }
            let rect = zones[zone]
            rememberIfNeeded(win)
            win.setNSFrame(rect)
            onSnapApplied?("\(zoneDisplayName(layout: layout, index: zone)) · \(screen.localizedName)")
        }
    }

    private func rememberIfNeeded(_ win: AXWindow) {
        guard let f = win.nsFrame else { return }
        if frameMemory.recall(key: win.memoryKey) == nil {
            frameMemory.remember(key: win.memoryKey, frame: f)
        }
    }

    static func layoutAndZone(for action: SnapAction) -> (SnapLayout, Int)? {
        func layout(_ id: String) -> SnapLayout? { SnapLayout.strip.first { $0.id == id } }
        switch action {
        case .leftHalf: guard let l = layout("halves") else { return nil }; return (l, 0)
        case .rightHalf: guard let l = layout("halves") else { return nil }; return (l, 1)
        case .topHalf: guard let l = layout("vertical") else { return nil }; return (l, 0)
        case .bottomHalf: guard let l = layout("vertical") else { return nil }; return (l, 1)
        case .leftThird: guard let l = layout("thirds") else { return nil }; return (l, 0)
        case .middleThird: guard let l = layout("thirds") else { return nil }; return (l, 1)
        case .rightThird: guard let l = layout("thirds") else { return nil }; return (l, 2)
        case .twoThirdsLeft: guard let l = layout("twoThirdsLeft") else { return nil }; return (l, 0)
        case .twoThirdsRight: guard let l = layout("twoThirdsRight") else { return nil }; return (l, 1)
        case .maximize: guard let l = layout("full") else { return nil }; return (l, 0)
        case .center, .restore: return nil
        }
    }

    func zoneDisplayName(layout: SnapLayout, index: Int) -> String {
        switch (layout.id, index) {
        case ("halves", 0): return "左半屏"
        case ("halves", 1): return "右半屏"
        case ("vertical", 0): return "上半屏"
        case ("vertical", 1): return "下半屏"
        case ("thirds", 0): return "左 1/3"
        case ("thirds", 1): return "中 1/3"
        case ("thirds", 2): return "右 1/3"
        case ("twoThirdsLeft", 0): return "左 2/3"
        case ("twoThirdsLeft", 1): return "右 1/3"
        case ("twoThirdsRight", 0): return "左 1/3"
        case ("twoThirdsRight", 1): return "右 2/3"
        case ("quarters", 0): return "左上 1/4"
        case ("quarters", 1): return "右上 1/4"
        case ("quarters", 2): return "左下 1/4"
        case ("quarters", 3): return "右下 1/4"
        case ("full", 0): return "最大化"
        default: return "\(layout.id)#\(index)"
        }
    }

    // MARK: - 应用吸附（拖拽路径）

    private func applyRect(_ rect: CGRect, to win: AXWindow, name: String) {
        win.setNSFrame(rect)
        let screenName = activeScreen?.localizedName ?? "?"
        let desc = "\(name) · \(screenName)"
        AppLog.info("SNAP '\(win.title ?? "?")' → \(name) rect=\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))x\(Int(rect.height))")
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
