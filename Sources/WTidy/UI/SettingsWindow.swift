import AppKit
import Carbon.HIToolbox

/// 设置窗口。
/// 故意不用 Auto Layout 撑尺寸：NSTabView 直接 autoresizing 贴满窗口内容区，
/// 各 tab 页内部只用「单边/居中」约束（和引导窗口同款、已验证可靠的模式）。
/// —— 此前两版（手动约束 NSTabView、NSTabViewController）都因根视图缺少尺寸
///    约束而内容塌陷错位，教训：tab 容器一律用 frame + autoresizingMask。
final class SettingsWindowController: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    static let shared = SettingsWindowController()

    private let window: NSWindow
    private let tabView = NSTabView()

    // 通用页控件
    private let dragCheck = NSButton(checkboxWithTitle: L("启用拖拽分屏"), target: nil, action: nil)
    private let hotkeyCheck = NSButton(checkboxWithTitle: L("启用全局快捷键"), target: nil, action: nil)
    private let loginCheck = NSButton(checkboxWithTitle: L("开机自动启动"), target: nil, action: nil)
    private let gapSegment = NSSegmentedControl(labels: [L("贴合"), "4pt", "8pt", "12pt"],
                                                trackingMode: .selectOne, target: nil, action: nil)
    private let permissionRow = NSStackView()
    private var hotkeyToggles: [NSButton] = []

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 760),
                          styleMask: [.titled, .closable],
                          backing: .buffered, defer: false)
        super.init()

        // 对齐原版窗口 chrome：标题 + 顶部 tab + 底部栏（自启勾选 + 完成按钮）
        window.title = L("WTidy 偏好设置")
        window.isReleasedWhenClosed = false
        window.delegate = self

        let content = window.contentView!

        tabView.font = .systemFont(ofSize: 13)
        tabView.addTabViewItem(layoutsTab())
        tabView.addTabViewItem(optionsTab())
        tabView.addTabViewItem(positioningTab())
        tabView.addTabViewItem(quickLayoutTab())
        tabView.addTabViewItem(hotkeysTab())
        tabView.addTabViewItem(aboutTab())

        // 底部栏。窗口固定尺寸不可缩放，全部用静态 frame（零 Auto Layout，
        // 规避 NSTabView 固有尺寸与窗口高度约束的冲突）
        let width = content.bounds.width     // 580
        let height = content.bounds.height   // 680
        let barHeight: CGFloat = 46

        let separator = NSBox()
        separator.boxType = .separator
        separator.frame = NSRect(x: 0, y: barHeight, width: width, height: 5)
        separator.autoresizingMask = [.width]
        content.addSubview(separator)

        let bar = NSView()
        bar.frame = NSRect(x: 0, y: 0, width: width, height: barHeight)
        bar.autoresizingMask = [.width]
        content.addSubview(bar)

        loginCheck.frame = NSRect(x: 16, y: (barHeight - 24) / 2, width: 220, height: 24)
        bar.addSubview(loginCheck)
        let doneButton = NSButton(title: L("完成"), target: self, action: #selector(doneClicked))
        doneButton.keyEquivalent = "\r"
        doneButton.bezelStyle = .rounded
        doneButton.frame = NSRect(x: width - 16 - 76, y: (barHeight - 28) / 2, width: 76, height: 28)
        bar.addSubview(doneButton)

        tabView.frame = NSRect(x: 12, y: barHeight + 8, width: width - 24, height: height - barHeight - 16)
        tabView.autoresizingMask = [.width]
        content.addSubview(tabView)

        wireActions()
        refreshState()
    }

    @objc private func doneClicked() {
        // 输入框的 action 只在按回车时触发——点「完成」前强制提交所有字段
        Prefs.stripMaxWidth = Double(maxWidthField.stringValue) ?? Prefs.stripMaxWidth
        Prefs.stripMargin = Double(marginField.stringValue) ?? Prefs.stripMargin
        Prefs.qlWidth = Double(qlWidthField.stringValue) ?? Prefs.qlWidth
        Prefs.qlHeight = Double(qlHeightField.stringValue) ?? Prefs.qlHeight
        refreshState()
        window.orderOut(nil)
    }

    func present() {
        refreshState()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Tab 页构建

    /// 布局页：对齐原版 Layouts——列表（拖拽排序 / 双击编辑）+ 左下角 +/−
    private let layoutTable = NSTableView()
    private let layoutScrollView = NSScrollView()
    private static let layoutDragType = NSPasteboard.PasteboardType("com.allblue.wtidy.layoutrow")

    private func layoutsTab() -> NSTabViewItem {
        let (content, stack) = makePage()
        stack.spacing = 8

        let caption = captionText(L("拖动可更改布局顺序，双击某行编辑其设置。图标条按此列表顺序展示。"))
        stack.addArrangedSubview(caption)
        stack.setCustomSpacing(10, after: caption)

        // 列表
        layoutTable.headerView = nil
        layoutTable.rowHeight = 96
        layoutTable.dataSource = self
        layoutTable.delegate = self
        layoutTable.target = self
        layoutTable.doubleAction = #selector(layoutRowDoubleClicked)
        layoutTable.allowsColumnReordering = false
        layoutTable.intercellSpacing = NSSize(width: 0, height: 8)
        layoutTable.style = .plain
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("layout"))
        column.width = 640
        layoutTable.addTableColumn(column)

        layoutScrollView.documentView = layoutTable
        layoutScrollView.hasVerticalScroller = true
        layoutScrollView.autohidesScrollers = true
        layoutScrollView.drawsBackground = false
        layoutScrollView.translatesAutoresizingMaskIntoConstraints = false
        layoutScrollView.heightAnchor.constraint(equalToConstant: 420).isActive = true
        layoutScrollView.widthAnchor.constraint(equalToConstant: 660).isActive = true
        stack.addArrangedSubview(layoutScrollView)
        stack.setCustomSpacing(12, after: layoutScrollView)

        // 左下角 +/−（对齐原版），右侧保留「恢复内置」
        let addButton = NSButton(title: L("＋"), target: self, action: #selector(addLayoutClicked))
        addButton.bezelStyle = .rounded
        addButton.widthAnchor.constraint(equalToConstant: 40).isActive = true
        let removeButton = NSButton(title: L("－"), target: self, action: #selector(removeSelectedLayout))
        removeButton.bezelStyle = .rounded
        removeButton.widthAnchor.constraint(equalToConstant: 40).isActive = true
        let resetButton = NSButton(title: L("恢复内置布局"), target: self, action: #selector(resetLayoutsClicked))
        resetButton.bezelStyle = .rounded
        let plusMinus = NSStackView(views: [addButton, removeButton])
        plusMinus.orientation = .horizontal
        plusMinus.spacing = 6
        let flexible = NSView()
        let bottom = NSStackView(views: [plusMinus, flexible, resetButton])
        bottom.orientation = .horizontal
        bottom.spacing = 8
        bottom.translatesAutoresizingMaskIntoConstraints = false
        bottom.widthAnchor.constraint(equalToConstant: 660).isActive = true
        flexible.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(bottom)

        let item = NSTabViewItem(identifier: "layouts")
        item.label = L("布局")
        item.view = content
        return item
    }

    /// 布局缩略图：走共用渲染器（浅色壁纸网格风，对齐原版 Layouts 列表）
    static func thumbnail(for layout: TidyLayout, size: NSSize = NSSize(width: 104, height: 60)) -> NSImage {
        let img = NSImage(size: size)
        img.lockFocus()
        LayoutIconRenderer.draw(layout: layout,
                                in: NSRect(origin: .zero, size: size),
                                flipped: false,   // NSImage 上下文原点左下
                                style: .light)
        img.unlockFocus()
        return img
    }

    // MARK: - 布局列表动作

    private func reloadLayouts() {
        layoutTable.reloadData()
    }

    @objc private func addLayoutClicked() {
        let newLayout = TidyLayout(id: "custom-" + UUID().uuidString.prefix(8),
                                   name: L("新布局"),
                                   cols: 6, rows: 6,
                                   regions: [.init(2, 2, 5, 5)])
        LayoutEditorWindowController.present(layout: newLayout, isNew: true) { [weak self] edited in
            var list = LayoutStore.layouts
            list.append(edited)
            LayoutStore.layouts = list
            self?.reloadLayouts()
        }
    }

    @objc private func removeSelectedLayout() {
        let row = layoutTable.selectedRow
        guard row >= 0, LayoutStore.layouts.indices.contains(row) else { return }
        var list = LayoutStore.layouts
        list.remove(at: row)
        LayoutStore.layouts = list
        reloadLayouts()
    }

    @objc private func resetLayoutsClicked() {
        LayoutStore.reset()
        reloadLayouts()
    }

    @objc private func layoutRowDoubleClicked() {
        let row = layoutTable.clickedRow >= 0 ? layoutTable.clickedRow : layoutTable.selectedRow
        guard row >= 0, LayoutStore.layouts.indices.contains(row) else { return }
        let layout = LayoutStore.layouts[row]
        LayoutEditorWindowController.present(layout: layout, isNew: false) { [weak self] edited in
            var list = LayoutStore.layouts
            list[row] = edited
            LayoutStore.layouts = list
            self?.reloadLayouts()
        }
    }

    /// 页面容器 + 垂直布局栈（栈用单边约束，容器尺寸由窗口/tab 决定）
    private func makePage() -> (NSView, NSStackView) {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 690, height: 680))
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

    // MARK: - 行为页（原版 Options：标题在外、控件在圆角分组框内）

    private let optionHideRadio = NSButton(radioButtonWithTitle: L("按住 ⌥ 隐藏布局图标"), target: nil, action: nil)
    private let optionShowRadio = NSButton(radioButtonWithTitle: L("按住 ⌥ 显示布局图标"), target: nil, action: nil)
    private let statusIconCheck = NSButton(checkboxWithTitle: L("显示菜单栏状态图标"), target: nil, action: nil)
    private let namesCheck = NSButton(checkboxWithTitle: L("在布局图标上显示名称"), target: nil, action: nil)
    private let warnCheck = NSButton(checkboxWithTitle: L("窗口未能调整尺寸时显示警告"), target: nil, action: nil)
    private let animateCheck = NSButton(checkboxWithTitle: L("吸附窗口动画（跨屏分阶段移动）"), target: nil, action: nil)
    private let groupCheck = NSButton(checkboxWithTitle: L("自动分组相邻互补布局"), target: nil, action: nil)
    private let themeInkRadio = NSButton(radioButtonWithTitle: L("墨蓝"), target: nil, action: nil)
    private let themeGraphiteRadio = NSButton(radioButtonWithTitle: L("石墨"), target: nil, action: nil)
    private let themeTealRadio = NSButton(radioButtonWithTitle: L("青碧"), target: nil, action: nil)
    private let themeVioletRadio = NSButton(radioButtonWithTitle: L("紫罗兰"), target: nil, action: nil)
    private let bgWell = NSImageView(frame: NSRect(x: 0, y: 0, width: 220, height: 124))
    private let bgDefaultButton = NSButton(title: L("默认深色"), target: nil, action: nil)
    private let bgWallpaperButton = NSButton(title: L("使用桌面壁纸"), target: nil, action: nil)

    /// 原版式分组框：小节标题在外，控件装进圆角框
    private func groupBox(_ controls: [NSView], width: CGFloat = 660) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        for c in controls { stack.addArrangedSubview(c) }
        let box = NSBox()
        box.boxType = .primary
        box.title = ""
        box.contentView = stack
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: width).isActive = true
        return box
    }

    private func optionsTab() -> NSTabViewItem {
        let (content, stack) = makePage()
        stack.spacing = 8

        stack.addArrangedSubview(sectionTitle(L("行为")))
        let behaviorIntro = captionText(L("⌥ 选项按钮用于控制布局图标的显示。"))
        optionHideRadio.target = self
        optionHideRadio.action = #selector(optionKeyModeChanged)
        optionShowRadio.target = self
        optionShowRadio.action = #selector(optionKeyModeChanged)
        stack.addArrangedSubview(groupBox([behaviorIntro, optionHideRadio, optionShowRadio,
                                           statusIconCheck, groupCheck, namesCheck, warnCheck]))

        stack.addArrangedSubview(sectionTitle(L("窗口调整")))
        stack.addArrangedSubview(groupBox([animateCheck, groupCheck, dragCheck, hotkeyCheck]))

        stack.addArrangedSubview(sectionTitle(L("图标条配色")))
        stack.addArrangedSubview(groupBox([themeInkRadio, themeGraphiteRadio, themeTealRadio, themeVioletRadio]))

        stack.addArrangedSubview(sectionTitle(L("背景")))
        let bgIntro = captionText(L("布局图标条背景可使用默认深色或桌面壁纸。"))
        bgDefaultButton.target = self
        bgDefaultButton.action = #selector(bgDefaultClicked)
        bgWallpaperButton.target = self
        bgWallpaperButton.action = #selector(bgWallpaperClicked)
        let bgButtons = NSStackView(views: [bgDefaultButton, bgWallpaperButton])
        bgButtons.orientation = .horizontal
        bgButtons.spacing = 10
        let bgInner = NSStackView()
        bgInner.orientation = .vertical
        bgInner.alignment = .leading
        bgInner.spacing = 10
        bgInner.addArrangedSubview(bgIntro)
        bgWell.wantsLayer = true
        bgWell.layer?.borderColor = NSColor.separatorColor.cgColor
        bgWell.layer?.borderWidth = 1
        bgWell.layer?.cornerRadius = 4
        let wellRow = NSStackView(views: [bgWell, bgButtons])
        wellRow.orientation = .horizontal
        wellRow.spacing = 16
        bgInner.addArrangedSubview(wellRow)
        stack.addArrangedSubview(groupBox([bgInner]))

        let warnIcon = NSImageView(image: NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                                                 accessibilityDescription: nil) ?? NSImage())
        warnIcon.contentTintColor = .systemYellow
        let warnText = NSTextField(labelWithString: L("缺少辅助功能权限，功能未生效"))
        warnText.font = .systemFont(ofSize: 12)
        let grantButton = NSButton(title: L("去授权"), target: self, action: #selector(grantClicked))
        permissionRow.orientation = .horizontal
        permissionRow.spacing = 8
        permissionRow.addArrangedSubview(warnIcon)
        permissionRow.addArrangedSubview(warnText)
        permissionRow.addArrangedSubview(grantButton)
        stack.addArrangedSubview(permissionRow)

        let item = NSTabViewItem(identifier: "options")
        item.label = L("行为")
        item.view = content
        return item
    }

    /// 背景图井预览：默认渐变或桌面壁纸
    private func refreshBackgroundWell() {
        let img = NSImage(size: NSSize(width: 220, height: 124))
        img.lockFocus()
        if Prefs.stripBackground == 1,
           let screen = NSScreen.main,
           let url = NSWorkspace.shared.desktopImageURL(for: screen),
           let wallpaper = NSImage(contentsOf: url) {
            wallpaper.draw(in: NSRect(origin: .zero, size: img.size),
                           from: NSRect(x: 0, y: 0, width: wallpaper.size.width, height: wallpaper.size.height / 2),
                           operation: .copy, fraction: 1)
        } else {
            let grad = NSGradient(colors: [NSColor(red: 0.62, green: 0.78, blue: 0.94, alpha: 1),
                                           NSColor(red: 0.22, green: 0.38, blue: 0.68, alpha: 1)])
            grad?.draw(in: NSRect(origin: .zero, size: img.size), angle: 270)
        }
        img.unlockFocus()
        bgWell.image = img
    }

    // MARK: - 定位页（原版 Positioning）

    private let orientHoriRadio = NSButton(radioButtonWithTitle: L("横向排列图标"), target: nil, action: nil)
    private let orientVertRadio = NSButton(radioButtonWithTitle: L("纵向排列图标"), target: nil, action: nil)
    private let posPreview = ScreenPositionPreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 340))
    private let posHSlider = NSSlider(value: 0.5, minValue: 0, maxValue: 1,
                                      target: nil, action: #selector(posHChanged))
    private let posVSlider = NSSlider(value: 0, minValue: 0, maxValue: 1,
                                      target: nil, action: #selector(posVChanged))
    private let maxWidthField = NSTextField(string: "512")
    private let marginField = NSTextField(string: "0")

    private func positioningTab() -> NSTabViewItem {
        let (content, stack) = makePage()

        func label(_ t: String) -> NSTextField {
            let f = NSTextField(labelWithString: t)
            f.font = .systemFont(ofSize: 12)
            return f
        }

        stack.addArrangedSubview(sectionTitle(L("排列方向")))
        orientHoriRadio.target = self
        orientHoriRadio.action = #selector(orientationChanged)
        orientVertRadio.target = self
        orientVertRadio.action = #selector(orientationChanged)
        let orientRow = NSStackView(views: [orientHoriRadio, orientVertRadio])
        orientRow.orientation = .horizontal
        orientRow.spacing = 16
        stack.addArrangedSubview(orientRow)

        stack.addArrangedSubview(sectionTitle(L("屏幕位置")))
        // 对齐原版：滑块与排列方式联动——横向排列只显示纵向滑块（调上下），
        // 纵向排列只显示横向滑块（调左右）；显隐在 refreshState 里切换
        posHSlider.target = self
        posHSlider.action = #selector(posHChanged)
        posHSlider.isContinuous = true
        posHSlider.widthAnchor.constraint(equalToConstant: 600).isActive = true
        posHSlider.heightAnchor.constraint(equalToConstant: 28).isActive = true
        posVSlider.target = self
        posVSlider.action = #selector(posVChanged)
        posVSlider.isContinuous = true
        posVSlider.isVertical = true
        posVSlider.widthAnchor.constraint(equalToConstant: 24).isActive = true
        posVSlider.heightAnchor.constraint(equalToConstant: 340).isActive = true

        posPreview.translatesAutoresizingMaskIntoConstraints = false
        posPreview.widthAnchor.constraint(equalToConstant: 600).isActive = true
        posPreview.heightAnchor.constraint(equalToConstant: 340).isActive = true

        let previewColumn = NSStackView(views: [posPreview, posHSlider])
        previewColumn.orientation = .vertical
        previewColumn.spacing = 8
        previewColumn.alignment = .leading
        let posRow = NSStackView(views: [previewColumn, posVSlider])
        posRow.orientation = .horizontal
        posRow.spacing = 10
        stack.addArrangedSubview(posRow)

        stack.addArrangedSubview(sectionTitle(L("尺寸")))
        maxWidthField.target = self
        maxWidthField.action = #selector(maxWidthCommitted)
        marginField.target = self
        marginField.action = #selector(marginCommitted)
        maxWidthField.widthAnchor.constraint(equalToConstant: 70).isActive = true
        marginField.widthAnchor.constraint(equalToConstant: 70).isActive = true
        let dimsRow = NSStackView(views: [label(L("最大宽度")), maxWidthField, label(L("边距")), marginField])
        dimsRow.orientation = .horizontal
        dimsRow.spacing = 8
        stack.addArrangedSubview(dimsRow)
        stack.addArrangedSubview(captionText(L("数值为整条图标条的总宽度；单图标宽 = 可用宽度 ÷ 布局数（基准 150pt，下限 90pt）。")))

        stack.addArrangedSubview(sectionTitle(L("窗口间隙")))
        gapSegment.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(gapSegment)
        stack.addArrangedSubview(captionText(L("贴合为原版 Window Tidy 的行为；间距可让相邻窗口留出呼吸感。")))

        let item = NSTabViewItem(identifier: "positioning")
        item.label = L("定位")
        item.view = content
        return item
    }

    // MARK: - 快速布局页（原版 Quick Layout）

    private let qlRecorder = HotkeyRecorderButton(title: "")
    private let qlNearCursorCheck = NSButton(checkboxWithTitle: L("显示在鼠标光标附近"), target: nil, action: nil)
    private let qlPosHSlider = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let qlPosVSlider = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let qlPreview = ScreenPositionPreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
    private let qlWidthField = NSTextField(string: "512")
    private let qlHeightField = NSTextField(string: "288")

    private func quickLayoutTab() -> NSTabViewItem {
        let (content, stack) = makePage()

        func label(_ t: String) -> NSTextField {
            let f = NSTextField(labelWithString: t)
            f.font = .systemFont(ofSize: 12)
            return f
        }

        stack.addArrangedSubview(sectionTitle(L("激活")))
        stack.addArrangedSubview(captionText(L("全局快捷键呼出快速布局面板：点选图标即把前台窗口吸到对应区域（含图标内投影选区）。Esc 或点击面板外关闭。")))
        qlRecorder.onRecord = { [weak self] keyCode, modifiers in
            Prefs.qlKeyCode = keyCode
            Prefs.qlModifiers = modifiers
            self?.refreshState()
        }
        qlRecorder.widthAnchor.constraint(equalToConstant: 260).isActive = true
        stack.addArrangedSubview(qlRecorder)

        stack.addArrangedSubview(sectionTitle(L("面板位置")))
        qlNearCursorCheck.target = self
        qlNearCursorCheck.action = #selector(qlNearCursorChanged)
        stack.addArrangedSubview(qlNearCursorCheck)
        // 原版式：横滑杆在下、纵滑杆在右 + 单图标预览
        qlPosHSlider.target = self
        qlPosHSlider.action = #selector(qlPosHChanged)
        qlPosHSlider.isContinuous = true
        qlPosHSlider.widthAnchor.constraint(equalToConstant: 600).isActive = true
        qlPosVSlider.target = self
        qlPosVSlider.action = #selector(qlPosVChanged)
        qlPosVSlider.isContinuous = true
        qlPosVSlider.isVertical = true
        qlPosVSlider.widthAnchor.constraint(equalToConstant: 24).isActive = true
        qlPosVSlider.heightAnchor.constraint(equalToConstant: 300).isActive = true

        qlPreview.translatesAutoresizingMaskIntoConstraints = false
        qlPreview.widthAnchor.constraint(equalToConstant: 600).isActive = true
        qlPreview.heightAnchor.constraint(equalToConstant: 300).isActive = true
        let qlColumn = NSStackView(views: [qlPreview, qlPosHSlider])
        qlColumn.orientation = .vertical
        qlColumn.spacing = 8
        qlColumn.alignment = .leading
        let qlPosRow = NSStackView(views: [qlColumn, qlPosVSlider])
        qlPosRow.orientation = .horizontal
        qlPosRow.spacing = 10
        stack.addArrangedSubview(qlPosRow)

        stack.addArrangedSubview(sectionTitle(L("面板尺寸")))
        qlWidthField.target = self
        qlWidthField.action = #selector(qlWidthCommitted)
        qlHeightField.target = self
        qlHeightField.action = #selector(qlHeightCommitted)
        qlWidthField.widthAnchor.constraint(equalToConstant: 70).isActive = true
        qlHeightField.widthAnchor.constraint(equalToConstant: 70).isActive = true
        let dimsRow = NSStackView(views: [label(L("宽度")), qlWidthField, label(L("高度")), qlHeightField])
        dimsRow.orientation = .horizontal
        dimsRow.spacing = 8
        stack.addArrangedSubview(dimsRow)

        let item = NSTabViewItem(identifier: "quicklayout")
        item.label = L("快速布局")
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
        stack.addArrangedSubview(captionText(L("快捷键与拖拽分屏互为补充；某些应用不支持拖拽感知时，快捷键仍可分屏。")))

        let item = NSTabViewItem(identifier: "hotkeys")
        item.label = L("快捷键")
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
        let openLog = NSButton(title: L("打开日志"), target: self, action: #selector(openLogClicked))

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
        item.label = L("关于")
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
        statusIconCheck.target = self
        statusIconCheck.action = #selector(statusIconChanged)
        namesCheck.target = self
        namesCheck.action = #selector(namesChanged)
        warnCheck.target = self
        warnCheck.action = #selector(warnChanged)
        animateCheck.target = self
        animateCheck.action = #selector(animateChanged)
        groupCheck.target = self
        groupCheck.action = #selector(groupChanged)
        for radio in [themeInkRadio, themeGraphiteRadio, themeTealRadio, themeVioletRadio] {
            radio.target = self
            radio.action = #selector(stripThemeChanged)
        }
        qlNearCursorCheck.target = self
        qlNearCursorCheck.action = #selector(qlNearCursorChanged)
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

        // 行为页
        optionHideRadio.state = Prefs.optionKeyMode == 0 ? .on : .off
        optionShowRadio.state = Prefs.optionKeyMode == 1 ? .on : .off
        if Prefs.optionKeyMode == 2 { optionHideRadio.state = .on }  // 两选一：不支持⌥时归入默认隐藏
        statusIconCheck.state = Prefs.showStatusIcon ? .on : .off
        namesCheck.state = Prefs.showLayoutNames ? .on : .off
        warnCheck.state = Prefs.warnOnFail ? .on : .off
        animateCheck.state = Prefs.animateWindows ? .on : .off
        groupCheck.state = Prefs.autoGroupLayouts ? .on : .off
        themeInkRadio.state = Prefs.stripTheme == 0 ? .on : .off
        themeGraphiteRadio.state = Prefs.stripTheme == 1 ? .on : .off
        themeTealRadio.state = Prefs.stripTheme == 2 ? .on : .off
        themeVioletRadio.state = Prefs.stripTheme == 3 ? .on : .off
        refreshBackgroundWell()

        // 定位页
        orientHoriRadio.state = Prefs.stripVertical ? .off : .on
        orientVertRadio.state = Prefs.stripVertical ? .on : .off
        // 滑块与排列方式联动：横排只留纵向滑块（调上下），纵排只留横向滑块（调左右）
        posHSlider.isHidden = !Prefs.stripVertical
        posVSlider.isHidden = Prefs.stripVertical
        posHSlider.doubleValue = Prefs.stripPosX
        posVSlider.doubleValue = 1 - Prefs.stripPosY   // 因子 0=顶 ↔ 滑块 1=上，取反
        maxWidthField.stringValue = String(Int(Prefs.stripMaxWidth))
        marginField.stringValue = String(Int(Prefs.stripMargin))
        posPreview.needsDisplay = true

        // 快速布局页
        qlRecorder.title = Self.hotkeyDisplay(keyCode: Prefs.qlKeyCode, modifiers: Prefs.qlModifiers)
        qlNearCursorCheck.state = Prefs.qlNearCursor ? .on : .off
        qlPosHSlider.doubleValue = Prefs.qlPosX
        qlPosVSlider.doubleValue = 1 - Prefs.qlPosY
        qlPosHSlider.isEnabled = !Prefs.qlNearCursor
        qlPosVSlider.isEnabled = !Prefs.qlNearCursor
        qlWidthField.stringValue = String(Int(Prefs.qlWidth))
        qlHeightField.stringValue = String(Int(Prefs.qlHeight))
        qlPreview.needsDisplay = true
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

    // MARK: - 行为页动作

    @objc private func optionKeyModeChanged() {
        if optionHideRadio.state == .on { Prefs.optionKeyMode = 0 }
        else if optionShowRadio.state == .on { Prefs.optionKeyMode = 1 }
    }

    @objc private func statusIconChanged() { Prefs.showStatusIcon = statusIconCheck.state == .on }
    @objc private func namesChanged() { Prefs.showLayoutNames = namesCheck.state == .on }
    @objc private func warnChanged() { Prefs.warnOnFail = warnCheck.state == .on }
    @objc private func animateChanged() { Prefs.animateWindows = animateCheck.state == .on }
    @objc private func groupChanged() { Prefs.autoGroupLayouts = groupCheck.state == .on }
    @objc private func stripThemeChanged() {
        if themeInkRadio.state == .on { Prefs.stripTheme = 0 }
        else if themeGraphiteRadio.state == .on { Prefs.stripTheme = 1 }
        else if themeTealRadio.state == .on { Prefs.stripTheme = 2 }
        else if themeVioletRadio.state == .on { Prefs.stripTheme = 3 }
        refreshBackgroundWell()
    }
    @objc private func bgDefaultClicked() { Prefs.stripBackground = 0 }
    @objc private func bgWallpaperClicked() { Prefs.stripBackground = 1 }

    // MARK: - 定位页动作

    @objc private func orientationChanged() {
        Prefs.stripVertical = orientVertRadio.state == .on
        refreshState()   // 同步滑块显隐（横排↔纵排）+ 预览重绘
    }
    @objc private func posHChanged(_ sender: NSSlider) {
        // 滑杆值 0=左 ↔ 因子 0=左，方向一致
        Prefs.stripPosX = sender.doubleValue
        posPreview.needsDisplay = true
    }
    @objc private func posVChanged(_ sender: NSSlider) {
        // 滑杆值 0=下/1=上（纵向滑块向上增大），而因子 0=顶——取反对齐直觉
        Prefs.stripPosY = 1 - sender.doubleValue
        posPreview.needsDisplay = true
    }
    @objc private func maxWidthCommitted(_ sender: NSTextField) {
        Prefs.stripMaxWidth = Double(sender.stringValue) ?? Prefs.stripMaxWidth
        refreshState()
    }
    @objc private func marginCommitted(_ sender: NSTextField) {
        Prefs.stripMargin = Double(sender.stringValue) ?? Prefs.stripMargin
        refreshState()
    }

    // MARK: - 快速布局页动作

    @objc private func qlNearCursorChanged() { Prefs.qlNearCursor = qlNearCursorCheck.state == .on; refreshState() }
    @objc private func qlPosHChanged(_ sender: NSSlider) { Prefs.qlPosX = sender.doubleValue; qlPreview.needsDisplay = true }
    @objc private func qlPosVChanged(_ sender: NSSlider) { Prefs.qlPosY = 1 - sender.doubleValue; qlPreview.needsDisplay = true }
    @objc private func qlWidthCommitted(_ sender: NSTextField) {
        Prefs.qlWidth = Double(sender.stringValue) ?? Prefs.qlWidth
        refreshState()
    }
    @objc private func qlHeightCommitted(_ sender: NSTextField) {
        Prefs.qlHeight = Double(sender.stringValue) ?? Prefs.qlHeight
        refreshState()
    }

    /// Carbon 键码 → 可读符号（常用键位映射，未收录的回退为 Key#）
    static func hotkeyDisplay(keyCode: UInt32, modifiers: Int) -> String {
        let base: String
        switch keyCode {
        case 0: base = "A"; case 1: base = "S"; case 2: base = "D"; case 3: base = "F"
        case 4: base = "H"; case 5: base = "G"; case 6: base = "Z"; case 7: base = "X"
        case 8: base = "C"; case 9: base = "V"; case 11: base = "B"; case 12: base = "Q"
        case 13: base = "W"; case 14: base = "E"; case 15: base = "R"; case 16: base = "Y"
        case 17: base = "T"; case 31: base = "O"; case 32: base = "U"; case 34: base = "I"
        case 35: base = "P"; case 37: base = "L"; case 38: base = "J"; case 40: base = "K"
        case 45: base = "N"; case 46: base = "M"
        case 18: base = "1"; case 19: base = "2"; case 20: base = "3"; case 21: base = "4"
        case 23: base = "5"; case 22: base = "6"; case 26: base = "7"; case 28: base = "8"
        case 25: base = "9"; case 29: base = "0"
        case 123: base = L("←"); case 124: base = L("→"); case 125: base = L("↓"); case 126: base = L("↑")
        case 49: base = "Space"; case 36: base = L("↩"); case 48: base = L("⇥")
        default: base = "Key(\(keyCode))"
        }
        let ctrl = modifiers & controlKey != 0 ? L("⌃") : ""
        let opt = modifiers & optionKey != 0 ? L("⌥") : ""
        let cmd = modifiers & cmdKey != 0 ? L("⌘") : ""
        let shift = modifiers & shiftKey != 0 ? L("⇧") : ""
        return ctrl + opt + cmd + shift + base
    }

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

// MARK: - 屏幕位置预览（定位页 / 原版 Screen position 可视化）
//
// 画的是「真实」的图标条：几何与拖拽 overlay 共用 StripGeometry，
// 图标绘制共用 LayoutIconRenderer——预览里看到的比例和位置就是拖拽时的实际效果。

final class ScreenPositionPreviewView: NSView {
    enum Mode {
        case strip        // 布局图标条（定位页）
        case quickLayout  // 快速布局面板块（快速布局页）
    }

    var mode: Mode = .strip {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        // 迷你屏幕按「真实主屏可见区」的尺寸与宽高比等比缩放绘制——
        // 预览即真实：这里看到的图标占比与实际屏幕完全一致
        let vf = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1512, height: 982)
        let availW = bounds.width - 20
        let availH = bounds.height - 20
        var w = availW
        var h = w * vf.height / vf.width
        if h > availH {
            h = availH
            w = h * vf.width / vf.height
        }
        let screen = NSRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h)
        let k = screen.width / vf.width   // 预览像素 / 实际点

        let path = NSBezierPath(roundedRect: screen, xRadius: 10, yRadius: 10)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        let grad = NSGradient(colors: [NSColor(red: 0.80, green: 0.87, blue: 0.95, alpha: 1),
                                       NSColor(red: 0.34, green: 0.50, blue: 0.76, alpha: 1)])
        grad?.draw(from: NSPoint(x: screen.midX, y: screen.maxY),
                   to: NSPoint(x: screen.midX, y: screen.minY), options: [])
        NSGraphicsContext.restoreGraphicsState()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        switch mode {
        case .strip:
            let rects = StripGeometry.iconRects(layoutCount: LayoutStore.layouts.count, in: vf)
            let layouts = LayoutStore.layouts
            for (i, r) in rects.enumerated() where layouts.indices.contains(i) {
                let viewRect = CGRect(x: screen.minX + r.minX * k,
                                      y: screen.minY + r.minY * k,
                                      width: r.width * k,
                                      height: r.height * k)
                LayoutIconRenderer.draw(layout: layouts[i], in: viewRect, flipped: false, style: .light)
            }

        case .quickLayout:
            // 原版 Quick Layout：呼出的是「一个布局图标」（壁纸网格风）
            let w = CGFloat(Prefs.qlWidth) * k
            let h = CGFloat(Prefs.qlHeight) * k
            let x = screen.minX + CGFloat(Prefs.qlPosX) * max(0, screen.width - w)
            let y = screen.maxY - CGFloat(Prefs.qlPosY) * max(0, screen.height - h) - h
            let iconRect = NSRect(x: x, y: y, width: w, height: h)
            let layout = LayoutStore.displayLayouts(for: nil).first
                ?? TidyLayout.builtins[0]
            LayoutIconRenderer.draw(layout: layout, in: iconRect, flipped: false, style: .light)
        }
    }
}

// MARK: - 全局快捷键录制按钮（原版「Click to record shortcut」）

final class HotkeyRecorderButton: NSButton {
    var onRecord: ((UInt32, Int) -> Void)?
    private var monitor: Any?
    private var previousTitle = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
    }

    convenience init(title: String) {
        self.init(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        self.title = title
    }

    required init?(coder: NSCoder) { fatalError(L("init(coder:) 未实现")) }

    override func mouseDown(with event: NSEvent) {
        startRecording()
    }

    private func startRecording() {
        guard monitor == nil else { return }
        previousTitle = title
        title = L("请按下快捷键…（Esc 取消，需含修饰键）")

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if event.keyCode == 53 {  // Esc 取消
                self.stopRecording()
                return nil
            }
            var carbon: Int = 0
            if event.modifierFlags.contains(.command) { carbon |= cmdKey }
            if event.modifierFlags.contains(.option) { carbon |= optionKey }
            if event.modifierFlags.contains(.control) { carbon |= controlKey }
            if event.modifierFlags.contains(.shift) { carbon |= shiftKey }
            guard carbon != 0 else { return nil }  // 无修饰键的按键直接吞掉

            self.onRecord?(UInt32(event.keyCode), carbon)
            self.stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        monitor.map { NSEvent.removeMonitor($0) }
        monitor = nil
        title = previousTitle
    }
}

// MARK: - 布局编辑器（对齐原版 Edit Layout：网格画布上拖画区域，不填数字）

/// 网格画布：在预览网格上拖拽画出区域 / 拖动移动 / 点选删除
final class LayoutGridCanvasView: NSView {
    private(set) var cols: Int
    private(set) var rows: Int
    private(set) var regions: [TidyLayout.Region]
    private(set) var selectedIndex: Int? = nil

    var onChanged: (() -> Void)?

    private enum DragMode {
        case none
        case paint(anchorX: Int, anchorY: Int)
        case move(index: Int, lastX: Int, lastY: Int)
    }
    private var mode: DragMode = .none

    init(cols: Int, rows: Int, regions: [TidyLayout.Region]) {
        self.cols = cols
        self.rows = rows
        self.regions = regions
        super.init(frame: NSRect(x: 0, y: 0, width: 470, height: 300))
    }

    required init?(coder: NSCoder) { fatalError(L("init(coder:) 未实现")) }

    override var isFlipped: Bool { true }   // 顶行在上，与网格 (1,1) 直觉一致

    // MARK: 绘制（浅色壁纸 + 网格 + 深色区域，选中亮蓝描边）

    override func draw(_ dirtyRect: NSRect) {
        let grad = NSGradient(colors: [NSColor(red: 0.80, green: 0.87, blue: 0.95, alpha: 1),
                                       NSColor(red: 0.34, green: 0.50, blue: 0.76, alpha: 1)])
        grad?.draw(from: NSPoint(x: bounds.midX, y: bounds.maxY),
                   to: NSPoint(x: bounds.midX, y: bounds.minY), options: [])

        let cw = bounds.width / CGFloat(cols)
        let ch = bounds.height / CGFloat(rows)
        NSColor.white.withAlphaComponent(0.35).setStroke()
        let grid = NSBezierPath()
        grid.lineWidth = 0.5
        for c in 1..<cols {
            let x = bounds.minX + cw * CGFloat(c)
            grid.move(to: CGPoint(x: x, y: bounds.minY))
            grid.line(to: CGPoint(x: x, y: bounds.maxY))
        }
        for r in 1..<rows {
            let y = bounds.minY + ch * CGFloat(r)
            grid.move(to: CGPoint(x: bounds.minX, y: y))
            grid.line(to: CGPoint(x: bounds.maxX, y: y))
        }
        grid.stroke()

        for (i, region) in regions.enumerated() {
            let w = bounds.width / CGFloat(cols)
            let h = bounds.height / CGFloat(rows)
            let r = NSRect(x: bounds.minX + CGFloat(region.x1 - 1) * w,
                           y: bounds.minY + CGFloat(region.y1 - 1) * h,
                           width: CGFloat(region.x2 - region.x1 + 1) * w,
                           height: CGFloat(region.y2 - region.y1 + 1) * h)
            let path = NSBezierPath(roundedRect: r.insetBy(dx: 1.5, dy: 1.5), xRadius: 4, yRadius: 4)
            NSColor(red: 0.09, green: 0.14, blue: 0.23, alpha: 0.92).setFill()
            path.fill()
            if i == selectedIndex {
                NSColor.white.withAlphaComponent(0.95).setStroke()
                path.lineWidth = 2.5
            } else {
                NSColor(red: 0.38, green: 0.68, blue: 0.95, alpha: 0.85).setStroke()
                path.lineWidth = 1
            }
            path.stroke()
        }
    }

    // MARK: 坐标换算

    private func cellAt(_ point: NSPoint) -> (x: Int, y: Int) {
        let x = min(cols, max(1, Int(point.x / bounds.width * CGFloat(cols)) + 1))
        let y = min(rows, max(1, Int(point.y / bounds.height * CGFloat(rows)) + 1))
        return (x, y)
    }

    // MARK: 交互：空白处拖画新区域；点住已画区域拖动移动

    override func mouseDown(with event: NSEvent) {
        let cell = cellAt(convert(event.locationInWindow, from: nil))
        if let idx = regions.firstIndex(where: { $0.contains(cellX: cell.x, cellY: cell.y) }) {
            selectedIndex = idx
            mode = .move(index: idx, lastX: cell.x, lastY: cell.y)
        } else {
            regions.append(TidyLayout.Region(cell.x, cell.y, cell.x, cell.y))
            selectedIndex = regions.count - 1
            mode = .paint(anchorX: cell.x, anchorY: cell.y)
        }
        needsDisplay = true
        onChanged?()
    }

    override func mouseDragged(with event: NSEvent) {
        let cell = cellAt(convert(event.locationInWindow, from: nil))
        switch mode {
        case .none:
            return
        case .paint(let ax, let ay):
            guard regions.indices.contains(selectedIndex ?? -1) else { return }
            let x1 = min(ax, cell.x), x2 = max(ax, cell.x)
            let y1 = min(ay, cell.y), y2 = max(ay, cell.y)
            regions[selectedIndex!] = TidyLayout.Region(x1, y1, x2, y2)
        case .move(let idx, let lastX, let lastY):
            guard regions.indices.contains(idx) else { return }
            let dx = cell.x - lastX
            let dy = cell.y - lastY
            guard dx != 0 || dy != 0 else { return }
            var r = regions[idx]
            r.x1 = min(max(r.x1 + dx, 1), cols)
            r.x2 = min(max(r.x2 + dx, 1), cols)
            r.y1 = min(max(r.y1 + dy, 1), rows)
            r.y2 = min(max(r.y2 + dy, 1), rows)
            regions[idx] = r
            mode = .move(index: idx, lastX: cell.x, lastY: cell.y)
        }
        needsDisplay = true
        onChanged?()
    }

    override func mouseUp(with event: NSEvent) {
        mode = .none
    }

    // MARK: 网格变化与删除

    /// 网格字段变化：夹紧已有区域到新网格
    func setGrid(cols newCols: Int, rows newRows: Int) {
        cols = newCols
        rows = newRows
        regions = regions.enumerated().map { i, r in
            var x1 = min(r.x1, cols), x2 = min(r.x2, cols)
            var y1 = min(r.y1, rows), y2 = min(r.y2, rows)
            if x1 > x2 { swap(&x1, &x2) }
            if y1 > y2 { swap(&y1, &y2) }
            if x1 > x2 || y1 > y2 { selectedIndex = nil }
            _ = i
            return TidyLayout.Region(max(x1, 1), max(y1, 1), max(x2, 1), max(y2, 1))
        }
        needsDisplay = true
    }

    func deleteSelected() {
        guard let idx = selectedIndex, regions.indices.contains(idx) else { return }
        regions.remove(at: idx)
        selectedIndex = nil
        needsDisplay = true
        onChanged?()
    }
}

final class LayoutEditorWindowController: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    private let window: NSWindow
    private let nameField: NSTextField
    private let colsField: NSTextField
    private let rowsField: NSTextField
    private let scopePopUp = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 26), pullsDown: false)
    private let shortcutRecorder = HotkeyRecorderButton(title: L("未设置（点击录制）"))
    private let canvas: LayoutGridCanvasView
    private let previewView: NSImageView
    private let deleteRegionButton = NSButton(title: L("删除所选区域"), target: nil, action: nil)
    private var working: TidyLayout
    private let isNew: Bool
    private let onCommit: (TidyLayout) -> Void

    /// 关键：编辑器控制器必须静态持有到窗口关闭。
    /// 此前 present() 里是局部变量，方法返回后控制器即被释放——
    /// 窗口还显示着（NSWindow 由 AppKit 窗口列表持有），但所有控件的
    /// target 已是死指针，表现为「弹窗能打开却完全操作不了」。
    private static var active: LayoutEditorWindowController?

    static func present(layout: TidyLayout, isNew: Bool, onCommit: @escaping (TidyLayout) -> Void) {
        let editor = LayoutEditorWindowController(layout: layout, isNew: isNew, onCommit: onCommit)
        LayoutEditorWindowController.active = editor
        editor.window.center()
        editor.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init(layout: TidyLayout, isNew: Bool, onCommit: @escaping (TidyLayout) -> Void) {
        // 所有 let 存储属性必须在 super.init() 之前初始化
        self.working = layout
        self.isNew = isNew
        self.onCommit = onCommit

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 740),
                          styleMask: [.titled, .closable],
                          backing: .buffered, defer: false)
        nameField = NSTextField(string: layout.name)
        colsField = NSTextField(string: String(layout.cols))
        rowsField = NSTextField(string: String(layout.rows))
        canvas = LayoutGridCanvasView(cols: layout.cols, rows: layout.rows, regions: layout.regions)
        previewView = NSImageView(image: SettingsWindowController.thumbnail(for: layout, size: NSSize(width: 200, height: 112)))

        super.init()

        window.title = isNew ? "新增布局" : "编辑布局：\(layout.name)"
        // ARC 下必须为 false：true 会让 AppKit 在 close 时手动释放 ARC 持有的
        // NSWindow，造成过度释放，在下一次 autorelease pool drain 时闪退
        window.isReleasedWhenClosed = false
        window.delegate = self

        buildUI()
    }

    // MARK: UI 构建

    private func buildUI() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 22, bottom: 18, right: 22)
        stack.translatesAutoresizingMaskIntoConstraints = false

        func label(_ t: String) -> NSTextField {
            let f = NSTextField(labelWithString: t)
            f.font = .systemFont(ofSize: 12)
            return f
        }
        func fieldRow(_ views: [NSView]) -> NSStackView {
            let s = NSStackView(views: views)
            s.orientation = .horizontal
            s.spacing = 8
            return s
        }

        // 名称
        nameField.font = .systemFont(ofSize: 13)
        nameField.widthAnchor.constraint(equalToConstant: 380).isActive = true
        nameField.delegate = self
        stack.addArrangedSubview(fieldRow([label(L("名称")), nameField]))

        // 激活快捷键（原版 Activation Shortcut：应用到前台窗口）
        shortcutRecorder.onRecord = { [weak self] keyCode, modifiers in
            self?.working.activationKeyCode = Int(keyCode)
            self?.working.activationModifiers = modifiers
            self?.shortcutRecorder.title = SettingsWindowController.hotkeyDisplay(keyCode: keyCode, modifiers: modifiers)
        }
        shortcutRecorder.widthAnchor.constraint(equalToConstant: 380).isActive = true
        stack.addArrangedSubview(fieldRow([label(L("激活快捷键")), shortcutRecorder]))
        stack.addArrangedSubview(captionText(L("点击录制；录制后按此快捷键把该布局应用到最前面的窗口。Shift+Esc 清除。—— 实际清除方式：点录制后按 Esc 取消。")))

        // 作用域
        scopePopUp.addItem(withTitle: L("所有屏幕"))
        scopePopUp.lastItem?.representedObject = -1
        for screen in NSScreen.screens {
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
            scopePopUp.addItem(withTitle: "仅 \(screen.localizedName)")
            scopePopUp.lastItem?.representedObject = Int(displayID)
            if working.scope == Int(displayID) {
                scopePopUp.select(scopePopUp.lastItem!)
            }
        }
        if working.scope == -1 {
            scopePopUp.selectItem(at: 0)
        }
        stack.addArrangedSubview(fieldRow([label(L("可用屏幕")), scopePopUp]))

        // 网格密度
        colsField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        rowsField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        colsField.alignment = .center
        rowsField.alignment = .center
        colsField.widthAnchor.constraint(equalToConstant: 48).isActive = true
        rowsField.widthAnchor.constraint(equalToConstant: 48).isActive = true
        colsField.delegate = self
        rowsField.delegate = self
        stack.addArrangedSubview(fieldRow([label(L("网格密度")), label(L("宽")), colsField, label(L("× 高")), rowsField,
                                           label(L("（网格越细，区域越精确）"))]))

        // 屏幕布局画布
        stack.addArrangedSubview(sectionCaption(L("屏幕布局")))
        stack.addArrangedSubview(captionText(L("在网格上「按住拖动」画出区域；点住已画区域拖动可移动；画错点「删除所选区域」。")))
        canvas.wantsLayer = true
        canvas.layer?.borderColor = NSColor.separatorColor.cgColor
        canvas.layer?.borderWidth = 1
        canvas.layer?.cornerRadius = 4
        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.widthAnchor.constraint(equalToConstant: 480).isActive = true
        canvas.heightAnchor.constraint(equalToConstant: 300).isActive = true
        canvas.onChanged = { [weak self] in
            self?.syncWorkingFromFields()
        }
        deleteRegionButton.bezelStyle = .rounded
        deleteRegionButton.controlSize = .small
        deleteRegionButton.target = self
        deleteRegionButton.action = #selector(deleteRegionClicked)
        let canvasRow = NSStackView(views: [deleteRegionButton, NSView()])
        canvasRow.orientation = .horizontal
        canvasRow.spacing = 8
        canvasRow.translatesAutoresizingMaskIntoConstraints = false
        canvasRow.widthAnchor.constraint(equalToConstant: 480).isActive = true
        canvasRow.arrangedSubviews[1].setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(canvas)
        stack.setCustomSpacing(4, after: canvas)
        stack.addArrangedSubview(canvasRow)
        stack.setCustomSpacing(12, after: canvasRow)

        // 预览
        stack.addArrangedSubview(sectionCaption(L("预览")))
        previewView.wantsLayer = true
        previewView.layer?.borderColor = NSColor.separatorColor.cgColor
        previewView.layer?.borderWidth = 1
        previewView.layer?.cornerRadius = 4
        stack.addArrangedSubview(previewView)
        stack.setCustomSpacing(14, after: previewView)

        // 取消 / 保存
        let cancelButton = NSButton(title: L("取消"), target: self, action: #selector(cancelClicked))
        let saveButton = NSButton(title: L("保存"), target: self, action: #selector(commitClicked))
        saveButton.keyEquivalent = "\r"
        saveButton.bezelStyle = .rounded
        let flexible = NSView()
        let buttons = NSStackView(views: [cancelButton, flexible, saveButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.translatesAutoresizingMaskIntoConstraints = false
        buttons.widthAnchor.constraint(equalToConstant: 490).isActive = true
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

    private func sectionCaption(_ t: String) -> NSTextField {
        let f = NSTextField(labelWithString: t)
        f.font = .systemFont(ofSize: 13, weight: .semibold)
        return f
    }

    private func captionText(_ t: String) -> NSTextField {
        let f = NSTextField(labelWithString: t)
        f.font = .systemFont(ofSize: 10)
        f.textColor = .secondaryLabelColor
        f.lineBreakMode = .byWordWrapping
        f.maximumNumberOfLines = 2
        f.preferredMaxLayoutWidth = 480
        return f
    }

    // MARK: 状态同步

    /// 画布/字段 → 工作副本（提交与实时预览共用）
    private func syncWorkingFromFields() {
        working.name = nameField.stringValue.isEmpty ? L("未命名") : nameField.stringValue
        let cols = max(1, min(12, Int(colsField.stringValue) ?? working.cols))
        let rows = max(1, min(12, Int(rowsField.stringValue) ?? working.rows))
        if cols != working.cols || rows != working.rows {
            working.cols = cols
            working.rows = rows
            canvas.setGrid(cols: cols, rows: rows)
        }
        working.scope = (scopePopUp.selectedItem?.representedObject as? Int) ?? working.scope
        working.regions = canvas.regions
        previewView.image = SettingsWindowController.thumbnail(for: working, size: NSSize(width: 200, height: 112))
    }

    func controlTextDidChange(_ obj: Notification) {
        syncWorkingFromFields()
    }

    @objc private func deleteRegionClicked() {
        canvas.deleteSelected()
        syncWorkingFromFields()
    }

    @objc private func commitClicked() {
        syncWorkingFromFields()
        // 区域画空时回退为整屏（避免保存出无区域布局）
        if working.regions.isEmpty {
            working.regions = [TidyLayout.Region(1, 1, working.cols, working.rows)]
        }
        onCommit(working)
        window.close()
    }

    @objc private func cancelClicked() {
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        if LayoutEditorWindowController.active === self {
            LayoutEditorWindowController.active = nil
        }
    }
}
// MARK: - 布局列表表格（拖拽排序 / 双击编辑）

extension SettingsWindowController {
    func numberOfRows(in tableView: NSTableView) -> Int {
        LayoutStore.layouts.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard LayoutStore.layouts.indices.contains(row) else { return nil }
        let layout = LayoutStore.layouts[row]
        let cell = NSView()

        let thumb = NSImageView(image: Self.thumbnail(for: layout, size: NSSize(width: 150, height: 84)))
        thumb.frame = NSRect(x: 12, y: 6, width: 150, height: 84)
        cell.addSubview(thumb)

        let name = NSTextField(labelWithString: layout.name)
        name.font = .systemFont(ofSize: 14, weight: .semibold)
        name.frame = NSRect(x: 178, y: 64, width: 400, height: 20)
        cell.addSubview(name)

        let desc: String
        if let first = layout.regions.first {
            desc = layout.regions.count == 1
                ? "\(layout.cols) × \(layout.rows) 网格，从 (\(first.x1), \(first.y1)) 到 (\(first.x2), \(first.y2))"
                : "\(layout.cols) × \(layout.rows) 网格，\(layout.regions.count) 个区域"
        } else {
            desc = "\(layout.cols) × \(layout.rows) 网格"
        }
        let descLabel = NSTextField(labelWithString: desc)
        descLabel.font = .systemFont(ofSize: 12)
        descLabel.textColor = .secondaryLabelColor
        descLabel.frame = NSRect(x: 178, y: 40, width: 440, height: 16)
        cell.addSubview(descLabel)

        let scopeLabel = NSTextField(labelWithString: layout.scope == -1 ? L("所有屏幕") : L("仅指定显示器"))
        scopeLabel.font = .systemFont(ofSize: 11)
        scopeLabel.textColor = .tertiaryLabelColor
        scopeLabel.frame = NSRect(x: 178, y: 20, width: 300, height: 14)
        cell.addSubview(scopeLabel)

        return cell
    }

    // MARK: 拖拽排序

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString(String(row), forType: Self.layoutDragType)
        return item
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo,
                   proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard dropOperation == .above,
              info.draggingPasteboard.types?.contains(Self.layoutDragType) == true else { return [] }
        return .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo,
                   row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let srcString = info.draggingPasteboard.string(forType: Self.layoutDragType),
              let src = Int(srcString),
              LayoutStore.layouts.indices.contains(src) else { return false }

        var list = LayoutStore.layouts
        let item = list.remove(at: src)
        let dst = min(max(row > src ? row - 1 : row, 0), list.count)
        list.insert(item, at: dst)
        LayoutStore.layouts = list
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: dst), byExtendingSelection: false)
        return true
    }
}
