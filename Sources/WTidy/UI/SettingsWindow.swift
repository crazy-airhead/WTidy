import AppKit
import Carbon.HIToolbox

/// 页面栈文档视图必须翻转：本环境下 NSStackView 实测 isFlipped=false，
/// 非翻转 docView 内容短于视口时会被 NSClipView 底对齐——整页内容下沉、
/// 顶部大片空白（2026-11-13 用户截图实测；此前几何断言漏算 bounds.origin 误判过一次）。
/// 设置页与布局编辑器共用。
final class PageStackView: NSStackView {
    override var isFlipped: Bool { true }
}

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
    private let loginCheck = NSButton(checkboxWithTitle: L("开机自动启动"), target: nil, action: nil)
    private let gapSegment = NSSegmentedControl(labels: [L("贴合"), "4pt", "8pt", "12pt"],
                                                trackingMode: .selectOne, target: nil, action: nil)
    private let permissionRow = NSStackView()

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

        tabView.font = Design.Font.tab
        tabView.addTabViewItem(layoutsTab())
        tabView.addTabViewItem(optionsTab())
        tabView.addTabViewItem(positioningTab())
        tabView.addTabViewItem(aboutTab())

        // 底部栏。窗口固定尺寸不可缩放，全部用静态 frame（零 Auto Layout，
        // 规避 NSTabView 固有尺寸与窗口高度约束的冲突）
        let width = content.bounds.width     // 720
        let height = content.bounds.height   // 760
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

        // 底栏控件与设计边距体系对齐（barInset=24，同 pageInsets 左值）；
        // 旧值 16 是规范外魔法数——与页面卡片（22..698）、内容列（46..674）都不对齐
        loginCheck.frame = NSRect(x: Design.Spacing.barInset, y: (barHeight - 24) / 2, width: 220, height: 24)
        bar.addSubview(loginCheck)
        let doneButton = NSButton(title: L("完成"), target: self, action: #selector(doneClicked))
        doneButton.keyEquivalent = "\r"
        doneButton.bezelStyle = .rounded
        doneButton.frame = NSRect(x: width - Design.Spacing.barInset - 76, y: (barHeight - 28) / 2, width: 76, height: 28)
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
        refreshState()
        window.orderOut(nil)
    }

    func present() {
        refreshState()
        window.center()   // 每次打开都在屏幕居中（窗口创建于 (0,0)，不居中会落在主屏左下角）
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Tab 页构建

    /// 布局页：对齐原版 Layouts——列表（拖拽排序 / 双击编辑）+ 左下角 +/−
    private let layoutTable = LayoutListTableView()
    private let layoutScrollView = NSScrollView()
    private static let layoutDragType = NSPasteboard.PasteboardType("com.allblue.wtidy.layoutrow")

    /// 说明文字限宽在内容列内换行——英文翻译比中文长，放任固有宽度会溢出页面甚至窗口
    private func columnCapped(_ label: NSTextField, width: CGFloat? = nil) -> NSTextField {
        label.widthAnchor.constraint(lessThanOrEqualToConstant: width ?? Self.columnWidth).isActive = true
        return label
    }

    private func layoutsTab() -> NSTabViewItem {
        let (scroll, stack) = makePage()
        stack.spacing = Design.Spacing.groupGap

        let caption = columnCapped(Design.Text.caption(
            L("拖动可更改布局顺序，双击编辑；右侧可为每个区域录制快捷键，按下直接把前台窗口吸到该区域。固定方向快捷键（⌥⌘←/→ 等）始终可用。"),
            wrapWidth: Self.columnWidth))
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
        layoutTable.draggingDestinationFeedbackStyle = .none  // 系统空隙反馈太微弱，改用自绘插入指示线（见 LayoutListTableView）
        layoutTable.registerForDraggedTypes([Self.layoutDragType])  // 不注册则永远不是拖放目标
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("layout"))
        column.width = Self.columnWidth
        layoutTable.addTableColumn(column)

        layoutScrollView.documentView = layoutTable
        layoutScrollView.hasVerticalScroller = true
        layoutScrollView.autohidesScrollers = true
        layoutScrollView.drawsBackground = false
        layoutScrollView.translatesAutoresizingMaskIntoConstraints = false
        // 列表吃掉页面剩余高度（≥420 下限），消除底部大空白：
        // 仅本页用 .fill 分布 + 栈高 ≥ 视口（优先级 900，可被内容增长自然突破转为滚动），
        // 列表是唯一低垂直拥抱（200）的视图，余量全部进列表；行多时列表内部滚动，页面不溢出
        stack.distribution = .fill
        let fillHeight = stack.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor)
        fillHeight.priority = NSLayoutConstraint.Priority(900)
        fillHeight.isActive = true
        layoutScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 420).isActive = true
        layoutScrollView.setContentHuggingPriority(NSLayoutConstraint.Priority(200), for: .vertical)
        layoutScrollView.widthAnchor.constraint(equalToConstant: Self.columnWidth).isActive = true
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
        bottom.widthAnchor.constraint(equalToConstant: Self.columnWidth).isActive = true
        flexible.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(bottom)

        let item = NSTabViewItem(identifier: "layouts")
        item.label = L("布局")
        item.view = scroll
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

    /// 页面容器：滚动视图包裹垂直布局栈（文档视图翻转：短内容顶对齐，长内容滚动）。
    private func makePage() -> (NSScrollView, NSStackView) {
        let stack = PageStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Design.Spacing.stackGap
        stack.edgeInsets = Design.Spacing.pageInsets
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.documentView = stack
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])
        return (scroll, stack)
    }

    /// 内容列宽：页面 676 − pageInsets 左右 48 = 628（窗口固定 720 不可缩放，
    /// 用常量 + 注释；此前硬编码 660 超宽 32pt，「恢复内置布局」被顶出右缘）。
    /// 跨视图约束（相对栈宽）在视图入树前激活会抛 NSGenericException，故不用。
    private static let columnWidth: CGFloat = 628

    // MARK: - 行为页（原版 Options：标题在外、控件在圆角分组框内）

    private let optionHideRadio = NSButton(radioButtonWithTitle: L("按住 ⌥ 隐藏布局图标"), target: nil, action: nil)
    private let optionShowRadio = NSButton(radioButtonWithTitle: L("按住 ⌥ 显示布局图标"), target: nil, action: nil)
    private let statusIconCheck = NSButton(checkboxWithTitle: L("显示菜单栏状态图标"), target: nil, action: nil)
    private let namesCheck = NSButton(checkboxWithTitle: L("在布局图标上显示名称"), target: nil, action: nil)
    private let warnCheck = NSButton(checkboxWithTitle: L("窗口未能调整尺寸时显示警告"), target: nil, action: nil)
    private let groupCheck = NSButton(checkboxWithTitle: L("自动分组相邻互补布局"), target: nil, action: nil)
    private let themeInkRadio = NSButton(radioButtonWithTitle: L("墨蓝"), target: nil, action: nil)
    private let themeGraphiteRadio = NSButton(radioButtonWithTitle: L("石墨"), target: nil, action: nil)
    private let themeTealRadio = NSButton(radioButtonWithTitle: L("青碧"), target: nil, action: nil)
    private let themeVioletRadio = NSButton(radioButtonWithTitle: L("紫罗兰"), target: nil, action: nil)
    private let bgWell = NSImageView(frame: NSRect(x: 0, y: 0, width: 220, height: 124))
    private let bgDefaultButton = NSButton(title: L("默认背景"), target: nil, action: nil)
    private let bgWallpaperButton = NSButton(title: L("使用桌面壁纸"), target: nil, action: nil)

    /// 原版式分组框：小节标题在外，控件装进圆角框；宽度 = 内容列宽
    private func groupBox(_ controls: [NSView]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Design.Spacing.groupGap
        stack.edgeInsets = Design.Spacing.groupInsets
        for c in controls { stack.addArrangedSubview(c) }
        let box = NSBox()
        box.boxType = .primary
        box.title = ""
        box.contentView = stack
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: Self.columnWidth).isActive = true
        return box
    }

    private func optionsTab() -> NSTabViewItem {
        let (scroll, stack) = makePage()
        stack.spacing = Design.Spacing.groupGap

        // 缺权限警告行钉在页首：这是最高优先级的异常状态，沉底会不可见
        let warnIcon = NSImageView(image: NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                                                 accessibilityDescription: nil) ?? NSImage())
        warnIcon.contentTintColor = .systemYellow
        let warnText = Design.Text.bodyLabel(L("缺少辅助功能权限，功能未生效"))
        let grantButton = NSButton(title: L("去授权"), target: self, action: #selector(grantClicked))
        permissionRow.orientation = .horizontal
        permissionRow.spacing = 8
        permissionRow.addArrangedSubview(warnIcon)
        permissionRow.addArrangedSubview(warnText)
        permissionRow.addArrangedSubview(grantButton)
        stack.addArrangedSubview(permissionRow)

        stack.addArrangedSubview(Design.Text.sectionTitle(L("行为")))
        let behaviorIntro = columnCapped(Design.Text.caption(L("⌥ 选项按钮用于控制布局图标的显示。")),
                                         width: Self.columnWidth - 28)   // 分组框内宽（628 − 左右内边距 28）
        optionHideRadio.target = self
        optionHideRadio.action = #selector(optionKeyModeChanged)
        optionShowRadio.target = self
        optionShowRadio.action = #selector(optionKeyModeChanged)
        stack.addArrangedSubview(groupBox([behaviorIntro, optionHideRadio, optionShowRadio,
                                           statusIconCheck, groupCheck, namesCheck, warnCheck]))

        // 注意：groupCheck 已在「行为」框——同一控件实例不能进第二个容器（会被静默移走）
        // 「窗口调整」区已删除（对齐原版）：拖拽分屏 / 全局快捷键 / 吸附动画均为常开行为，不设开关
        stack.addArrangedSubview(Design.Text.sectionTitle(L("图标条配色")))
        stack.addArrangedSubview(groupBox([themeInkRadio, themeGraphiteRadio, themeTealRadio, themeVioletRadio]))

        stack.addArrangedSubview(Design.Text.sectionTitle(L("背景")))
        let bgIntro = columnCapped(Design.Text.caption(L("布局图标条背景可使用默认背景或桌面壁纸。")),
                                   width: Self.columnWidth - 28)
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
        bgWell.layer?.cornerRadius = Design.Radius.insetFrame
        let wellRow = NSStackView(views: [bgWell, bgButtons])
        wellRow.orientation = .horizontal
        wellRow.spacing = 16
        bgInner.addArrangedSubview(wellRow)
        stack.addArrangedSubview(groupBox([bgInner]))

        let item = NSTabViewItem(identifier: "options")
        item.label = L("行为")
        item.view = scroll
        return item
    }

    /// 背景图井预览：图标底色的两种铺法——默认主题深底 / 桌面壁纸+蒙板（预览即真实）
    private func refreshBackgroundWell() {
        let img = NSImage(size: NSSize(width: 220, height: 124))
        img.lockFocus()
        if Prefs.stripBackground == 1,
           let screen = NSScreen.main,
           let url = NSWorkspace.shared.desktopImageURL(for: screen),
           let wallpaper = NSImage(contentsOf: url) {
            wallpaper.draw(in: NSRect(origin: .zero, size: img.size),
                           from: .zero, operation: .sourceOver, fraction: 1)
            // 与图标壁纸底叠同一条压暗蒙板
            Design.Color.stripWallpaperVeil.setFill()
            NSRect(origin: .zero, size: img.size).fill(using: .sourceOver)
        } else {
            // 默认背景 = 图标主题深底（随「图标条配色」联动）
            let grad = NSGradient(colors: StripTheme.at(Prefs.stripTheme).bgColors)
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
        let (scroll, stack) = makePage()

        stack.addArrangedSubview(Design.Text.sectionTitle(L("排列方向")))
        orientHoriRadio.target = self
        orientHoriRadio.action = #selector(orientationChanged)
        orientVertRadio.target = self
        orientVertRadio.action = #selector(orientationChanged)
        let orientRow = NSStackView(views: [orientHoriRadio, orientVertRadio])
        orientRow.orientation = .horizontal
        orientRow.spacing = 16
        stack.addArrangedSubview(orientRow)

        stack.addArrangedSubview(Design.Text.sectionTitle(L("屏幕位置")))
        // 对齐原版：滑块与排列方式联动——横向排列只显示纵向滑块（调上下），
        // 纵向排列只显示横向滑块（调左右）；显隐在 refreshState 里切换
        posHSlider.target = self
        posHSlider.action = #selector(posHChanged)
        posHSlider.isContinuous = true
        // 594 = 内容列 628 − 纵向滑杆 24 − 行距 10；此前 600 会随纵向滑杆一起超出内容列
        posHSlider.widthAnchor.constraint(equalToConstant: 594).isActive = true
        posHSlider.heightAnchor.constraint(equalToConstant: 28).isActive = true
        posVSlider.target = self
        posVSlider.action = #selector(posVChanged)
        posVSlider.isContinuous = true
        posVSlider.isVertical = true
        posVSlider.widthAnchor.constraint(equalToConstant: 24).isActive = true
        posVSlider.heightAnchor.constraint(equalToConstant: 340).isActive = true

        posPreview.translatesAutoresizingMaskIntoConstraints = false
        posPreview.widthAnchor.constraint(equalToConstant: 594).isActive = true
        posPreview.heightAnchor.constraint(equalToConstant: 340).isActive = true

        let previewColumn = NSStackView(views: [posPreview, posHSlider])
        previewColumn.orientation = .vertical
        previewColumn.spacing = 8
        previewColumn.alignment = .leading
        let posRow = NSStackView(views: [previewColumn, posVSlider])
        posRow.orientation = .horizontal
        posRow.spacing = 10
        stack.addArrangedSubview(posRow)

        stack.addArrangedSubview(Design.Text.sectionTitle(L("尺寸")))
        maxWidthField.target = self
        maxWidthField.action = #selector(maxWidthCommitted)
        marginField.target = self
        marginField.action = #selector(marginCommitted)
        maxWidthField.widthAnchor.constraint(equalToConstant: 70).isActive = true
        marginField.widthAnchor.constraint(equalToConstant: 70).isActive = true
        let dimsRow = NSStackView(views: [Design.Text.bodyLabel(L("最大宽度")), maxWidthField,
                                          Design.Text.bodyLabel(L("边距")), marginField])
        dimsRow.orientation = .horizontal
        dimsRow.spacing = Design.Spacing.groupGap
        stack.addArrangedSubview(dimsRow)
        stack.addArrangedSubview(columnCapped(Design.Text.caption(
            L("数值为整条图标条的总宽度；单图标宽 = 可用宽度 ÷ 布局数（基准 150pt，下限 90pt）。"),
            wrapWidth: Self.columnWidth)))

        stack.addArrangedSubview(Design.Text.sectionTitle(L("窗口间隙")))
        gapSegment.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(gapSegment)
        stack.addArrangedSubview(columnCapped(Design.Text.caption(
            L("贴合为窗口完全贴齐；间距可让相邻窗口留出呼吸感。"),
            wrapWidth: Self.columnWidth)))

        let item = NSTabViewItem(identifier: "positioning")
        item.label = L("定位")
        item.view = scroll
        return item
    }

    private func aboutTab() -> NSTabViewItem {
        // 初始尺寸取 tab 内容区（NSTabView 会再拉伸对齐）；居中靠约束，不靠 frame
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 696, height: 698))

        let iconConfig = NSImage.SymbolConfiguration(pointSize: 48, weight: .light)
        let icon = NSImageView(image: NSImage(systemSymbolName: "rectangle.split.2x2", accessibilityDescription: nil)?
            .withSymbolConfiguration(iconConfig) ?? NSImage())
        icon.contentTintColor = .controlAccentColor

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let title = NSTextField(labelWithString: "WTidy \(version)")
        title.font = Design.Font.dialogTitle
        let credit = NSTextField(labelWithString: L("arm64 原生 · 看门狗自愈 · 现代登录项"))
        credit.alignment = .center
        credit.font = Design.Font.hint
        credit.textColor = .secondaryLabelColor

        let logPath = NSTextField(labelWithString: AppLog.shared.logPath.path)
        logPath.font = Design.Font.monoSmall
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
        groupCheck.target = self
        groupCheck.action = #selector(groupChanged)
        for radio in [themeInkRadio, themeGraphiteRadio, themeTealRadio, themeVioletRadio] {
            radio.target = self
            radio.action = #selector(stripThemeChanged)
        }
    }

    private func refreshState() {
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

        // 行为页
        optionHideRadio.state = Prefs.optionKeyMode == 0 ? .on : .off
        optionShowRadio.state = Prefs.optionKeyMode == 1 ? .on : .off
        if Prefs.optionKeyMode == 2 { optionHideRadio.state = .on }  // 两选一：不支持⌥时归入默认隐藏
        statusIconCheck.state = Prefs.showStatusIcon ? .on : .off
        namesCheck.state = Prefs.showLayoutNames ? .on : .off
        warnCheck.state = Prefs.warnOnFail ? .on : .off
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
    }

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
    @objc private func openLogClicked() { NSWorkspace.shared.open(AppLog.shared.logPath) }

    // MARK: - 行为页动作

    @objc private func optionKeyModeChanged() {
        if optionHideRadio.state == .on { Prefs.optionKeyMode = 0 }
        else if optionShowRadio.state == .on { Prefs.optionKeyMode = 1 }
    }

    @objc private func statusIconChanged() { Prefs.showStatusIcon = statusIconCheck.state == .on }
    @objc private func namesChanged() { Prefs.showLayoutNames = namesCheck.state == .on }
    @objc private func warnChanged() { Prefs.warnOnFail = warnCheck.state == .on }
    @objc private func groupChanged() { Prefs.autoGroupLayouts = groupCheck.state == .on }
    @objc private func stripThemeChanged() {
        if themeInkRadio.state == .on { Prefs.stripTheme = 0 }
        else if themeGraphiteRadio.state == .on { Prefs.stripTheme = 1 }
        else if themeTealRadio.state == .on { Prefs.stripTheme = 2 }
        else if themeVioletRadio.state == .on { Prefs.stripTheme = 3 }
        refreshBackgroundWell()
    }
    @objc private func bgDefaultClicked() {
        Prefs.stripBackground = 0
        refreshBackgroundWell()
    }
    @objc private func bgWallpaperClicked() {
        Prefs.stripBackground = 1
        refreshBackgroundWell()
    }

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

    /// 录制快捷键的统一校验：与固定动作/其他布局冲突时弹窗并拒绝。
    /// 返回 true 表示可采用该组合。
    @discardableResult
    static func validateShortcut(keyCode: UInt32, modifiers: Int,
                                 excluding layoutID: String, region: Int? = nil) -> Bool {
        guard let owner = HotkeyManager.shared.conflictOwner(keyCode: keyCode,
                                                             modifiers: modifiers,
                                                             excluding: layoutID,
                                                             region: region) else { return true }
        let alert = NSAlert()
        alert.messageText = L("快捷键冲突")
        alert.informativeText = LF("该组合已被「%@」占用，请换一个。", owner)
        alert.addButton(withTitle: L("好"))
        alert.runModal()
        return false
    }
}

// MARK: - 屏幕位置预览（定位页 / 原版 Screen position 可视化）
//
// 画的是「真实」的图标条：几何与拖拽 overlay 共用 StripGeometry，
// 图标绘制共用 LayoutIconRenderer——预览里看到的比例和位置就是拖拽时的实际效果。

final class ScreenPositionPreviewView: NSView {

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

        let path = NSBezierPath(roundedRect: screen,
                                xRadius: Design.Radius.screenFrame, yRadius: Design.Radius.screenFrame)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        // 预览即真实：迷你屏底色与布局图标共用同一条浅色壁纸色带
        let grad = Design.Color.makeWallpaperGradient()
        grad?.draw(from: NSPoint(x: screen.midX, y: screen.maxY),
                   to: NSPoint(x: screen.midX, y: screen.minY), options: [])
        NSGraphicsContext.restoreGraphicsState()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        // 布局图标条预览：真实屏幕等比 + 浅色风格图标。
        // iconRects 返回全局屏幕坐标，必须先减去 visibleFrame 原点再乘缩放系数，
        // 否则菜单栏高度（vf.minY≈38pt）会被一起缩放，条的位置偏高（2026-11-13 修正）
        let rects = StripGeometry.iconRects(layoutCount: LayoutStore.layouts.count, in: vf)
        let layouts = LayoutStore.layouts
        for (i, r) in rects.enumerated() where layouts.indices.contains(i) {
            let viewRect = CGRect(x: screen.minX + (r.minX - vf.minX) * k,
                                  y: screen.minY + (r.minY - vf.minY) * k,
                                  width: r.width * k,
                                  height: r.height * k)
            LayoutIconRenderer.draw(layout: layouts[i], in: viewRect, flipped: false, style: .light)
        }
    }
}

// MARK: - 全局快捷键录制按钮（macOS 快捷键设置惯例）

/// 点击录制：录制态高亮（强调色描边）；Esc 取消；Delete/⌦ 清除（macOS 惯例）；
/// 无修饰键的按键不静默吞掉，标题即时提示。
final class HotkeyRecorderButton: NSButton {
    var onRecord: ((UInt32, Int) -> Void)?
    var onClear: (() -> Void)?
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

    /// 窗口关闭/按钮离树时务必收掉 monitor，否则局部键盘监听泄漏
    override func viewDidMoveToWindow() {
        if window == nil { stopRecording() }
    }

    private func startRecording() {
        guard monitor == nil else { return }
        previousTitle = title
        title = L("输入快捷键…")
        bezelColor = .controlAccentColor   // 录制态视觉高亮

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            switch event.keyCode {
            case 53:   // Esc 取消
                self.stopRecording()
                return nil
            case 51, 117:   // Delete / ⌦：清除已录快捷键
                self.stopRecording()
                self.onClear?()
                return nil
            default:
                break
            }
            var carbon: Int = 0
            if event.modifierFlags.contains(.command) { carbon |= cmdKey }
            if event.modifierFlags.contains(.option) { carbon |= optionKey }
            if event.modifierFlags.contains(.control) { carbon |= controlKey }
            if event.modifierFlags.contains(.shift) { carbon |= shiftKey }
            guard carbon != 0 else {
                self.title = L("需含修饰键（⌃⌥⌘⇧）")   // 提示而非静默吞掉
                return nil
            }

            self.stopRecording()
            self.onRecord?(UInt32(event.keyCode), carbon)
            return nil
        }
    }

    private func stopRecording() {
        monitor.map { NSEvent.removeMonitor($0) }
        monitor = nil
        bezelColor = nil
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
        // 画布底色与布局图标 .light 风格共用同一条浅色壁纸色带（预览即真实）
        // 本视图翻转（isFlipped=true）：from=minY 才是视觉顶——翻转视图里 from=maxY 首色会落到视觉底部（实测）
        let grad = Design.Color.makeWallpaperGradient()
        grad?.draw(from: NSPoint(x: bounds.midX, y: bounds.minY),
                   to: NSPoint(x: bounds.midX, y: bounds.maxY), options: [])

        let cw = bounds.width / CGFloat(cols)
        let ch = bounds.height / CGFloat(rows)
        Design.Color.gridLineLight.setStroke()
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
            let path = NSBezierPath(roundedRect: r.insetBy(dx: Design.Spacing.cellInsetDark,
                                                           dy: Design.Spacing.cellInsetDark),
                                    xRadius: Design.Radius.cell, yRadius: Design.Radius.cell)
            Design.Color.cellInkFill.setFill()
            path.fill()
            if i == selectedIndex {
                Design.Color.focusLine.setStroke()
                path.lineWidth = 2.5
            } else {
                Design.Color.cellAccentStroke.setStroke()
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

        window.title = isNew ? L("新增布局") : LF("编辑布局：%@", layout.name)
        // ARC 下必须为 false：true 会让 AppKit 在 close 时手动释放 ARC 持有的
        // NSWindow，造成过度释放，在下一次 autorelease pool drain 时闪退
        window.isReleasedWhenClosed = false
        window.delegate = self

        buildUI()
    }

    // MARK: UI 构建

    private func buildUI() {
        let stack = PageStackView()   // 滚动容器文档视图必须翻转（短内容顶对齐）
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Design.Spacing.stackGap
        stack.edgeInsets = Design.Spacing.pageInsets
        stack.translatesAutoresizingMaskIntoConstraints = false

        func label(_ t: String) -> NSTextField {
            Design.Text.bodyLabel(t)
        }
        func fieldRow(_ views: [NSView]) -> NSStackView {
            let s = NSStackView(views: views)
            s.orientation = .horizontal
            s.spacing = Design.Spacing.groupGap
            return s
        }

        // 名称
        nameField.widthAnchor.constraint(equalToConstant: 380).isActive = true
        nameField.delegate = self
        stack.addArrangedSubview(fieldRow([label(L("名称")), nameField]))

        // 快捷键不在编辑器设：统一在布局列表行内按区域录制（冲突一目了然）

        // 作用域
        scopePopUp.addItem(withTitle: L("所有屏幕"))
        scopePopUp.lastItem?.representedObject = -1
        for screen in NSScreen.screens {
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
            scopePopUp.addItem(withTitle: LF("仅 %@", screen.localizedName))
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
        colsField.font = Design.Font.monoField
        rowsField.font = Design.Font.monoField
        colsField.alignment = .center
        rowsField.alignment = .center
        colsField.widthAnchor.constraint(equalToConstant: 48).isActive = true
        rowsField.widthAnchor.constraint(equalToConstant: 48).isActive = true
        colsField.delegate = self
        rowsField.delegate = self
        stack.addArrangedSubview(fieldRow([label(L("网格密度")), label(L("宽")), colsField, label(L("× 高")), rowsField,
                                           label(L("（网格越细，区域越精确）"))]))

        // 屏幕布局画布
        stack.addArrangedSubview(Design.Text.sectionTitle(L("屏幕布局")))
        stack.addArrangedSubview(Design.Text.caption(L("在网格上「按住拖动」画出区域；点住已画区域拖动可移动；画错点「删除所选区域」。")))
        canvas.wantsLayer = true
        canvas.layer?.borderColor = NSColor.separatorColor.cgColor
        canvas.layer?.borderWidth = 1
        canvas.layer?.cornerRadius = Design.Radius.insetFrame
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
        stack.addArrangedSubview(Design.Text.sectionTitle(L("预览")))
        previewView.wantsLayer = true
        previewView.layer?.borderColor = NSColor.separatorColor.cgColor
        previewView.layer?.borderWidth = 1
        previewView.layer?.cornerRadius = Design.Radius.insetFrame
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
        buttons.widthAnchor.constraint(equalToConstant: 512).isActive = true   // 编辑器内容列宽（560 − pageInsets 48），取消/保存行右缘与列对齐
        flexible.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(buttons)

        // 内容超过窗口高度（多区域布局的区域快捷键行）时滚动，与设置页同款模式
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.documentView = stack
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])
        window.contentView = scroll
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
        // 区域被删后，越界的区域快捷键随之失效
        working.regionHotkeys = working.regionHotkeys.filter { $0.key < working.regions.count }
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

/// 拖拽排序的插入位置指示线：强调色圆点 + 圆角横线，落在插入行边界上（系统拖放指示样式）
final class LayoutDropIndicatorView: NSView {
    private static let dotDiameter: CGFloat = 7
    private static let lineThickness: CGFloat = 2
    private static let edgeInset: CGFloat = 5

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        autoresizingMask = [.width]   // 随表格宽度伸缩
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 显示在表格坐标 y（目标行的上边界；追加到末尾时为底边）
    func show(atBoundaryY y: CGFloat, width: CGFloat) {
        let d = Self.dotDiameter
        frame = NSRect(x: Self.edgeInset, y: y - d / 2,
                       width: max(0, width - Self.edgeInset * 2), height: d)
        superview?.addSubview(self, positioned: .above, relativeTo: nil)  // 行视图陆续入列，保持指示线置顶
        isHidden = false
        needsDisplay = true
    }

    func hide() {
        isHidden = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let d = Self.dotDiameter
        let lineRect = NSRect(x: d / 2, y: (bounds.height - Self.lineThickness) / 2,
                              width: bounds.width - d / 2, height: Self.lineThickness)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: lineRect, xRadius: Self.lineThickness / 2, yRadius: Self.lineThickness / 2).fill()
        NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: d, height: d)).fill()
    }
}

/// 布局列表表格：托管插入指示线，并在拖拽离开/结束时收起
final class LayoutListTableView: NSTableView {
    private let dropLine = LayoutDropIndicatorView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(dropLine)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 在第 row 行的上边界显示插入指示线（row == 行数即追加到末尾）
    func showDropLine(atBoundaryRow row: Int) {
        let step = rowHeight + intercellSpacing.height   // 无表头、行高一致，行边界即 row * step
        dropLine.show(atBoundaryY: CGFloat(row) * step, width: bounds.width)
    }

    func hideDropLine() {
        dropLine.hide()
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        super.draggingExited(sender)
        hideDropLine()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        super.draggingEnded(sender)
        hideDropLine()
    }
}

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
        name.font = Design.Font.listTitle
        name.frame = NSRect(x: 178, y: 64, width: 250, height: 20)
        cell.addSubview(name)

        let desc: String
        if let first = layout.regions.first {
            desc = layout.regions.count == 1
                ? LF("%d × %d 网格，从 (%d, %d) 到 (%d, %d)", layout.cols, layout.rows, first.x1, first.y1, first.x2, first.y2)
                : LF("%d × %d 网格，%d 个区域", layout.cols, layout.rows, layout.regions.count)
        } else {
            desc = LF("%d × %d 网格", layout.cols, layout.rows)
        }
        let descLabel = NSTextField(labelWithString: desc)
        descLabel.font = Design.Font.body
        descLabel.textColor = .secondaryLabelColor
        descLabel.frame = NSRect(x: 178, y: 40, width: 250, height: 16)
        cell.addSubview(descLabel)

        let scopeLabel = NSTextField(labelWithString: layout.scope == -1 ? L("所有屏幕") : L("仅指定显示器"))
        scopeLabel.font = Design.Font.hint
        scopeLabel.textColor = .tertiaryLabelColor
        scopeLabel.frame = NSRect(x: 178, y: 20, width: 300, height: 14)
        cell.addSubview(scopeLabel)

        // 快捷键统一在行内设置：每区域一个录制钮（按下直接吸到该区域，跳过投影选区），
        // 纵列靠右、垂直居中；旧版布局级快捷键（若已设）保留在列顶，可改可清
        let recColumn = NSStackView()
        recColumn.orientation = .vertical
        recColumn.spacing = 2
        recColumn.alignment = .trailing
        if let kc = layout.activationKeyCode, kc > 0, let mods = layout.activationModifiers {
            let rec = makeShortcutRecorder(layoutID: layout.id, region: nil,
                                           current: Self.hotkeyDisplay(keyCode: UInt32(kc), modifiers: mods))
            let tag = Design.Text.caption(L("布局"))
            let row = NSStackView(views: [tag, rec])
            row.orientation = .horizontal
            row.spacing = 6
            recColumn.addArrangedSubview(row)
        }
        for i in 0..<layout.regions.count {
            let current = layout.regionHotkeys[i].flatMap {
                $0.keyCode > 0 ? Self.hotkeyDisplay(keyCode: UInt32($0.keyCode), modifiers: $0.modifiers) : nil
            }
            let rec = makeShortcutRecorder(layoutID: layout.id, region: i, current: current)
            rec.widthAnchor.constraint(equalToConstant: 108).isActive = true
            rec.heightAnchor.constraint(equalToConstant: 20).isActive = true
            if layout.regions.count > 1 {
                let tag = Design.Text.caption(LF("区域 %d", i + 1))
                let row = NSStackView(views: [tag, rec])
                row.orientation = .horizontal
                row.spacing = 6
                recColumn.addArrangedSubview(row)
            } else {
                recColumn.addArrangedSubview(rec)
            }
        }
        let colSize = recColumn.fittingSize
        recColumn.frame = NSRect(x: Self.columnWidth - 12 - colSize.width,
                                 y: (96 - colSize.height) / 2,
                                 width: colSize.width, height: colSize.height)
        cell.addSubview(recColumn)

        return cell
    }

    /// 列表行的快捷键录制钮：region=nil 为旧版布局级（按窗口位置投影选区），
    /// region=i 直接吸到区域 i。点击即录、Delete 清除、冲突弹窗拒绝；
    /// 写回 LayoutStore 会广播 prefsChanged，HotkeyManager 自动重注册。
    private func makeShortcutRecorder(layoutID: String, region: Int?, current: String?) -> HotkeyRecorderButton {
        let rec = HotkeyRecorderButton(title: current ?? L("录制"))
        rec.controlSize = .small
        rec.font = Design.Font.monoBadge
        rec.onRecord = { [weak self] keyCode, modifiers in
            guard Self.validateShortcut(keyCode: keyCode, modifiers: modifiers,
                                        excluding: layoutID, region: region) else { return }
            var list = LayoutStore.layouts
            guard let idx = list.firstIndex(where: { $0.id == layoutID }) else { return }
            if let region {
                list[idx].regionHotkeys[region] = .init(keyCode: Int(keyCode), modifiers: modifiers)
            } else {
                list[idx].activationKeyCode = Int(keyCode)
                list[idx].activationModifiers = modifiers
            }
            LayoutStore.layouts = list
            self?.layoutTable.reloadData()
        }
        rec.onClear = { [weak self] in
            var list = LayoutStore.layouts
            guard let idx = list.firstIndex(where: { $0.id == layoutID }) else { return }
            if let region {
                list[idx].regionHotkeys[region] = nil
            } else {
                list[idx].activationKeyCode = nil
                list[idx].activationModifiers = nil
            }
            LayoutStore.layouts = list
            self?.layoutTable.reloadData()
        }
        return rec
    }

    // MARK: 拖拽排序

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString(String(row), forType: Self.layoutDragType)
        return item
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo,
                   proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard info.draggingPasteboard.types?.contains(Self.layoutDragType) == true else {
            layoutTable.hideDropLine()
            return []
        }
        // AppKit 默认提议 .on，必须主动改为 .above（插入语义）
        tableView.setDropRow(row, dropOperation: .above)
        layoutTable.showDropLine(atBoundaryRow: row)   // 插入位置画一条强调色指示线
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
        layoutTable.hideDropLine()
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: dst), byExtendingSelection: false)
        return true
    }
}
