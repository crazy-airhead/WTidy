import Testing
import AppKit
import Carbon.HIToolbox
@testable import WTidy

// 设置窗口布局冒烟测试。
// 注意：离屏 cacheDisplay 渲染不出文字控件（无窗口服务上下文），PNG 只能看定位，
// 因此这里用数值断言校验 tab 容器与页面栈的 frame——确定且可靠。
// 教训（2026-11-13，用户截图驱动）：数值断言只保结构不保观感——页顶对齐、缩略图
// 底色这类「渲染结果」必须用几何换算 + 位图像素采样断言锁死，见后两个测试。
@Suite(.serialized)
@MainActor
struct SettingsRenderTests {
    @Test func settingsLayoutNumbers() {
        _ = NSApplication.shared

        let controller = SettingsWindowController.shared
        controller.present()
        guard let win = NSApp.windows.first(where: { $0.title == "WTidy 偏好设置" }) else {
            Issue.record("设置窗口未创建")
            return
        }
        win.contentView?.layoutSubtreeIfNeeded()
        guard let content = win.contentView else { return }
        let bounds = content.bounds

        // 1) tab 容器应贴满内容区（零约束 + autoresizing）
        guard let tab = content.subviews.compactMap({ $0 as? NSTabView }).first else {
            Issue.record("找不到 NSTabView")
            return
        }
        #expect(abs(tab.frame.width - (bounds.width - 24)) < 1, "tab 容器宽度应贴满内容区（左右留 12）：\(tab.frame) vs \(bounds)")
        // tab 高度 = 窗口内容高 − 底部原版式底栏（46pt 栏 + 上下 16pt 间距）
        #expect(abs(tab.frame.height - (bounds.height - 62)) < 1,
                "tab 容器高度应占据底栏以上区域：\(tab.frame) vs \(bounds)")
        #expect(tab.tabViewItems.count == 4, "布局/行为/定位/关于");
        #expect(tab.tabViewItems.map(\.label) == ["布局", "行为", "定位", "关于"])

        // 注意：AppKit frame 坐标原点在左下角——顶对齐的视图 maxY ≈ 容器高度。
        // NSStackView 自身 flipped，绘制自顶向下；frame 仍在容器坐标系里。

        // 2) 行为页（原版 Options）：页面为滚动容器，栈是其 documentView
        tab.selectTabViewItem(at: 1)
        win.contentView?.layoutSubtreeIfNeeded()
        let general = tab.tabViewItems[1].view!
        guard let scrollV = general as? NSScrollView,
              let stack = scrollV.documentView as? NSStackView else {
            Issue.record("行为页应为滚动容器 + 布局栈")
            return
        }
        stack.layoutSubtreeIfNeeded()
        #expect(stack.frame.width > 150, "栈宽应 > 150，实际 \(stack.frame)")
        #expect(stack.frame.height > 200, "栈高应 > 200（塌陷则失败），实际 \(stack.frame.height)")

        // 3) 行为页：缺权限警告行钉在页首，第一个分组框紧跟小节标题
        let boxes = stack.arrangedSubviews.compactMap { $0 as? NSBox }
        #expect(boxes.count == 3, "行为页应有 3 个分组框（行为/配色/背景），实际 \(boxes.count)")
        if let firstBox = boxes.first {
            // 结构断言：页首是缺权限警告行（已授权时隐藏但仍占位 arrangedSubviews），
            // 其后依次是「行为」小节标题 + 第一个分组框
            let views = stack.arrangedSubviews
            let headRow = views.first as? NSStackView
            #expect(headRow != nil && headRow !== boxes.first,
                    "页首应为缺权限警告行（NSStackView），实际 \(type(of: views.first!))")
            if let boxIdx = views.firstIndex(where: { $0 === firstBox }), boxIdx > 0 {
                let titleField = views[boxIdx - 1] as? NSTextField
                #expect(titleField?.font == Design.Font.sectionTitle,
                        "分组框应紧跟小节标题，实际前一个是 \(type(of: views[boxIdx - 1]))")
            } else {
                Issue.record("第一个分组框位置异常")
            }
            let inner = (firstBox.contentView as? NSStackView)?.arrangedSubviews.filter { $0 is NSButton } ?? []
            #expect(inner.count >= 2, "行为分组框内应含 ⌥ 单选等开关，实际 \(inner.count) 个按钮")
        }

        // 4) 快捷键设置已并入布局体系：布局页应包含布局列表表格（滚动视图内）
        tab.selectTabViewItem(at: 0)
        win.contentView?.layoutSubtreeIfNeeded()
        let layoutsPage = tab.tabViewItems[0].view!
        func hasTableView(_ v: NSView) -> Bool {
            v is NSTableView || v.subviews.contains(where: hasTableView)
        }
        #expect(hasTableView(layoutsPage), "布局页应包含布局列表表格")

        // 离屏渲染 PNG 存档（人工复核定位用；文字渲染缺失是离屏局限）
        if let rep = content.bitmapImageRepForCachingDisplay(in: bounds),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: "/tmp/wtidy-settings-general.png"))
        }
    }

    /// 布局页顶对齐防回归：说明文字距页面顶 = pageInsets.top。
    /// 背景：非翻转文档视图在内容短于视口时被 NSClipView 底对齐——整页下沉、
    /// 顶部空白 137pt（2026-11-13 用户截图实测）。PageStackView 翻转后此断言锁定。
    /// 教训：视口顶距必须算上 clip bounds.origin（此前漏算导致误判「已顶对齐」）。
    @Test func layoutsPageTopAligned() {
        _ = NSApplication.shared
        let controller = SettingsWindowController.shared
        controller.present()
        guard let win = NSApp.windows.first(where: { $0.title == "WTidy 偏好设置" }),
              let tab = win.contentView?.subviews.compactMap({ $0 as? NSTabView }).first,
              let scroll = tab.tabViewItems[0].view as? NSScrollView,
              let stack = scroll.documentView as? NSStackView else {
            Issue.record("布局页应为滚动容器 + 布局栈")
            return
        }
        #expect(stack.isFlipped, "页面栈文档视图必须翻转，否则短内容被底对齐、顶部留白")
        tab.selectTabViewItem(at: 0)
        win.contentView?.layoutSubtreeIfNeeded()
        stack.layoutSubtreeIfNeeded()

        guard let caption = stack.arrangedSubviews.first as? NSTextField else {
            Issue.record("布局页栈首元素应为说明文字（NSTextField）")
            return
        }
        // 视觉顶距按 clip 实际方向计算（NSClipView 的方向跟随文档视图）：
        // 翻转 → minY − origin.y；非翻转 → (origin.y + height) − maxY
        let inClip = scroll.contentView.convert(caption.frame, from: stack)
        let bounds = scroll.contentView.bounds
        let visualTopGap: CGFloat
        if scroll.contentView.isFlipped {
            visualTopGap = inClip.minY - bounds.origin.y
        } else {
            visualTopGap = (bounds.origin.y + bounds.height) - inClip.maxY
        }
        #expect(abs(visualTopGap - Design.Spacing.pageInsets.top) < 3,
                "说明文字应贴页面顶部（pageInsets.top=\(Design.Spacing.pageInsets.top)），实际顶距 \(visualTopGap)pt（clip bounds=\(bounds)）")

        // 说明文字不得溢出内容列，且必须是真换行字段而非单行钉宽——
        // 英文翻译比中文长，labelWithString 的单行 simple label 会被 AppKit 钉
        // `width == 单行宽` 必需约束，越出列宽还连带挤歪下方元素（十六次核对）
        #expect(caption.frame.width <= 629,
                "说明文字宽度应 ≤ 内容列 628pt，实际 \(caption.frame.width)pt")

        // 列表应吃掉页面余量（420 下限 + .fill 填充），页面底部无大空白
        if let listScroll = stack.arrangedSubviews.compactMap({ $0 as? NSScrollView }).first {
            #expect(listScroll.frame.height > 500,
                    "布局列表应填满页面剩余高度（视口 652 − 说明/按钮等 ≈ 95pt），实际 \(listScroll.frame.height)pt")
        }
    }

    /// 布局页列表行视图的公共取用：quarters 行视图（已做行内布局）
    private func quartersRowView(_ table: NSTableView) -> NSView? {
        guard let qRow = LayoutStore.layouts.firstIndex(where: { $0.id == "quarters" }),
              let rowView = table.view(atColumn: 0, row: qRow, makeIfNecessary: true) else {
            Issue.record("quarters 行视图缺失")
            return nil
        }
        rowView.layoutSubtreeIfNeeded()
        return rowView
    }

    private func collect<T: NSView>(_ v: NSView) -> [T] {
        ([v] as [NSView]).flatMap { $0.subviews }.reduce(into: [v as? T].compactMap { $0 }) {
            $0.append(contentsOf: collect($1) as [T])
        }
    }

    /// 布局行快捷键纵列防回归：每区域一个录制钮 + 行尾清除钮（未录制隐藏），
    /// 纵列在行内右对齐、垂直居中且不压左侧文字区（文字列 x=178 宽 250，列 minX 须 > 428）。
    @Test func layoutRowRecorderColumn() {
        _ = NSApplication.shared
        let controller = SettingsWindowController.shared
        controller.present()
        guard let win = NSApp.windows.first(where: { $0.title == "WTidy 偏好设置" }),
              let tab = win.contentView?.subviews.compactMap({ $0 as? NSTabView }).first,
              let scroll = tab.tabViewItems[0].view as? NSScrollView else {
            Issue.record("布局页结构异常")
            return
        }
        tab.selectTabViewItem(at: 0)
        win.contentView?.layoutSubtreeIfNeeded()
        guard let pageStack = scroll.documentView as? NSStackView,
              let listScroll = pageStack.arrangedSubviews.compactMap({ $0 as? NSScrollView }).first,
              let table = listScroll.documentView as? NSTableView else {
            Issue.record("布局页列表缺失")
            return
        }

        tab.selectTabViewItem(at: 0)
        win.contentView?.layoutSubtreeIfNeeded()
        guard let pageStack = scroll.documentView as? NSStackView,
              let listScroll = pageStack.arrangedSubviews.compactMap({ $0 as? NSScrollView }).first,
              let table = listScroll.documentView as? NSTableView else {
            Issue.record("布局页列表缺失")
            return
        }

        // 内置布局已预置区域快捷键（2026-11-13）——本测试验「未录制」基线：
        // 先清空 quarters 的默认快捷键（✕ 淡出禁点、录制钮占位标题才有意义）
        let saved = LayoutStore.layouts
        defer { LayoutStore.layouts = saved }
        var list = LayoutStore.layouts
        guard let q = list.firstIndex(where: { $0.id == "quarters" }) else {
            Issue.record("quarters 缺失")
            return
        }
        list[q].regionHotkeys = [:]
        LayoutStore.layouts = list

        // 多区域布局（quarters，4 区域）：4 个录制钮 + 4 个清除钮（未录制 → 淡出禁点但占位）
        table.reloadData()
        guard let rowView = quartersRowView(table) else { return }
        let recorders: [HotkeyRecorderButton] = collect(rowView)
        #expect(recorders.count == 4, "quarters 行应有 4 个区域录制钮，实际 \(recorders.count)")
        #expect(recorders.allSatisfy { $0.title == L("录制") },
                "未录制的录制钮应显示占位标题（旧版曾因离树回填被抹成空白钮），实际 \(recorders.map(\.title))")
        // 各区域录制钮必须同一竖线（✕ 占位后列几何恒定；折叠方案曾致跨行漂移）。
        // 注意 4 个钮分属 4 个行栈，须换算到行视图坐标再比
        let recMinXs = recorders.map { rowView.convert($0.frame, from: $0.superview).minX }
        if let first = recMinXs.first {
            #expect(recMinXs.allSatisfy { abs($0 - first) < 0.5 },
                    "各区域录制钮应左缘对齐，实际行内 minX \(recMinXs)")
        }
        #expect(recorders.allSatisfy { abs($0.frame.height - 24) < 0.5 },
                "录制钮高度应 24pt（96 行高配 22 偏矮），实际 \(recorders.map { $0.frame.height })")
        let clears: [HotkeyClearButton] = collect(rowView)
        #expect(clears.count == 4, "每区域行尾应各有一个清除钮，实际 \(clears.count)")
        #expect(clears.allSatisfy { $0.alphaValue == 0 && !$0.isEnabled },
                "未录制的清除钮应淡出禁点（占位不折叠），实际 \(clears.map { ($0.alphaValue, $0.isEnabled) })")

        // 纵列右对齐且不压文字区
        if let column = rowView.subviews.first(where: { $0 is NSStackView }) {
            #expect(column.frame.minX > 428, "录制钮纵列不应压文字区（minX 须 > 428），实际 \(column.frame.minX)")
            #expect(column.frame.maxX <= 613, "录制钮纵列右缘应留 16pt 边距（628−16），实际 maxX \(column.frame.maxX)")
            #expect(column.frame.height <= SettingsWindowController.rowHeight,
                    "录制钮纵列不应超出行高 \(SettingsWindowController.rowHeight)，实际 \(column.frame.height)")
        } else {
            Issue.record("行内缺少录制钮纵列")
        }
    }

    /// 已录制态：录制钮回显组合文本、行尾 ✕ 出现且只有该行出现
    @Test func layoutRowRecorderRecordedState() {
        _ = NSApplication.shared
        let controller = SettingsWindowController.shared
        controller.present()
        guard let win = NSApp.windows.first(where: { $0.title == "WTidy 偏好设置" }),
              let tab = win.contentView?.subviews.compactMap({ $0 as? NSTabView }).first,
              let scroll = tab.tabViewItems[0].view as? NSScrollView else {
            Issue.record("布局页结构异常")
            return
        }
        let saved = LayoutStore.layouts
        defer { LayoutStore.layouts = saved }
        var list = LayoutStore.layouts
        guard let q = list.firstIndex(where: { $0.id == "quarters" }) else {
            Issue.record("quarters 缺失")
            return
        }

        tab.selectTabViewItem(at: 0)
        win.contentView?.layoutSubtreeIfNeeded()
        guard let pageStack = scroll.documentView as? NSStackView,
              let listScroll = pageStack.arrangedSubviews.compactMap({ $0 as? NSScrollView }).first,
              let table = listScroll.documentView as? NSTableView else {
            Issue.record("布局页列表缺失")
            return
        }

        // 内置默认态：预置的快捷键（quarters 区域 0 = ⌥⌘1）应直接回显在录制钮上
        table.reloadData()
        guard let defaultRow = quartersRowView(table) else { return }
        let defaultRecorders: [HotkeyRecorderButton] = collect(defaultRow)
        #expect(defaultRecorders.count == 4)
        #expect(defaultRecorders[0].title == SettingsWindowController.hotkeyDisplay(keyCode: 18, modifiers: cmdKey | optionKey),
                "内置默认快捷键应回显（quarters 区域 0 = ⌥⌘1），实际 \(defaultRecorders.map(\.title))")

        // 构造「仅区域 1 已录制」基线：清掉内置默认再录 ⌥⌘H
        list[q].regionHotkeys = [:]
        list[q].regionHotkeys[1] = .init(keyCode: 4, modifiers: cmdKey | optionKey)   // ⌥⌘H
        LayoutStore.layouts = list

        table.reloadData()
        guard let rowView = quartersRowView(table) else { return }

        let recorders: [HotkeyRecorderButton] = collect(rowView)
        #expect(recorders.count == 4)
        let expected = SettingsWindowController.hotkeyDisplay(keyCode: 4, modifiers: cmdKey | optionKey)
        #expect(recorders[1].title == expected, "已录制区域的录制钮应回显组合，实际 \(recorders[1].title)")

        let clears: [HotkeyClearButton] = collect(rowView)
        for (i, clear) in clears.enumerated() {
            let active = (clear.alphaValue == 1 && clear.isEnabled)
            #expect(active == (i == 1), "只有已录制的区域 2 清除钮可见可点，实际 \(clears.map { ($0.alphaValue, $0.isEnabled) })")
        }
        // 已录制行的录制钮仍须与未录制行同位（✕ 占位不折叠的对齐保证），同上换算行视图坐标
        let recMinXs = recorders.map { rowView.convert($0.frame, from: $0.superview).minX }
        if let first = recMinXs.first {
            #expect(recMinXs.allSatisfy { abs($0 - first) < 0.5 },
                    "已录制态各区域录制钮仍应对齐，实际行内 minX \(recMinXs)")
        }
    }

    /// 空白钮根因防回归（2026-11-13 用户截图）：标题必须由状态派生，
    /// 按钮离开窗口层级（reloadData 回收行视图）不得把标题抹成空串
    @Test func recorderTitleSurvivesHierarchyRemoval() {
        _ = NSApplication.shared
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        win.contentView = host

        let plain = HotkeyRecorderButton()
        host.addSubview(plain)
        plain.removeFromSuperview()   // 触发 viewDidMoveToWindow(nil)
        #expect(plain.title == L("录制"), "离树后占位标题不得被抹空，实际 '\(plain.title)'")

        let recorded = HotkeyRecorderButton(displayText: "⌥⌘H")
        host.addSubview(recorded)
        recorded.removeFromSuperview()
        #expect(recorded.title == "⌥⌘H", "离树后已录文本不得被抹空，实际 '\(recorded.title)'")
    }

    /// 区域块内缩必须随图标尺寸收缩（预览即真实）：
    /// 以定位页预览同级的 60×34 小图标渲染「最大化」布局，区域块纵向覆盖应 ≥ 70%。
    /// 背景：内缩曾是绝对 6pt，小图标（预览约 28pt 高）上吃掉 40%+ 高度，
    /// 区域块「漂浮」在卡片中央，rows=1 布局全部变形（2026-11-13 用户截图实测）。
    @Test func thumbnailsScaleCellsToSize() {
        let full = TidyLayout.builtins.first { $0.id == "full" }!
        let img = SettingsWindowController.thumbnail(for: full, size: NSSize(width: 60, height: 34))
        guard let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            Issue.record("缩略图位图化失败")
            return
        }
        // 扫描中部一列：深墨蓝（区域块）像素占整图高度的比例
        let x = rep.pixelsWide / 2
        var darkRows = 0
        for y in 0..<rep.pixelsHigh {
            if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
               c.redComponent < 0.35, c.blueComponent < 0.55 {
                darkRows += 1
            }
        }
        let coverage = Double(darkRows) / Double(rep.pixelsHigh)
        #expect(coverage > 0.70,
                "小图标上区域块应占高度 ≥70%（比例内缩），实际 \(Int(coverage * 100))%——绝对内缩会退化到 65% 以下")
    }

    /// 编辑器页面元素必须收在内容列内（512 = 窗口 560 − pageInsets 左右 48）。
    /// 背景：编辑器说明文字曾是全应用唯一无限宽约束的 caption，英文固有宽度 ~557pt
    /// 溢出内容列直达窗口边缘，约束求解器连带把取消/保存行挤离列缘
    /// （2026-11-13 用户截图两处红框实测：说明文字满窗宽、Save 右缘距列缘 ~47pt）。
    @Test func editorPageStaysInContentColumn() {
        _ = NSApplication.shared
        LayoutEditorWindowController.present(layout: TidyLayout.builtins[0], isNew: true) { _ in }
        defer { NSApp.windows.first(where: { $0.delegate is LayoutEditorWindowController })?.close() }
        guard let win = NSApp.windows.first(where: { $0.delegate is LayoutEditorWindowController }),
              let scroll = win.contentView as? NSScrollView,
              let stack = scroll.documentView as? PageStackView else {
            Issue.record("编辑器窗口应为滚动容器 + PageStackView")
            return
        }
        win.contentView?.layoutSubtreeIfNeeded()
        stack.layoutSubtreeIfNeeded()

        let column: CGFloat = 512   // 编辑器内容列宽（与设置页同规则：窗口宽 − pageInsets 左右 48）
        let insets = Design.Spacing.pageInsets

        // 1) 说明文字限宽在内容列内、贴左缘、不越右缘。
        //    测试进程跑中文（固有宽度 ~470pt 不过界），须人为灌入超列长文本模拟
        //    英文场景——英文翻译更长（~557pt），未限宽会满窗溢出（十一/十六次核对）。
        //    minX 容差 3：NSStackView 对齐存在系统性 2pt 偏移，设置页 caption 同位。
        let captions = stack.arrangedSubviews.compactMap { $0 as? NSTextField }.filter { $0.font == Design.Font.caption }
        #expect(captions.count == 1, "编辑器应只有一条说明文字，实际 \(captions.count)")
        if let caption = captions.first {
            #expect(abs(caption.frame.minX - insets.left) < 3,
                    "说明文字应贴左缘 \(insets.left)pt，实际 minX \(caption.frame.minX)")
            caption.stringValue = String(repeating: "Press and drag on the grid to draw a region; ", count: 4)
            caption.invalidateIntrinsicContentSize()
            for _ in 0..<3 {
                caption.superview?.needsLayout = true
                caption.needsLayout = true
                stack.layoutSubtreeIfNeeded()
            }
            #expect(caption.frame.width <= column + 1,
                    "超长说明文字应被限宽在内容列 \(column)pt 内，实际 \(caption.frame.width)pt")
            #expect(caption.frame.maxX <= insets.left + column + 1,
                    "超长说明文字不得越过内容列右缘 \(insets.left + column)，实际 maxX \(caption.frame.maxX)")
            #expect(caption.frame.height >= 24,
                    "超长说明文字应换行为两行（行高 13，两行 ≈26pt；单行仅 13pt），实际高 \(caption.frame.height)pt")
            #expect(caption.preferredMaxLayoutWidth == column,
                    "说明文字应设 wrapWidth 保证两行换行高度计算正确，实际 \(String(describing: caption.preferredMaxLayoutWidth))")
        }

        // 2) 画布与取消/保存行与内容列同宽对齐（右缘 = 24 + 512）
        if let canvas = stack.arrangedSubviews.compactMap({ $0 as? LayoutGridCanvasView }).first {
            #expect(abs(canvas.frame.width - column) < 1,
                    "画布应与内容列同宽 \(column)pt，实际 \(canvas.frame.width)pt")
            #expect(abs(canvas.frame.maxX - (insets.left + column)) < 1,
                    "画布右缘应与内容列对齐 \(insets.left + column)，实际 maxX \(canvas.frame.maxX)")
        } else {
            Issue.record("编辑器画布缺失")
        }
        let buttonRows = stack.arrangedSubviews.filter { row in
            (row as? NSStackView)?.arrangedSubviews.contains(where: { ($0 as? NSButton)?.title == L("保存") }) ?? false
        }
        #expect(buttonRows.count == 1, "取消/保存行缺失")
        if let row = buttonRows.first as? NSStackView,
           let save = row.arrangedSubviews.compactMap({ $0 as? NSButton }).first(where: { $0.title == L("保存") }) {
            #expect(abs(row.frame.width - column) < 1,
                    "取消/保存行应与内容列同宽 \(column)pt，实际 \(row.frame.width)pt")
            let saveMaxX = row.convert(save.frame, to: stack).maxX
            #expect(abs(saveMaxX - (insets.left + column)) < 1,
                    "保存钮右缘应与内容列对齐 \(insets.left + column)，实际 \(saveMaxX)")
        }

        // 真实窗口截图存档（cacheDisplay 渲染不出文字；实窗 CGWindowList 可以），
        // 人工复核说明文字是否真换行、按钮行是否对齐列缘
        win.center()
        win.makeKeyAndOrderFront(nil)
        Thread.sleep(forTimeInterval: 0.3)
        let winID = CGWindowID(win.windowNumber)
        if let cg = CGWindowListCreateImage(CGRect.null, [.optionIncludingWindow], winID, [.bestResolution]) {
            let rep = NSBitmapImageRep(cgImage: cg)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: "/tmp/wtidy-editor-window.png"))
            }
        }
    }

    /// 缩略图壁纸底带防回归：.light 图标的区域块内缩 6pt，四周必须露出壁纸色带。
    /// 背景：内缩曾为 1.5pt，rows=1 布局的区域块遮住 96% 底色，缩略图远看「白底深块」。
    @Test func thumbnailsShowWallpaperRamp() {
        let halves = TidyLayout.builtins.first { $0.id == "halves" }!
        let img = SettingsWindowController.thumbnail(for: halves, size: NSSize(width: 150, height: 84))
        guard let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            Issue.record("缩略图位图化失败")
            return
        }
        func pixel(_ x: Int, _ y: Int) -> (r: Double, g: Double, b: Double)? {
            rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
                .map { ($0.redComponent, $0.greenComponent, $0.blueComponent) }
        }
        // 采样坐标以「点」给出；位图可能是 2x（Retina lockFocus），按实际分辨率换算
        let scale = Double(rep.pixelsWide) / 150
        func sample(_ x: Double, _ y: Int) -> (r: Double, g: Double, b: Double)? {
            pixel(Int(x * scale), Int(Double(y) * scale))
        }
        // 环带/中缝应露出壁纸色带（蓝主导）；块内应为深墨蓝
        let isRampBlue: (Double, Double, Double) -> Bool = { r, _, b in b > r + 0.2 && b > 0.8 }
        let isPaleRamp: (Double, Double, Double) -> Bool = { r, _, b in b > r + 0.08 && b > 0.92 }
        let isInkCell: (Double, Double, Double) -> Bool = { r, _, b in r < 0.3 && b < 0.5 }
        let samples: [(label: String, x: Double, y: Int, check: (Double, Double, Double) -> Bool)] = [
            ("顶环带", 75, 3, isPaleRamp),    // 色带顶端本就近白，只验「够亮且偏蓝」；x=75 是中缝列，无区域块
            ("左环带", 2, 42, isRampBlue),    // 3pt 内缩下左带只剩 1pt 净宽（边框 0–1pt、块从 3pt 起）
            ("中缝", 74, 42, isRampBlue),     // 避开 x=75 的网格线
            ("左块内", 30, 42, isInkCell),
        ]
        for s in samples {
            guard let p = sample(s.x, s.y) else {
                Issue.record("\(s.label) 采样失败")
                continue
            }
            #expect(s.check(p.r, p.g, p.b),
                    "\(s.label)(\(s.x),\(s.y)) 应为壁纸色带蓝/深墨蓝，实际 r=\(p.r) g=\(p.g) b=\(p.b)")
        }
    }
}
