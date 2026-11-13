import AppKit

/// 首次启动 / 授权丢失时展示的引导窗口（纯 AppKit——CLT 工具链无 SwiftUI 宏插件）。
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    static let shared = OnboardingWindowController()

    var onDone: (() -> Void)?

    private var pollTimer: Timer?
    private var trustStatusLabel: NSTextField!
    private var authorizeButton: NSButton!
    private var doneButton: NSButton!
    private var loginCheckbox: NSButton!

    private init() {
        // 560 宽：英文按钮「Authorize in System Settings」+ 步骤文案实测需 440pt 行宽，
        // 500 宽会把英文步骤行挤爆（图标与右侧控件重叠、按钮顶出卡片外）
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 430),
                           styleMask: [.titled, .closable],
                           backing: .buffered, defer: false)
        win.title = L("欢迎使用 WTidy")
        win.isReleasedWhenClosed = false
        win.center()
        super.init(window: win)
        win.delegate = self
        win.contentView = buildContent()
    }

    required init?(coder: NSCoder) { fatalError(L("init(coder:) 未实现")) }

    func present() {
        refreshTrustUI()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        startPolling()
    }

    func windowWillClose(_ notification: Notification) {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func startPolling() {
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshTrustUI()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    // MARK: - UI 构建

    private func buildContent() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = Design.Spacing.cardGap
        stack.edgeInsets = Design.Spacing.onboardingInsets
        stack.translatesAutoresizingMaskIntoConstraints = false

        // 头部
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 44, weight: .light)
        let icon = NSImageView(image: NSImage(systemSymbolName: "rectangle.split.2x2", accessibilityDescription: nil)?
            .withSymbolConfiguration(iconConfig) ?? NSImage())
        icon.contentTintColor = .controlAccentColor

        let title = NSTextField(labelWithString: "WTidy")
        title.font = Design.Font.heroTitle
        let subtitle = NSTextField(labelWithString: L("原生重制的窗口分屏工具"))
        subtitle.font = Design.Font.body
        subtitle.textColor = .secondaryLabelColor
        let header = NSStackView(views: [icon, title, subtitle])
        header.orientation = .vertical
        header.alignment = .centerX
        header.spacing = Design.Spacing.headerGap

        // 步骤卡片
        let step1 = stepRow(number: "1",
                            title: L("辅助功能权限"),
                            detail: L("WTidy 靠它感知窗口拖拽、移动窗口。"),
                            trailing: buildTrustControls())
        let step2 = stepRow(number: "2",
                            title: L("开机自动启动"),
                            detail: LoginItemController.isAvailable
                                ? L("使用现代登录项机制，稳定随系统启动。")
                                : L("安装到 /Applications 后可启用。"),
                            trailing: buildLoginControls())
        // 两行同宽：徽标左对齐、trailing 控件右对齐
        NSLayoutConstraint.activate([
            step1.widthAnchor.constraint(equalToConstant: 468),
            step2.widthAnchor.constraint(equalToConstant: 468),
        ])

        let card = NSStackView(views: [step1, step2])
        card.orientation = .vertical
        card.alignment = .leading   // ①② 步骤条左对齐（默认 centerX 会因行宽不同而错位）
        card.spacing = Design.Spacing.cardGap
        card.edgeInsets = Design.Spacing.cardInsets
        card.wantsLayer = true
        card.layer?.cornerRadius = Design.Radius.onboardingCard
        card.layer?.backgroundColor = Design.Color.cardFill.cgColor

        // 完成按钮
        doneButton = NSButton(title: L("请先完成第 1 步授权"), target: self, action: #selector(doneClicked))
        doneButton.controlSize = .large
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"
        doneButton.isEnabled = false
        doneButton.widthAnchor.constraint(equalToConstant: 300).isActive = true

        let hint = NSTextField(labelWithString: L("拖拽任意窗口，屏幕顶部会出现布局条；悬停选择布局后松手即吸附。\n快捷键示例：⌥⌘← 左半屏，⌃⌥⌘F 最大化，⌃⌥⌘Z 恢复位置。"))
        hint.font = Design.Font.hint
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 3   // 英文文案按语义拆成 3 行（中文 2 行）

        stack.addArrangedSubview(header)
        stack.addArrangedSubview(card)
        stack.addArrangedSubview(doneButton)
        stack.addArrangedSubview(hint)

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            card.widthAnchor.constraint(equalToConstant: 500),
        ])
        return container
    }

    private func buildTrustControls() -> NSView {
        trustStatusLabel = NSTextField(labelWithString: "")
        trustStatusLabel.font = Design.Font.bodyEmphasis

        authorizeButton = NSButton(title: L("打开系统设置授权"), target: self, action: #selector(authorizeClicked))

        let box = NSStackView(views: [trustStatusLabel, authorizeButton])
        box.orientation = .vertical
        box.alignment = .trailing
        box.spacing = 6
        return box
    }

    private func buildLoginControls() -> NSView {
        loginCheckbox = NSButton(checkboxWithTitle: "", target: self, action: nil)
        loginCheckbox.state = .on
        loginCheckbox.isEnabled = LoginItemController.isAvailable
        return loginCheckbox
    }

    private func stepRow(number: String, title: String, detail: String, trailing: NSView) -> NSView {
        let badgeConfig = NSImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        let badge = NSImageView(image: NSImage(systemSymbolName: "\(number).circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(badgeConfig) ?? NSImage())
        badge.contentTintColor = .controlAccentColor

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = Design.Font.stepTitle
        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = Design.Font.hint
        detailLabel.textColor = .secondaryLabelColor
        let texts = NSStackView(views: [titleLabel, detailLabel])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 2

        let row = NSStackView(views: [badge, texts])
        row.orientation = .horizontal
        row.spacing = Design.Spacing.groupGap
        row.alignment = .firstBaseline

        let outer = NSStackView(views: [row, trailing])
        outer.orientation = .horizontal
        outer.distribution = .fill
        outer.spacing = 8
        outer.setHuggingPriority(.defaultLow, for: .horizontal)
        row.setContentHuggingPriority(.defaultLow, for: .horizontal)
        trailing.setContentHuggingPriority(.required, for: .horizontal)
        return outer
    }

    // MARK: - 状态与动作

    private func refreshTrustUI() {
        let trusted = AccessibilityService.isTrusted
        if trusted {
            trustStatusLabel.stringValue = L("✓ 已授权")
            trustStatusLabel.textColor = .systemGreen
            authorizeButton.isHidden = true
            doneButton.isEnabled = true
            doneButton.title = L("开始使用")
        } else {
            trustStatusLabel.stringValue = L("授权后此处自动打勾")
            trustStatusLabel.textColor = .secondaryLabelColor
            authorizeButton.isHidden = false
            doneButton.isEnabled = false
            doneButton.title = L("请先完成第 1 步授权")
        }
    }

    @objc private func authorizeClicked() {
        AccessibilityService.requestTrust()
    }

    @objc private func doneClicked() {
        pollTimer?.invalidate()
        Prefs.onboardingDone = true
        if loginCheckbox.state == .on {
            LoginItemController.setEnabled(true)
        }
        window?.close()
        onDone?()
    }
}
