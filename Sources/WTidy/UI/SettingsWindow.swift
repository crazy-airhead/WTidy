import AppKit

/// 设置窗口（纯 AppKit——CLT 工具链无 SwiftUI 宏插件）。
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private var dragCheckbox: NSButton!
    private var hotkeyCheckbox: NSButton!
    private var loginCheckbox: NSButton!
    private var gapSegment: NSSegmentedControl!
    private var permissionRow: NSStackView!

    private init() {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
                           styleMask: [.titled, .closable],
                           backing: .buffered, defer: false)
        win.title = "WTidy 设置"
        win.isReleasedWhenClosed = false
        win.center()
        super.init(window: win)

        let tabBar = NSTabView()
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        tabBar.addTabViewItem(tabItem("通用", identifier: "general") { GeneralTab(controller: self) })
        tabBar.addTabViewItem(tabItem("快捷键", identifier: "hotkeys") { HotkeysTab() })
        tabBar.addTabViewItem(tabItem("关于", identifier: "about") { AboutTab() })

        win.contentView = tabBar
        win.contentView?.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: win.contentView!.topAnchor, constant: 12),
            tabBar.bottomAnchor.constraint(equalTo: win.contentView!.bottomAnchor, constant: -12),
            tabBar.leadingAnchor.constraint(equalTo: win.contentView!.leadingAnchor, constant: 16),
            tabBar.trailingAnchor.constraint(equalTo: win.contentView!.trailingAnchor, constant: -16),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }

    func present() {
        refreshState()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func refreshState() {
        guard dragCheckbox != nil else { return }
        dragCheckbox.state = Prefs.dragEnabled ? .on : .off
        hotkeyCheckbox.state = Prefs.hotkeysEnabled ? .on : .off
        loginCheckbox.state = (LoginItemController.isAvailable && LoginItemController.isEnabled) ? .on : .off
        loginCheckbox.isEnabled = LoginItemController.isAvailable
        let gap = Prefs.windowGap
        switch gap {
        case 0: gapSegment.selectedSegment = 0
        case 4: gapSegment.selectedSegment = 1
        case 8: gapSegment.selectedSegment = 2
        case 12: gapSegment.selectedSegment = 3
        default: gapSegment.selectedSegment = -1
        }
        permissionRow.isHidden = AccessibilityService.isTrusted
    }

    private func tabItem(_ label: String, identifier: String, build: @escaping () -> NSView) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: identifier)
        item.label = label
        item.view = build()
        return item
    }

    // MARK: - 通用页

    private class GeneralTab: NSView {
        weak var controller: SettingsWindowController?

        init(controller: SettingsWindowController) {
            self.controller = controller
            super.init(frame: .zero)

            let stack = NSStackView()
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 10
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
                stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            ])

            stack.addArrangedSubview(sectionTitle("功能"))
            controller.dragCheckbox = NSButton(checkboxWithTitle: "启用拖拽分屏",
                                               target: controller, action: #selector(SettingsWindowController.toggleDrag))
            stack.addArrangedSubview(controller.dragCheckbox)
            controller.hotkeyCheckbox = NSButton(checkboxWithTitle: "启用全局快捷键",
                                                 target: controller, action: #selector(SettingsWindowController.toggleHotkeys))
            stack.addArrangedSubview(controller.hotkeyCheckbox)

            stack.addArrangedSubview(spacer())
            stack.addArrangedSubview(sectionTitle("窗口间隙"))
            controller.gapSegment = NSSegmentedControl(labels: ["贴合", "4pt", "8pt", "12pt"],
                                                       trackingMode: .selectOne,
                                                       target: controller,
                                                       action: #selector(SettingsWindowController.gapChanged))
            stack.addArrangedSubview(controller.gapSegment)
            stack.addArrangedSubview(captionText("贴合为原版 Window Tidy 的行为；间距可让相邻窗口留出呼吸感。"))

            stack.addArrangedSubview(spacer())
            stack.addArrangedSubview(sectionTitle("启动"))
            controller.loginCheckbox = NSButton(checkboxWithTitle: "开机自动启动",
                                                target: controller, action: #selector(SettingsWindowController.toggleLogin))
            stack.addArrangedSubview(controller.loginCheckbox)
            if !LoginItemController.isAvailable {
                stack.addArrangedSubview(captionText("开发模式：把 WTidy.app 放入 /Applications 后可启用。"))
            }

            // 权限告警行（未授权时显示）
            let warnIcon = NSImageView(image: NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                                                      accessibilityDescription: nil) ?? NSImage())
            warnIcon.contentTintColor = .systemYellow
            let warnText = NSTextField(labelWithString: "缺少辅助功能权限，功能未生效")
            warnText.font = .systemFont(ofSize: 12)
            let grantButton = NSButton(title: "去授权", target: self, action: #selector(grantClicked))
            controller.permissionRow = NSStackView(views: [warnIcon, warnText, grantButton])
            controller.permissionRow.spacing = 8
            stack.addArrangedSubview(controller.permissionRow)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }

        @objc private func grantClicked() {
            AccessibilityService.requestTrust()
        }
    }

    // MARK: - 快捷键页

    private class HotkeysTab: NSView {
        init() {
            super.init(frame: .zero)

            let stack = NSStackView()
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 6
            stack.translatesAutoresizingMaskIntoConstraints = false

            for action in SnapAction.allCases {
                let name = NSTextField(labelWithString: action.displayName)
                name.font = .systemFont(ofSize: 12)
                let badge = keyBadge(action.keyDescription)
                let toggle = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggle(_:)))
                toggle.state = Prefs.hotkeyEnabled(action.rawValue) ? .on : .off
                toggle.identifier = NSUserInterfaceItemIdentifier(action.rawValue)

                let spacer = NSView()
                spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
                let row = NSStackView(views: [name, spacer, badge, toggle])
                row.orientation = .horizontal
                row.spacing = 8
                row.distribution = .fill
                stack.addArrangedSubview(row)
            }

            let caption = captionText("快捷键与拖拽分屏互为补充；某些应用不支持拖拽感知时，快捷键仍可分屏。")

            let scroll = NSScrollView()
            scroll.documentView = stack
            scroll.hasVerticalScroller = true
            scroll.translatesAutoresizingMaskIntoConstraints = false
            scroll.drawsBackground = false

            let container = NSStackView()
            container.orientation = .vertical
            container.spacing = 8
            container.translatesAutoresizingMaskIntoConstraints = false
            container.addArrangedSubview(scroll)
            container.addArrangedSubview(caption)

            addSubview(container)
            NSLayoutConstraint.activate([
                container.topAnchor.constraint(equalTo: topAnchor, constant: 12),
                container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
                container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                stack.widthAnchor.constraint(greaterThanOrEqualTo: scroll.widthAnchor, constant: -20),
                stack.heightAnchor.constraint(greaterThanOrEqualTo: scroll.heightAnchor, constant: -8),
            ])
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }

        @objc private func toggle(_ sender: NSButton) {
            guard let id = sender.identifier?.rawValue else { return }
            Prefs.setHotkeyEnabled(sender.state == .on, id: id)
        }

        private func keyBadge(_ text: String) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            field.alignment = .center
            field.wantsLayer = true
            field.layer?.cornerRadius = 5
            field.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.25).cgColor
            field.layer?.masksToBounds = true
            let width = max(44, CGFloat(text.count) * 10 + 16)
            field.widthAnchor.constraint(equalToConstant: width).isActive = true
            return field
        }
    }

    // MARK: - 关于页

    private class AboutTab: NSView {
        init() {
            super.init(frame: .zero)

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
            let openLog = NSButton(title: "打开日志", target: nil, action: #selector(AppDelegate.openLogFromAbout))
            openLog.target = AppDelegate.self

            let stack = NSStackView(views: [icon, title, credit, logPath, openLog])
            stack.orientation = .vertical
            stack.alignment = .centerX
            stack.spacing = 10
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }
    }

    // MARK: - 动作

    @objc private func toggleDrag() {
        Prefs.dragEnabled = dragCheckbox.state == .on
    }

    @objc private func toggleHotkeys() {
        Prefs.hotkeysEnabled = hotkeyCheckbox.state == .on
    }

    @objc private func toggleLogin() {
        LoginItemController.setEnabled(loginCheckbox.state == .on)
        refreshState()
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

    // MARK: - 小工具

    private class func sectionTitle(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = .systemFont(ofSize: 13, weight: .semibold)
        return f
    }

    private class func captionText(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = .systemFont(ofSize: 10)
        f.textColor = .secondaryLabelColor
        f.lineBreakMode = .byWordWrapping
        f.maximumNumberOfLines = 2
        return f
    }

    private class func spacer() -> NSView {
        let v = NSView()
        v.heightAnchor.constraint(equalToConstant: 8).isActive = true
        return v
    }
}

extension AppDelegate {
    @objc static func openLogFromAbout() {
        NSWorkspace.shared.open(AppLog.shared.logPath)
    }
}
