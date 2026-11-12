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
        tabView.addTabViewItem(layoutsTab())
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

    /// 布局页：对齐原版 Layouts 标签——布局列表（增删改排序）+ 编辑器
    private var layoutsStack: NSStackView!

    private func layoutsTab() -> NSTabViewItem {
        let (content, stack) = makePage()
        stack.spacing = 6

        let caption = captionText("图标条按此列表顺序展示。点击「编辑」调整名称、网格与区域（对齐原版的网格区域模型）。")
        stack.addArrangedSubview(caption)
        stack.setCustomSpacing(10, after: caption)

        layoutsStack = NSStackView()
        layoutsStack.orientation = .vertical
        layoutsStack.alignment = .leading
        layoutsStack.spacing = 4
        stack.addArrangedSubview(layoutsStack)

        rebuildLayoutRows()

        // 底部：新增 / 恢复内置
        let addButton = NSButton(title: "新增布局", target: self, action: #selector(addLayoutClicked))
        let resetButton = NSButton(title: "恢复内置布局", target: self, action: #selector(resetLayoutsClicked))
        let bottom = NSStackView(views: [addButton, resetButton])
        bottom.orientation = .horizontal
        bottom.spacing = 8
        stack.setCustomSpacing(12, after: layoutsStack)
        stack.addArrangedSubview(bottom)

        let item = NSTabViewItem(identifier: "layouts")
        item.label = "布局"
        item.view = content
        return item
    }

    private func rebuildLayoutRows() {
        guard let stack = layoutsStack else { return }
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for (index, layout) in LayoutStore.layouts.enumerated() {
            let thumb = NSImageView(image: Self.thumbnail(for: layout))
            let name = NSTextField(labelWithString: layout.name)
            name.font = .systemFont(ofSize: 12)
            name.widthAnchor.constraint(greaterThanOrEqualToConstant: 96).isActive = true

            func smallButton(_ title: String, _ action: Selector, _ tag: Int) -> NSButton {
                let b = NSButton(title: title, target: self, action: action)
                b.tag = tag
                b.controlSize = .small
                return b
            }

            let up = smallButton("↑", #selector(moveLayoutUp(_:)), index)
            let down = smallButton("↓", #selector(moveLayoutDown(_:)), index)
            let edit = smallButton("编辑", #selector(editLayoutClicked(_:)), index)
            let remove = smallButton("删除", #selector(removeLayoutClicked(_:)), index)
            up.isEnabled = index > 0
            down.isEnabled = index < LayoutStore.layouts.count - 1

            let flexible = NSView()
            let row = NSStackView(views: [thumb, name, flexible, up, down, edit, remove])
            row.orientation = .horizontal
            row.spacing = 6
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalToConstant: 500).isActive = true
            stack.addArrangedSubview(row)
        }
    }

    /// 布局缩略图（归一化区域 → 位图，y 翻转：位图绘制原点在左下）
    static func thumbnail(for layout: TidyLayout, size: NSSize = NSSize(width: 84, height: 48)) -> NSImage {
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor.quaternaryLabelColor.withAlphaComponent(0.30).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 6, yRadius: 6).fill()
        let inner = NSRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4)
        for nr in layout.normalizedRects {
            let r = NSRect(x: inner.minX + nr.minX * inner.width,
                           y: inner.minY + (1 - nr.maxY) * inner.height,
                           width: nr.width * inner.width,
                           height: nr.height * inner.height)
            NSColor.controlAccentColor.withAlphaComponent(0.85).setFill()
            NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3).fill()
        }
        img.unlockFocus()
        return img
    }

    // MARK: - 布局列表动作

    @objc private func moveLayoutUp(_ sender: NSButton) {
        var list = LayoutStore.layouts
        let i = sender.tag
        guard i > 0 else { return }
        list.swapAt(i, i - 1)
        LayoutStore.layouts = list
        rebuildLayoutRows()
    }

    @objc private func moveLayoutDown(_ sender: NSButton) {
        var list = LayoutStore.layouts
        let i = sender.tag
        guard i < list.count - 1 else { return }
        list.swapAt(i, i + 1)
        LayoutStore.layouts = list
        rebuildLayoutRows()
    }

    @objc private func removeLayoutClicked(_ sender: NSButton) {
        var list = LayoutStore.layouts
        guard list.indices.contains(sender.tag) else { return }
        list.remove(at: sender.tag)
        LayoutStore.layouts = list
        rebuildLayoutRows()
    }

    @objc private func addLayoutClicked() {
        let newLayout = TidyLayout(id: "custom-" + UUID().uuidString.prefix(8),
                                   name: "新布局",
                                   cols: 6, rows: 6,
                                   regions: [.init(2, 2, 5, 5)])
        LayoutEditorWindowController.present(layout: newLayout, isNew: true) { [weak self] edited in
            var list = LayoutStore.layouts
            list.append(edited)
            LayoutStore.layouts = list
            self?.rebuildLayoutRows()
        }
    }

    @objc private func resetLayoutsClicked() {
        LayoutStore.reset()
        rebuildLayoutRows()
    }

    @objc private func editLayoutClicked(_ sender: NSButton) {
        let index = sender.tag
        guard LayoutStore.layouts.indices.contains(index) else { return }
        let layout = LayoutStore.layouts[index]
        LayoutEditorWindowController.present(layout: layout, isNew: false) { [weak self] edited in
            var list = LayoutStore.layouts
            list[index] = edited
            LayoutStore.layouts = list
            self?.rebuildLayoutRows()
        }
    }

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

// MARK: - 布局编辑器
//
// 对齐原版 Layouts 的编辑模型：名称 + 网格（cols×rows）+ 若干区域
// （1-based 单元坐标 (x1,y1)-(x2,y2)，y1 为顶行），实时预览缩略图。

final class LayoutEditorWindowController: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    private let window: NSWindow
    private let nameField: NSTextField
    private let colsField: NSTextField
    private let rowsField: NSTextField
    private let regionsStack: NSStackView
    private let previewView: NSImageView
    private var regionFields: [(x1: NSTextField, y1: NSTextField, x2: NSTextField, y2: NSTextField)] = []
    private var working: TidyLayout
    private let isNew: Bool
    private let onCommit: (TidyLayout) -> Void

    static func present(layout: TidyLayout, isNew: Bool, onCommit: @escaping (TidyLayout) -> Void) {
        let editor = LayoutEditorWindowController(layout: layout, isNew: isNew, onCommit: onCommit)
        editor.window.center()
        editor.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init(layout: TidyLayout, isNew: Bool, onCommit: @escaping (TidyLayout) -> Void) {
        // 所有 let 存储属性必须在 super.init() 之前初始化
        self.working = layout
        self.isNew = isNew
        self.onCommit = onCommit

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 470, height: 480),
                          styleMask: [.titled, .closable],
                          backing: .buffered, defer: false)
        nameField = NSTextField(string: layout.name)
        colsField = NSTextField(string: String(layout.cols))
        rowsField = NSTextField(string: String(layout.rows))
        regionsStack = NSStackView()
        regionsStack.orientation = .vertical
        regionsStack.alignment = .leading
        regionsStack.spacing = 4
        previewView = NSImageView(image: SettingsWindowController.thumbnail(for: layout, size: NSSize(width: 180, height: 100)))

        super.init()

        window.title = isNew ? "新增布局" : "编辑布局：\(layout.name)"
        window.isReleasedWhenClosed = true
        window.delegate = self

        buildUI()
        rebuildRegionRows()
    }

    private func buildUI() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        func label(_ t: String) -> NSTextField {
            let f = NSTextField(labelWithString: t)
            f.font = .systemFont(ofSize: 12)
            return f
        }
        func smallField(_ s: String, width: CGFloat = 44) -> NSTextField {
            let f = NSTextField(string: s)
            f.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            f.alignment = .center
            f.widthAnchor.constraint(equalToConstant: width).isActive = true
            f.delegate = self
            return f
        }

        nameField.delegate = self
        nameField.widthAnchor.constraint(equalToConstant: 180).isActive = true
        colsField.delegate = self
        rowsField.delegate = self
        colsField.widthAnchor.constraint(equalToConstant: 44).isActive = true
        rowsField.widthAnchor.constraint(equalToConstant: 44).isActive = true

        stack.addArrangedSubview(label("名称"))
        stack.addArrangedSubview(nameField)
        let gridRow = NSStackView(views: [label("网格"), colsField, label("×"), rowsField, label("（列 × 行）")])
        gridRow.orientation = .horizontal
        gridRow.spacing = 6
        stack.addArrangedSubview(gridRow)
        stack.setCustomSpacing(14, after: gridRow)

        stack.addArrangedSubview(label("区域（单元坐标，1 起；y1 为顶行；格式 x1 y1 x2 y2）"))
        stack.addArrangedSubview(regionsStack)

        let addRegion = NSButton(title: "+ 添加区域", target: self, action: #selector(addRegionClicked))
        let removeRegion = NSButton(title: "− 移除最后区域", target: self, action: #selector(removeRegionClicked))
        removeRegion.controlSize = .small
        addRegion.controlSize = .small
        let regionButtons = NSStackView(views: [addRegion, removeRegion])
        regionButtons.orientation = .horizontal
        regionButtons.spacing = 8
        stack.addArrangedSubview(regionButtons)
        stack.setCustomSpacing(14, after: regionButtons)

        let previewRow = NSStackView(views: [label("预览"), previewView])
        previewRow.orientation = .horizontal
        previewRow.spacing = 12
        stack.addArrangedSubview(previewRow)
        stack.setCustomSpacing(16, after: previewRow)

        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelClicked))
        let commit = NSButton(title: "完成", target: self, action: #selector(commitClicked))
        commit.keyEquivalent = "\r"
        commit.bezelStyle = .rounded
        let flexible = NSView()
        let buttons = NSStackView(views: [cancel, flexible, commit])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.translatesAutoresizingMaskIntoConstraints = false
        buttons.widthAnchor.constraint(equalToConstant: 430).isActive = true
        flexible.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(buttons)

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor),
        ])
        window.contentView = content
    }

    private func rebuildRegionRows() {
        regionsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        regionFields.removeAll()

        for (i, region) in working.regions.enumerated() {
            let fields = (0..<4).map { _ -> NSTextField in
                let f = NSTextField(string: "0")
                f.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
                f.alignment = .center
                f.widthAnchor.constraint(equalToConstant: 40).isActive = true
                f.delegate = self
                return f
            }
            fields[0].stringValue = String(region.x1)
            fields[1].stringValue = String(region.y1)
            fields[2].stringValue = String(region.x2)
            fields[3].stringValue = String(region.y2)

            let indexLabel = NSTextField(labelWithString: "\(i + 1).")
            indexLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            let row = NSStackView(views: [indexLabel, fields[0], fields[1], fields[2], fields[3]])
            row.orientation = .horizontal
            row.spacing = 4
            regionsStack.addArrangedSubview(row)
            regionFields.append((fields[0], fields[1], fields[2], fields[3]))
        }
    }

    // MARK: - 状态采集

    /// 从输入框读取当前工作副本（非法输入回退为原值，实时预览用）
    private func syncWorkingFromFields() {
        working.name = nameField.stringValue.isEmpty ? "未命名" : nameField.stringValue
        working.cols = max(1, min(12, Int(colsField.stringValue) ?? working.cols))
        working.rows = max(1, min(12, Int(rowsField.stringValue) ?? working.rows))
        working.regions = regionFields.enumerated().map { i, f in
            let old = working.regions.indices.contains(i) ? working.regions[i] : TidyLayout.Region(1, 1, working.cols, working.rows)
            func v(_ field: NSTextField, _ fallback: Int) -> Int { Int(field.stringValue) ?? fallback }
            var x1 = max(1, v(f.x1, old.x1)), y1 = max(1, v(f.y1, old.y1))
            var x2 = max(1, v(f.x2, old.x2)), y2 = max(1, v(f.y2, old.y2))
            x1 = min(x1, working.cols); x2 = min(x2, working.cols)
            y1 = min(y1, working.rows); y2 = min(y2, working.rows)
            if x1 > x2 { swap(&x1, &x2) }
            if y1 > y2 { swap(&y1, &y2) }
            return TidyLayout.Region(x1, y1, x2, y2)
        }
    }

    private func updatePreview() {
        syncWorkingFromFields()
        previewView.image = SettingsWindowController.thumbnail(for: working, size: NSSize(width: 180, height: 100))
    }

    // MARK: - 动作

    @objc private func addRegionClicked() {
        syncWorkingFromFields()
        working.regions.append(TidyLayout.Region(1, 1, working.cols, working.rows))
        rebuildRegionRows()
        updatePreview()
    }

    @objc private func removeRegionClicked() {
        guard working.regions.count > 1 else { return }
        syncWorkingFromFields()
        working.regions.removeLast()
        rebuildRegionRows()
        updatePreview()
    }

    @objc private func commitClicked() {
        updatePreview()
        onCommit(working)
        window.close()
    }

    @objc private func cancelClicked() {
        window.close()
    }

    func controlTextDidChange(_ obj: Notification) {
        updatePreview()
    }
}
