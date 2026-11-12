import AppKit

/// 设置窗口。
/// 故意不用 Auto Layout 撑尺寸：NSTabView 直接 autoresizing 贴满窗口内容区，
/// 各 tab 页内部只用「单边/居中」约束（和引导窗口同款、已验证可靠的模式）。
/// —— 此前两版（手动约束 NSTabView、NSTabViewController）都因根视图缺少尺寸
///    约束而内容塌陷错位，教训：tab 容器一律用 frame + autoresizingMask。
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private let window: NSWindow
    private let tabView = NSTabView()

    // 通用页控件
    private let dragCheck = NSButton(checkboxWithTitle: "启用拖拽分屏", target: nil, action: nil)
    private let hotkeyCheck = NSButton(checkboxWithTitle: "启用全局快捷键", target: nil, action: nil)
    private let loginCheck = NSButton(checkboxWithTitle: "开机自动启动", target: nil, action: nil)
    private let gapSegment = NSSegmentedControl(labels: ["贴合", "4pt", "8pt", "12pt"],
                                                trackingMode: .selectOne, target: nil, action: nil)
    private let permissionRow = NSStackView()
    private var hotkeyToggles: [NSButton] = []

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 560),
                          styleMask: [.titled, .closable],
                          backing: .buffered, defer: false)
        super.init()

        window.title = "WTidy 设置"
        window.isReleasedWhenClosed = false
        window.delegate = self

        // tab 容器：frame + autoresizing，零约束
        tabView.frame = window.contentView!.bounds
        tabView.autoresizingMask = [.width, .height]
        tabView.font = .systemFont(ofSize: 13)
        tabView.addTabViewItem(generalTab())
        tabView.addTabViewItem(hotkeysTab())
        tabView.addTabViewItem(aboutTab())
        window.contentView?.addSubview(tabView)

        wireActions()
        refreshState()
    }

    func present() {
        refreshState()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Tab 页构建

    /// 页面容器 + 垂直布局栈（栈用单边约束，容器尺寸由窗口/tab 决定）
    private func makePage() -> (NSView, NSStackView) {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 580, height: 512))
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 24, bottom: 18, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor),
        ])
        return (content, stack)
    }

    private func generalTab() -> NSTabViewItem {
        let (content, stack) = makePage()

        let gapCaption = captionText("贴合为原版 Window Tidy 的行为；间距可让相邻窗口留出呼吸感。")
        stack.addArrangedSubview(sectionTitle("功能"))
        stack.addArrangedSubview(dragCheck)
        stack.addArrangedSubview(hotkeyCheck)
        stack.setCustomSpacing(18, after: hotkeyCheck)
        stack.addArrangedSubview(sectionTitle("窗口间隙"))
        stack.addArrangedSubview(gapSegment)
        stack.addArrangedSubview(gapCaption)
        stack.setCustomSpacing(18, after: gapCaption)
        stack.addArrangedSubview(sectionTitle("启动"))
        stack.addArrangedSubview(loginCheck)

        let warnIcon = NSImageView(image: NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                                                 accessibilityDescription: nil) ?? NSImage())
        warnIcon.contentTintColor = .systemYellow
        let warnText = NSTextField(labelWithString: "缺少辅助功能权限，功能未生效")
        warnText.font = .systemFont(ofSize: 12)
        let grantButton = NSButton(title: "去授权", target: self, action: #selector(grantClicked))
        permissionRow.orientation = .horizontal
        permissionRow.spacing = 8
        permissionRow.addArrangedSubview(warnIcon)
        permissionRow.addArrangedSubview(warnText)
        permissionRow.addArrangedSubview(grantButton)
        stack.addArrangedSubview(permissionRow)

        let item = NSTabViewItem(identifier: "general")
        item.label = "通用"
        item.view = content
        return item
    }

    private func hotkeysTab() -> NSTabViewItem {
        let (content, stack) = makePage()
        stack.spacing = 6

        for action in SnapAction.allCases {
            let name = NSTextField(labelWithString: action.displayName)
            name.font = .systemFont(ofSize: 12)
            let badge = keyBadge(action.keyDescription)
            let toggle = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleHotkeyRow(_:)))
            toggle.identifier = NSUserInterfaceItemIdentifier(action.rawValue)
            hotkeyToggles.append(toggle)

            let flexible = NSView()
            let row = NSStackView(views: [name, flexible, badge, toggle])
            row.orientation = .horizontal
            row.spacing = 8
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalToConstant: 500).isActive = true
            flexible.setContentHuggingPriority(.defaultLow, for: .horizontal)
            stack.addArrangedSubview(row)
        }
        stack.setCustomSpacing(16, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(captionText("快捷键与拖拽分屏互为补充；某些应用不支持拖拽感知时，快捷键仍可分屏。"))

        let item = NSTabViewItem(identifier: "hotkeys")
        item.label = "快捷键"
        item.view = content
        return item
    }

    private func aboutTab() -> NSTabViewItem {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 580, height: 512))

        let iconConfig = NSImage.SymbolConfiguration(pointSize: 48, weight: .light)
        let icon = NSImageView(image: NSImage(systemSymbolName: "rectangle.split.2x2", accessibilityDescription: nil)?
            .withSymbolConfiguration(iconConfig) ?? NSImage())
        icon.contentTintColor = .controlAccentColor

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let title = NSTextField(labelWithString: "WTidy \(version)")
        title.font = .systemFont(ofSize: 20, weight: .bold)
        let credit = NSTextField(labelWithString: "arm64 原生 · 看门狗自愈 · 现代登录项\n重制致敬 Window Tidy（Light Pillar, 2011–2017）")
        credit.alignment = .center
        credit.font = .systemFont(ofSize: 11)
        credit.textColor = .secondaryLabelColor

        let logPath = NSTextField(labelWithString: AppLog.shared.logPath.path)
        logPath.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        logPath.textColor = .secondaryLabelColor
        logPath.lineBreakMode = .byTruncatingMiddle
        logPath.preferredMaxLayoutWidth = 440
        let openLog = NSButton(title: "打开日志", target: self, action: #selector(openLogClicked))

        let stack = NSStackView(views: [icon, title, credit, logPath, openLog])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.setCustomSpacing(14, after: credit)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])

        let item = NSTabViewItem(identifier: "about")
        item.label = "关于"
        item.view = content
        return item
    }

    // MARK: - 状态刷新与动作

    private func wireActions() {
        dragCheck.target = self
        dragCheck.action = #selector(toggleDrag)
        hotkeyCheck.target = self
        hotkeyCheck.action = #selector(toggleHotkeys)
        loginCheck.target = self
        loginCheck.action = #selector(toggleLogin)
        gapSegment.target = self
        gapSegment.action = #selector(gapChanged)
    }

    private func refreshState() {
        dragCheck.state = Prefs.dragEnabled ? .on : .off
        hotkeyCheck.state = Prefs.hotkeysEnabled ? .on : .off
        loginCheck.state = (LoginItemController.isAvailable && LoginItemController.isEnabled) ? .on : .off
        loginCheck.isEnabled = LoginItemController.isAvailable
        switch Prefs.windowGap {
        case 0: gapSegment.selectedSegment = 0
        case 4: gapSegment.selectedSegment = 1
        case 8: gapSegment.selectedSegment = 2
        case 12: gapSegment.selectedSegment = 3
        default: gapSegment.selectedSegment = -1
        }
        permissionRow.isHidden = AccessibilityService.isTrusted
        for toggle in hotkeyToggles {
            guard let id = toggle.identifier?.rawValue else { continue }
            toggle.state = Prefs.hotkeyEnabled(id) ? .on : .off
        }
    }

    @objc private func toggleDrag() { Prefs.dragEnabled = dragCheck.state == .on }
    @objc private func toggleHotkeys() { Prefs.hotkeysEnabled = hotkeyCheck.state == .on }
    @objc private func toggleLogin() {
        LoginItemController.setEnabled(loginCheck.state == .on)
        loginCheck.state = LoginItemController.isEnabled ? .on : .off
    }
    @objc private func toggleHotkeyRow(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        Prefs.setHotkeyEnabled(sender.state == .on, id: id)
    }
    @objc private func gapChanged() {
        switch gapSegment.selectedSegment {
        case 0: Prefs.windowGap = 0
        case 1: Prefs.windowGap = 4
        case 2: Prefs.windowGap = 8
        case 3: Prefs.windowGap = 12
        default: break
        }
    }
    @objc private func grantClicked() { AccessibilityService.requestTrust() }
    @objc private func openLogClicked() { NSWorkspace.shared.open(AppLog.shared.logPath) }

    func windowDidBecomeKey(_ notification: Notification) {
        refreshState()
    }

    // MARK: - 小工具

    private func sectionTitle(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = .systemFont(ofSize: 13, weight: .semibold)
        return f
    }

    private func captionText(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = .systemFont(ofSize: 10)
        f.textColor = .secondaryLabelColor
        f.lineBreakMode = .byWordWrapping
        f.maximumNumberOfLines = 2
        return f
    }

    private func keyBadge(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        field.alignment = .center
        field.wantsLayer = true
        field.layer?.cornerRadius = 5
        field.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.25).cgColor
        field.layer?.masksToBounds = true
        field.widthAnchor.constraint(equalToConstant: max(48, CGFloat(text.count) * 10 + 18)).isActive = true
        return field
    }
}
