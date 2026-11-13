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
    /// 当前屏实际展示的布局（作用域过滤 + 自动分组后）
    private var visibleLayouts: [TidyLayout] = []

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
        visibleLayouts = LayoutStore.displayLayouts(for: activeScreenNumber)
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
            visibleLayouts = LayoutStore.displayLayouts(for: activeScreenNumber)
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
        if let i = stripIndex(at: cursor), visibleLayouts.indices.contains(i) {
            let layout = visibleLayouts[i]
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

        let hoveredStrip = stripShouldShow ? stripIndex(at: cursor) : nil
        if let i = hoveredStrip, visibleLayouts.indices.contains(i) {
            let layout = visibleLayouts[i]
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

        if stripShouldShow {
            model.strip = stripRectsGlobal.indices.map { i in
                (rect: stripRectsGlobal[i],
                 layout: visibleLayouts[i],
                 activeRegion: hoveredStrip == i ? activeZoneIndex : nil)
            }
        } else {
            model.strip = []
        }
        model.hoveredStripIndex = hoveredStrip

        if activeLayout != nil {
            model.veilRect = screen.frame
            model.zones = zonesGlobal
            model.hoveredZoneIndex = activeZoneIndex
        }

        window(for: screen).overlayView.model = model
    }

    /// 图标条摆放：几何统一走 StripGeometry（与「定位」页预览共用，预览即真实）
    private func computeStripRects(screen: NSScreen) {
        stripRectsGlobal = StripGeometry.iconRects(layoutCount: visibleLayouts.count,
                                                   in: screen.visibleFrame)
    }

    /// ⌥ 键当前是否按住（对齐原版「按住 ⌥ 隐藏/显示 Layout Icons」）
    private var optionKeyHeld: Bool {
        CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate)
    }

    /// ⌥ 模式下当前图标条是否应显示
    private var stripShouldShow: Bool {
        switch Prefs.optionKeyMode {
        case 0: return !optionKeyHeld   // 按住 ⌥ 隐藏
        case 1: return optionKeyHeld    // 按住 ⌥ 显示
        default: return true
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

        switch action {
        case .restore:
            let key = win.memoryKey
            guard let original = frameMemory.recall(key: key) else {
                AppLog.info("恢复位置：没有 '\(win.title ?? "?")' 的历史记录")
                return
            }
            WindowAnimator.apply(win, to: original) { [weak self] in
                self?.onSnapApplied?(LF("恢复原位置 · %@", screen.localizedName))
            }
            frameMemory.remove(key: key)

        case .center:
            guard let size = win.nsFrame?.size else { return }
            rememberIfNeeded(win)
            let rect = SnapEngine.centeredRect(size: size, in: vf)
            WindowAnimator.apply(win, to: rect) { [weak self] in
                self?.onSnapApplied?(LF("居中（保持尺寸） · %@", screen.localizedName))
            }
        }
    }

    private func rememberIfNeeded(_ win: AXWindow) {
        guard let f = win.nsFrame else { return }
        if frameMemory.recall(key: win.memoryKey) == nil {
            frameMemory.remember(key: win.memoryKey, frame: f)
        }
    }

    /// 供快速布局/菜单调用：把前台窗口吸到指定布局的指定区域
    @discardableResult
    func snapFrontmost(layout: TidyLayout, zoneIndex: Int) -> Bool {
        guard AccessibilityService.isTrusted else { return false }
        guard let win = ax.frontmostWindow(), win.canSnap else { return false }
        guard let screen = screenForWindow(win) else { return false }
        let zones = SnapEngine.zoneRects(for: layout, in: screen.visibleFrame, gap: Prefs.windowGap)
        guard zones.indices.contains(zoneIndex), !zones[zoneIndex].isNull else { return false }
        rememberIfNeeded(win)
        let desc = "\(zoneDisplayName(layout: layout, index: zoneIndex)) · \(screen.localizedName)"
        WindowAnimator.apply(win, to: zones[zoneIndex]) { [weak self] in
            AppLog.info("SNAP '\(win.title ?? "?")' → \(desc)")
            self?.onSnapApplied?(desc)
        }
        return true
    }

    /// 菜单「应用布局」：区域由窗口中心在屏内的归一化位置投影决定
    /// （窗口在左半屏时应用「左右半屏」会落到左半区，符合直觉）
    @discardableResult
    func applyLayoutToWindow(_ layout: TidyLayout) -> Bool {
        guard AccessibilityService.isTrusted else { return false }
        guard let win = ax.frontmostWindow(), win.canSnap else { return false }
        guard let screen = screenForWindow(win) else { return false }
        let vf = screen.visibleFrame
        var zone = 0
        if let frame = win.nsFrame {
            let nx = (frame.midX - vf.minX) / max(vf.width, 1)
            let ny = (vf.maxY - frame.midY) / max(vf.height, 1)   // 原点左上
            zone = SnapEngine.zoneIndexInIcon(nx: min(max(nx, 0), 0.999),
                                              ny: min(max(ny, 0), 0.999),
                                              layout: layout) ?? 0
        }
        return snapFrontmost(layout: layout, zoneIndex: zone)
    }

    /// 菜单「应用布局」按 id 查找（兼容自动分组产生的合并 id）
    @discardableResult
    func applyLayoutByID(_ id: String) -> Bool {
        let display = LayoutStore.displayLayouts(for: nil)
        let layout = display.first { $0.id == id } ?? LayoutStore.layout(id: id)
        guard let layout = layout else { return false }
        return applyLayoutToWindow(layout)
    }

    /// 菜单「恢复所有窗口」：把本次会话内吸附过的窗口全部还原到吸附前位置
    func restoreAllWindows() {
        guard AccessibilityService.isTrusted else { return }
        var restored = 0
        let memory = frameMemory.store
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            guard let value = axCopyValue(element, "AXWindows" as String) else { continue }
            guard let windows = value as? [AXUIElement] else { continue }
            for w in windows {
                let axWin = AXWindow(element: w, pid: app.processIdentifier)
                let key = axWin.memoryKey
                guard memory.keys.contains(key), let original = memory[key] else { continue }
                axWin.setNSFrame(original)
                frameMemory.remove(key: key)
                restored += 1
            }
        }
        AppLog.info("恢复所有窗口：\(restored) 个")
        onSnapApplied?(LF("已恢复 %d 个窗口原位置", restored))
    }

    /// 菜单「发送窗口到另一块屏幕」：把前台窗口发送到它当前不在的那块屏，
    /// 保持相对位置与尺寸比例。双屏时目标唯一；多屏时取鼠标所在屏作为目标。
    @discardableResult
    func moveFrontmostToOtherDisplay() -> Bool {
        guard AccessibilityService.isTrusted else { return false }
        guard let win = ax.frontmostWindow(), win.canSnap, let frame = win.nsFrame else { return false }
        guard let fromScreen = screenForWindow(win) else { return false }

        let others = NSScreen.screens.filter { screenNumber(of: $0) != screenNumber(of: fromScreen) }
        guard !others.isEmpty else {
            onSnapApplied?(L("没有其他显示器可发送"))
            return false
        }
        let toScreen = others.count == 1
            ? others[0]
            : (screenForPoint(NSEvent.mouseLocation) ?? others[0])
        let fromVF = fromScreen.visibleFrame
        let toVF = toScreen.visibleFrame
        // 相对位置比例映射 + 尺寸限制在目标屏内
        let relX = (frame.midX - fromVF.minX) / max(fromVF.width, 1)
        let relY = (fromVF.maxY - frame.midY) / max(fromVF.height, 1)
        let w = min(frame.width, toVF.width)
        let h = min(frame.height, toVF.height)
        let x = toVF.minX + relX * toVF.width - w / 2
        let yTop = toVF.minY + relY * toVF.height + h / 2
        let target = CGRect(x: x, y: yTop - h, width: w, height: h).intersection(toVF)
        rememberIfNeeded(win)
        let desc = LF("已移动到 %@", toScreen.localizedName)
        WindowAnimator.apply(win, to: target) { [weak self] in
            AppLog.info("MOVE '\(win.title ?? "?")' → \(desc)")
            self?.onSnapApplied?(desc)
        }
        return true
    }

    func zoneDisplayName(layout: TidyLayout, index: Int) -> String {
        // 内置区域名按内置表下标定义；用户列表里区域先后可能不同，先按几何位置换算
        // （对不上内置表的——分区被改过——落到 default 用通用命名）
        switch (layout.id, layout.builtinRegionIndex(index)) {
        case ("halves", 0): return L("左半屏")
        case ("halves", 1): return L("右半屏")
        case ("vertical", 0): return L("上半屏")
        case ("vertical", 1): return L("下半屏")
        case ("thirds", 0): return L("左 1/3")
        case ("thirds", 1): return L("中 1/3")
        case ("thirds", 2): return L("右 1/3")
        case ("narrowWide", 0): return L("左 1/3")
        case ("narrowWide", 1): return L("右 2/3")
        case ("wideNarrow", 0): return L("左 2/3")
        case ("wideNarrow", 1): return L("右 1/3")
        case ("quarters", 0): return L("左上 1/4")
        case ("quarters", 1): return L("右上 1/4")
        case ("quarters", 2): return L("左下 1/4")
        case ("quarters", 3): return L("右下 1/4")
        case ("full", 0): return L("最大化")
        case ("center", 0): return L("居中")
        default:
            if layout.regions.count > 1 {
                // 自动分组合并的布局（id 形如 a+b，名称形如 L("甲 / 乙")）：按区域取对应名称
                if layout.id.contains("+") {
                    let names = layout.name.components(separatedBy: " / ")
                    if names.indices.contains(index) { return names[index] }
                }
                return LF("%1$@ 区域%2$d", layout.name, index + 1)
            }
            return layout.name
        }
    }

    // MARK: - 应用吸附（拖拽路径）

    private func applyRect(_ rect: CGRect, to win: AXWindow, layout: TidyLayout, zoneIndex: Int) {
        let screenName = activeScreen?.localizedName ?? "?"
        var desc = "\(zoneDisplayName(layout: layout, index: zoneIndex)) · \(screenName)"

        // 动画吸附（原版 AnimateWindows）；完成后读回 frame 检测偏差
        WindowAnimator.apply(win, to: rect) { [weak self] in
            guard let self = self else { return }
            if let actual = win.nsFrame {
                let deviation = max(abs(actual.minX - rect.minX), abs(actual.minY - rect.minY),
                                    abs(actual.width - rect.width), abs(actual.height - rect.height))
                if deviation > 5 {
                    AppLog.warn("SNAP 偏差 \(Int(deviation))pt '\(win.title ?? "?")' 目标=\(rect) 实际=\(actual)")
                    if Prefs.warnOnFail {
                        desc = LF("⚠️ 未能完全调整尺寸（偏差 %dpt）— ", Int(deviation)) + desc
                    }
                }
            }
            AppLog.info("SNAP '\(win.title ?? "?")' → \(desc)")
            self.onSnapApplied?(desc)
        }
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
