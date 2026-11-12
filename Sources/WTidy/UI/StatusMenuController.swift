import AppKit

/// 菜单栏状态项：三态图标 + 实时监听状态 + 最近吸附记录。
/// 状态可见化是本重制版的核心承诺——原版的病就是「静默死亡看不见」。
final class StatusMenuController: NSObject {
    enum State {
        case ok            // 正常监听（绿点）
        case noPermission  // 缺辅助功能权限（黄叹号）
        case paused        // 拖拽功能被用户关闭（灰）
    }

    struct Hooks {
        var openSettings: () -> Void
        var requestPermissions: () -> Void
        var restart: () -> Void
        var showQuickLayout: () -> Void
        var applyLayoutByID: (String) -> Void
        var restoreAllWindows: () -> Void
        var moveToActiveDisplay: () -> Void
    }

    private let statusItem: NSStatusItem
    private var hooks: Hooks?

    private let statusLine = NSMenuItem(title: "…", action: nil, keyEquivalent: "")
    private let lastSnapLine = NSMenuItem(title: "最近吸附：—", action: nil, keyEquivalent: "")
    private let dragToggle = NSMenuItem(title: "拖拽分屏", action: nil, keyEquivalent: "")
    private let hotkeyToggle = NSMenuItem(title: "全局快捷键", action: nil, keyEquivalent: "")
    private let loginToggle = NSMenuItem(title: "开机自动启动", action: nil, keyEquivalent: "")
    private let layoutSubmenu = NSMenuItem(title: "应用布局到前台窗口", action: nil, keyEquivalent: "")
    private let restoreAllItem = NSMenuItem(title: "恢复所有窗口位置", action: nil, keyEquivalent: "")
    private let moveToDisplayItem = NSMenuItem(title: "移动窗口到活动显示器", action: nil, keyEquivalent: "")
    /// attract 脉冲（对齐原版 attractState）：缺权限时图标闪烁引起注意
    private var attractTimer: Timer?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusLine.target = self
        statusLine.action = #selector(statusLineClicked)
        statusLine.isEnabled = true
        menu.addItem(statusLine)
        lastSnapLine.isEnabled = false
        menu.addItem(lastSnapLine)
        menu.addItem(.separator())

        dragToggle.target = self
        dragToggle.action = #selector(toggleDrag)
        dragToggle.isEnabled = true
        menu.addItem(dragToggle)
        hotkeyToggle.target = self
        hotkeyToggle.action = #selector(toggleHotkeys)
        hotkeyToggle.isEnabled = true
        menu.addItem(hotkeyToggle)
        menu.addItem(.separator())

        loginToggle.target = self
        loginToggle.action = #selector(toggleLogin)
        loginToggle.isEnabled = true
        menu.addItem(loginToggle)

        // 布局子菜单（原版主菜单的 Apply Layout）：打开时动态重建
        layoutSubmenu.submenu = NSMenu()
        layoutSubmenu.submenu?.delegate = self
        menu.addItem(layoutSubmenu)
        restoreAllItem.target = self
        restoreAllItem.action = #selector(restoreAllClicked)
        menu.addItem(restoreAllItem)
        moveToDisplayItem.target = self
        moveToDisplayItem.action = #selector(moveToDisplayClicked)
        menu.addItem(moveToDisplayItem)
        menu.addItem(.separator())

        let quickItem = NSMenuItem(title: "快速布局", action: #selector(showQuickLayout), keyEquivalent: "l")
        quickItem.target = self
        menu.addItem(quickItem)
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let logItem = NSMenuItem(title: "打开日志", action: #selector(openLog), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)
        menu.addItem(.separator())

        let restartItem = NSMenuItem(title: "重启 WTidy", action: #selector(restart), keyEquivalent: "r")
        restartItem.target = self
        menu.addItem(restartItem)
        let quitItem = NSMenuItem(title: "退出 WTidy", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        update(state: .ok)
        refreshToggles()
    }

    func configure(hooks: Hooks) {
        self.hooks = hooks
    }

    // MARK: - 状态更新

    func update(state: State) {
        attractTimer?.invalidate()
        attractTimer = nil
        switch state {
        case .ok:
            statusItem.button?.image = Self.symbolImage("rectangle.split.2x2", tint: nil, alpha: 1)
            statusItem.button?.alphaValue = 1
            statusLine.attributedTitle = Self.dotTitle("正常监听中", color: .systemGreen,
                                                       detail: "拖拽任意窗口顶部即可分屏")
        case .noPermission:
            statusItem.button?.image = Self.symbolImage("exclamationmark.triangle.fill", tint: .systemYellow, alpha: 1)
            statusLine.attributedTitle = Self.dotTitle("缺少辅助功能权限", color: .systemYellow,
                                                       detail: "点此打开系统设置授权")
            startAttractPulse()
        case .paused:
            statusItem.button?.image = Self.symbolImage("rectangle.split.2x2", tint: nil, alpha: 0.35)
            statusItem.button?.alphaValue = 1
            statusLine.attributedTitle = Self.dotTitle("拖拽分屏已暂停", color: .systemGray,
                                                       detail: "在下方开关中重新开启")
        }
    }

    /// attract 脉冲：0.6s 闪烁，授权后自动停止
    private func startAttractPulse() {
        let timer = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in
            guard let button = self?.statusItem.button else { return }
            button.alphaValue = button.alphaValue > 0.5 ? 0.35 : 1
        }
        RunLoop.main.add(timer, forMode: .common)
        attractTimer = timer
    }

    func setLastSnap(_ text: String) {
        lastSnapLine.title = "最近吸附：\(text)"
    }

    func refreshToggles() {
        dragToggle.state = Prefs.dragEnabled ? .on : .off
        hotkeyToggle.state = Prefs.hotkeysEnabled ? .on : .off
        if LoginItemController.isAvailable {
            loginToggle.state = LoginItemController.isEnabled ? .on : .off
        } else {
            loginToggle.isEnabled = false
            loginToggle.state = .off
            loginToggle.title = "开机自动启动（安装到 /Applications 后可用）"
        }
    }

    // MARK: - 动作

    @objc private func statusLineClicked() {
        if !AccessibilityService.isTrusted {
            hooks?.requestPermissions()
        } else {
            hooks?.openSettings()
        }
    }

    @objc private func toggleDrag() {
        Prefs.dragEnabled = !Prefs.dragEnabled
        refreshToggles()
        AppLog.info("拖拽分屏开关 → \(Prefs.dragEnabled)")
    }

    @objc private func toggleHotkeys() {
        Prefs.hotkeysEnabled = !Prefs.hotkeysEnabled
        refreshToggles()
        AppLog.info("快捷键开关 → \(Prefs.hotkeysEnabled)")
    }

    @objc private func toggleLogin() {
        LoginItemController.setEnabled(!LoginItemController.isEnabled)
        refreshToggles()
    }

    @objc private func openSettings() { hooks?.openSettings() }

    @objc private func showQuickLayout() { hooks?.showQuickLayout() }

    /// Options：「Show Window Tidy status icon」
    func setVisible(_ visible: Bool) {
        statusItem.isVisible = visible
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(AppLog.shared.logPath)
    }

    @objc private func restart() { hooks?.restart() }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - 图标与文案

    private static func symbolImage(_ name: String, tint: NSColor?, alpha: CGFloat) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: "WTidy") else { return nil }
        guard let tint = tint else {
            base.isTemplate = true
            return base
        }
        let img = NSImage(size: base.size)
        img.lockFocus()
        let rect = CGRect(origin: .zero, size: base.size)
        base.draw(in: rect)
        tint.setFill()
        rect.fill(using: .sourceAtop)
        img.unlockFocus()
        return img
    }

    private static func dotTitle(_ text: String, color: NSColor, detail: String) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: "● ", attributes: [
            .foregroundColor: color, .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .paragraphStyle: para,
        ]))
        s.append(NSAttributedString(string: text + "  ", attributes: [
            .font: NSFont.menuFont(ofSize: 13),
            .paragraphStyle: para,
        ]))
        s.append(NSAttributedString(string: detail, attributes: [
            .foregroundColor: NSColor.secondaryLabelColor,
            .font: NSFont.menuFont(ofSize: 11),
            .paragraphStyle: para,
        ]))
        return s
    }
}

extension StatusMenuController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === layoutSubmenu.submenu {
            rebuildLayoutSubmenu(menu)
            return
        }
        refreshToggles()
        update(state: currentRenderState)
    }

    /// 布局子菜单：每次打开重建（对齐原版 Apply Layout，作用于最前窗口）
    private func rebuildLayoutSubmenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let layouts = LayoutStore.displayLayouts(for: nil)
        let trusted = AccessibilityService.isTrusted
        if layouts.isEmpty {
            let empty = NSMenuItem(title: "（无布局，请在设置的「布局」页添加）", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }
        for layout in layouts {
            let item = NSMenuItem(title: layout.name, action: #selector(applyLayoutClicked), keyEquivalent: "")
            item.target = self
            item.identifier = NSUserInterfaceItemIdentifier(layout.id)
            item.isEnabled = trusted
            let icon = NSImage(size: NSSize(width: 36, height: 20))
            icon.lockFocus()
            let inner = NSRect(x: 1, y: 1, width: 34, height: 18)
            for nr in layout.normalizedRects {
                let r = NSRect(x: inner.minX + nr.minX * inner.width,
                               y: inner.minY + (1 - nr.maxY) * inner.height,
                               width: nr.width * inner.width,
                               height: nr.height * inner.height)
                NSColor.controlAccentColor.withAlphaComponent(0.8).setFill()
                NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2).fill()
            }
            icon.unlockFocus()
            item.image = icon
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let manage = NSMenuItem(title: "管理布局…", action: #selector(openSettings), keyEquivalent: "")
        manage.target = self
        menu.addItem(manage)
    }

    @objc private func applyLayoutClicked(_ sender: NSMenuItem) {
        guard let id = sender.identifier?.rawValue else { return }
        hooks?.applyLayoutByID(id)
    }

    @objc private func restoreAllClicked() { hooks?.restoreAllWindows() }

    @objc private func moveToDisplayClicked() { hooks?.moveToActiveDisplay() }

    private var currentRenderState: State {
        if !AccessibilityService.isTrusted { return .noPermission }
        if !Prefs.dragEnabled { return .paused }
        return .ok
    }
}
