import AppKit

/// 设置窗口：NSTabViewController(.toolbar) 标准模式——标签在窗口顶部工具栏，
/// 每个 tab 是独立 NSViewController，窗口尺寸由内容驱动。
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let tabVC = SettingsTabViewController()
        let win = NSWindow(contentViewController: tabVC)
        win.styleMask = [.titled, .closable]
        win.title = "WTidy 设置"
        win.isReleasedWhenClosed = false
        super.init(window: win)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Tab 容器

final class SettingsTabViewController: NSTabViewController {
    init() {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar

        let general = NSTabViewItem(viewController: GeneralSettingsViewController())
        general.label = "通用"
        general.identifier = "general"
        addTabViewItem(general)

        let hotkeys = NSTabViewItem(viewController: HotkeysSettingsViewController())
        hotkeys.label = "快捷键"
        hotkeys.identifier = "hotkeys"
        addTabViewItem(hotkeys)

        let about = NSTabViewItem(viewController: AboutSettingsViewController())
        about.label = "关于"
        about.identifier = "about"
        addTabViewItem(about)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = NSSize(width: 560, height: 460)
    }
}

// MARK: - 内容构造小工具

private func makeRow(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
    let s = NSStackView(views: views)
    s.orientation = .horizontal
    s.spacing = spacing
    s.alignment = .centerY
    return s
}

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

// MARK: - 通用页

final class GeneralSettingsViewController: NSViewController {
    private let dragCheck = NSButton(checkboxWithTitle: "启用拖拽分屏", target: nil, action: nil)
    private let hotkeyCheck = NSButton(checkboxWithTitle: "启用全局快捷键", target: nil, action: nil)
    private let loginCheck = NSButton(checkboxWithTitle: "开机自动启动", target: nil, action: nil)
    private let gapSegment = NSSegmentedControl(labels: ["贴合", "4pt", "8pt", "12pt"],
                                                trackingMode: .selectOne, target: nil, action: nil)
    private let permissionRow = makeRow([
        {
            let icon = NSImageView(image: NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                                                 accessibilityDescription: nil) ?? NSImage())
            icon.contentTintColor = .systemYellow
            return icon
        }(),
        {
            let t = NSTextField(labelWithString: "缺少辅助功能权限，功能未生效")
            t.font = .systemFont(ofSize: 12)
            return t
        }(),
    ])

    override func loadView() {
        gapSegment.target = self
        gapSegment.action = #selector(gapChanged)
        dragCheck.target = self
        dragCheck.action = #selector(toggleDrag)
        hotkeyCheck.target = self
        hotkeyCheck.action = #selector(toggleHotkeys)
        loginCheck.target = self
        loginCheck.action = #selector(toggleLogin)

        let grantButton = NSButton(title: "去授权", target: self, action: #selector(grantClicked))
        permissionRow.addArrangedSubview(grantButton)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        stack.addArrangedSubview(sectionTitle("功能"))
        stack.addArrangedSubview(dragCheck)
        stack.addArrangedSubview(hotkeyCheck)
        stack.addArrangedSubview(sectionTitle("窗口间隙"))
        stack.addArrangedSubview(gapSegment)
        stack.addArrangedSubview(captionText("贴合为原版 Window Tidy 的行为；间距可让相邻窗口留出呼吸感。"))
        stack.addArrangedSubview(sectionTitle("启动"))
        stack.addArrangedSubview(loginCheck)
        stack.setCustomSpacing(18, after: hotkeyCheck)
        stack.setCustomSpacing(18, after: captionText("贴合为原版 Window Tidy 的行为；间距可让相邻窗口留出呼吸感。"))
        stack.addArrangedSubview(permissionRow)

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            stack.widthAnchor.constraint(equalToConstant: 540),
        ])

        view = container
        preferredContentSize = NSSize(width: 560, height: 460)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
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
    }

    @objc private func toggleDrag() { Prefs.dragEnabled = dragCheck.state == .on }
    @objc private func toggleHotkeys() { Prefs.hotkeysEnabled = hotkeyCheck.state == .on }
    @objc private func toggleLogin() {
        LoginItemController.setEnabled(loginCheck.state == .on)
        loginCheck.state = LoginItemController.isEnabled ? .on : .off
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
}

// MARK: - 快捷键页

final class HotkeysSettingsViewController: NSViewController {
    private var stack: NSStackView!

    override func loadView() {
        stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 8, right: 20)

        for action in SnapAction.allCases {
            let name = NSTextField(labelWithString: action.displayName)
            name.font = .systemFont(ofSize: 12)
            let badge = keyBadge(action.keyDescription)
            let toggle = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggle(_:)))
            toggle.identifier = NSUserInterfaceItemIdentifier(action.rawValue)

            let flexible = NSView()
            let row = makeRow([name, flexible, badge, toggle], spacing: 8)
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalToConstant: 500).isActive = true
            flexible.setContentHuggingPriority(.defaultLow, for: .horizontal)
            stack.addArrangedSubview(row)
        }

        let caption = captionText("快捷键与拖拽分屏互为补充；某些应用不支持拖拽感知时，快捷键仍可分屏。")
        stack.addArrangedSubview(caption)
        stack.setCustomSpacing(14, after: stack.arrangedSubviews.last!)

        let container = NSView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
        ])

        view = container
        preferredContentSize = NSSize(width: 560, height: 460)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshToggles()
    }

    private func refreshToggles() {
        for row in stack.arrangedSubviews where row is NSStackView {
            for case let toggle as NSButton in (row as! NSStackView).arrangedSubviews
            where toggle.identifier != nil {
                guard let id = toggle.identifier?.rawValue else { continue }
                toggle.state = Prefs.hotkeyEnabled(id) ? .on : .off
            }
        }
    }

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
        field.widthAnchor.constraint(equalToConstant: max(48, CGFloat(text.count) * 10 + 18)).isActive = true
        return field
    }
}

// MARK: - 关于页

final class AboutSettingsViewController: NSViewController {
    override func loadView() {
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
        logPath.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let openLog = NSButton(title: "打开日志", target: self, action: #selector(openLogClicked))

        let stack = NSStackView(views: [icon, title, credit, logPath, openLog])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.setCustomSpacing(14, after: credit)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            logPath.widthAnchor.constraint(lessThanOrEqualToConstant: 440),
        ])

        view = container
        preferredContentSize = NSSize(width: 560, height: 460)
    }

    @objc private func openLogClicked() {
        NSWorkspace.shared.open(AppLog.shared.logPath)
    }
}
