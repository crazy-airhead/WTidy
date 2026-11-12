import Testing
import AppKit
@testable import WTidy

// 设置窗口布局冒烟测试。
// 注意：离屏 cacheDisplay 渲染不出文字控件（无窗口服务上下文），PNG 只能看定位，
// 因此这里用数值断言校验 tab 容器与页面栈的 frame——确定且可靠。
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

        // 2) 行为页（原版 Options）：栈应顶对齐（maxY≈页高）、靠左、尺寸合理
        tab.selectTabViewItem(at: 1)
        win.contentView?.layoutSubtreeIfNeeded()
        let general = tab.tabViewItems[1].view!
        guard let stack = general.subviews.compactMap({ $0 as? NSStackView }).first else {
            Issue.record("通用页找不到布局栈")
            return
        }
        #expect(stack.frame.minX <= 40, "栈应靠左，实际 \(stack.frame)")
        #expect(abs(stack.frame.maxY - general.bounds.height) < 30, "栈应顶对齐 maxY≈\(general.bounds.height)，实际 \(stack.frame)")
        #expect(stack.frame.width > 150, "栈宽应 > 150，实际 \(stack.frame.width)")
        #expect(stack.frame.height > 200, "栈高应 > 200（塌陷则失败），实际 \(stack.frame.height)")

        // 3) 行为页：第一个分组框应靠页面顶部，框内应含功能开关
        let boxes = stack.arrangedSubviews.compactMap { $0 as? NSBox }
        #expect(boxes.count == 4, "行为页应有 4 个分组框（行为/窗口调整/配色/背景），实际 \(boxes.count)")
        if let firstBox = boxes.first {
            let f = general.convert(firstBox.frame, from: stack)
            #expect(f.maxY > general.bounds.height * 0.7, "第一个分组框应靠页面顶部，实际 \(f)")
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
}
