import Testing
import AppKit
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

        guard let caption = stack.arrangedSubviews.first else {
            Issue.record("布局页栈首元素缺失")
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

        // 说明文字不得溢出内容列（英文翻译比中文长，未限宽时固有宽度直达窗口边缘被裁断）
        #expect(caption.frame.width <= 629,
                "说明文字宽度应 ≤ 内容列 628pt，实际 \(caption.frame.width)pt")

        // 列表应吃掉页面余量（420 下限 + .fill 填充），页面底部无大空白
        if let listScroll = stack.arrangedSubviews.compactMap({ $0 as? NSScrollView }).first {
            #expect(listScroll.frame.height > 500,
                    "布局列表应填满页面剩余高度（视口 652 − 说明/按钮等 ≈ 95pt），实际 \(listScroll.frame.height)pt")
        }
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
