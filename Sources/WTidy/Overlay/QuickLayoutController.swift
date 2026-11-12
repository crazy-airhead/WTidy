import AppKit
import ApplicationServices

/// 快速布局（对齐原版 Quick Layout）：全局快捷键/菜单呼出图标条面板，
/// 点选图标（含图标内投影选区）即把前台窗口吸到对应区域。
/// 与拖拽路径互补——不拖动也能一键分屏。
final class QuickLayoutController: NSObject {
    static let shared = QuickLayoutController()

    weak var overlay: OverlayController?

    private var panel: NSPanel?
    private var escMonitor: Any?
    private var outsideMonitor: Any?

    func show() {
        guard let overlay = overlay else { return }
        guard AccessibilityService.isTrusted else {
            AppLog.warn("快速布局触发但缺少辅助功能权限")
            return
        }
        hide()  // 重复呼出=重新定位

        let width = CGFloat(Prefs.qlWidth)
        let height = CGFloat(Prefs.qlHeight)
        // 作用域过滤（对齐原版布局的 "All Screens" 概念）：只展示适用于光标所在屏的布局
        let screenID = screenAtMouse.flatMap { screenNumberOf($0) }
        let layouts = LayoutStore.displayLayouts(for: screenID)
        guard !layouts.isEmpty else { return }

        let view = QuickIconsView(layouts: layouts, controller: self)
        view.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))

        let p = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.contentView = view
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.isReleasedWhenClosed = false   // ARC 下防御性关闭（panel 默认 true）
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.setFrame(placementRect(width: width, height: height), display: true)
        p.orderFrontRegardless()
        panel = p
        installMonitors()
        AppLog.info("快速布局已呼出（\(layouts.count) 个布局）")
    }

    private func screenNumberOf(_ screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
    }

    func hide() {
        escMonitor.map { NSEvent.removeMonitor($0) }
        outsideMonitor.map { NSEvent.removeMonitor($0) }
        escMonitor = nil
        outsideMonitor = nil
        panel?.orderOut(nil)
        panel = nil
    }

    var isShowing: Bool { panel?.isVisible == true }

    /// 面板位置：光标附近（默认）或保存的屏幕位置系数
    private func placementRect(width: CGFloat, height: CGFloat) -> CGRect {
        guard let screen = screenAtMouse ?? NSScreen.main else { return .zero }
        let vf = screen.visibleFrame
        let origin: CGPoint
        if Prefs.qlNearCursor {
            let mouse = NSEvent.mouseLocation
            origin = CGPoint(x: min(max(mouse.x + 16, vf.minX), vf.maxX - width),
                             y: min(max(mouse.y - height - 12, vf.minY), vf.maxY - height))
        } else {
            origin = CGPoint(x: vf.minX + CGFloat(Prefs.qlPosX) * max(0, vf.width - width),
                             y: vf.maxY - CGFloat(Prefs.qlPosY) * max(0, vf.height - height) - height)
        }
        return CGRect(origin: origin, size: NSSize(width: width, height: height)).integral
    }

    private var screenAtMouse: NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
    }

    private func installMonitors() {
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {  // Esc
                self?.hide()
                return nil
            }
            return event
        }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }

    // MARK: - 点选（由 QuickIconsView 调用）

    fileprivate func handleClick(layoutIndex: Int, normalizedPoint: CGPoint) {
        guard let overlay = overlay else { return }
        let layouts = LayoutStore.layouts
        guard layouts.indices.contains(layoutIndex) else { return }
        let layout = layouts[layoutIndex]
        let zone = SnapEngine.zoneIndexInIcon(nx: normalizedPoint.x, ny: normalizedPoint.y, layout: layout) ?? 0
        if overlay.snapFrontmost(layout: layout, zoneIndex: zone) {
            hide()
        }
    }
}

/// 快速布局面板内容视图：图标网格，接受点击（与拖拽条不同，这里是交互面板）
final class QuickIconsView: NSView {
    private let layouts: [TidyLayout]
    private let controller: QuickLayoutController
    private var iconRects: [CGRect] = []

    init(layouts: [TidyLayout], controller: QuickLayoutController) {
        self.layouts = layouts
        self.controller = controller
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError(L("init(coder:) 未实现")) }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        computeIcons()
    }

    private func computeIcons() {
        let count = CGFloat(max(1, layouts.count))
        let boundsW = bounds.width
        let boundsH = bounds.height
        let cols = min(count, max(1, floor(boundsW / 150)))
        let rows = ceil(count / cols)
        let cellW = boundsW / cols
        let cellH = boundsH / rows
        let pad: CGFloat = 14

        iconRects = (0..<layouts.count).map { i in
            let col = CGFloat(i % Int(cols))
            let row = CGFloat(i / Int(cols))
            let w = cellW - pad * 2
            let h = cellH - pad * 2
            let x = col * cellW + pad
            let y = row * cellH + pad
            return CGRect(x: x, y: y, width: w, height: h)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // 底卡
        let card = bounds.insetBy(dx: 6, dy: 6)
        let cardPath = NSBezierPath(roundedRect: card, xRadius: 14, yRadius: 14)
        NSColor.black.withAlphaComponent(0.62).setFill()
        cardPath.fill()

        for (i, layout) in layouts.enumerated() {
            guard iconRects.indices.contains(i) else { continue }
            LayoutIconRenderer.draw(layout: layout,
                                    in: iconRects[i],
                                    flipped: true,   // 本视图翻转坐标
                                    showName: true)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        for (i, r) in iconRects.enumerated() where r.contains(location) {
            let nx = (location.x - r.minX) / max(r.width, 1)
            let ny = (location.y - r.minY) / max(r.height, 1)  // 视图 flipped，ny 原点在顶 ✓
            controller.handleClick(layoutIndex: i, normalizedPoint: CGPoint(x: nx, y: ny))
            return
        }
    }
}
