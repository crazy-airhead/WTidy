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
        guard let win = NSApp.windows.first(where: { $0.title == "WTidy 设置" }) else {
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
        #expect(abs(tab.frame.width - bounds.width) < 1, "tab 容器宽度应贴满：\(tab.frame) vs \(bounds)")
        #expect(abs(tab.frame.height - bounds.height) < 1, "tab 容器高度应贴满")
        #expect(tab.tabViewItems.count == 6, "布局/行为/定位/快速布局/快捷键/关于")
        #expect(tab.tabViewItems.map(\.label) == ["布局", "行为", "定位", "快速布局", "快捷键", "关于"])

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

        // 3) 通用页第一个复选框应在栈顶部（转换到页面坐标后靠近页面顶端）
        guard let firstCheck = stack.arrangedSubviews.first(where: { $0 is NSButton }) else {
            Issue.record("找不到功能开关")
            return
        }
        let inGeneral = general.convert(firstCheck.frame, from: stack)
        #expect(inGeneral.maxY > general.bounds.height * 0.8, "功能开关应靠页面顶部，实际 \(inGeneral)")

        // 4) 快捷键页应有 12 行且不塌陷（需先选中该 tab 才会布局）
        tab.selectTabViewItem(at: 4)
        win.contentView?.layoutSubtreeIfNeeded()
        let hotkeys = tab.tabViewItems[4].view!
        guard let hkStack = hotkeys.subviews.compactMap({ $0 as? NSStackView }).first else {
            Issue.record("快捷键页找不到布局栈")
            return
        }
        let rows = hkStack.arrangedSubviews.filter { $0 is NSStackView }
        #expect(rows.count == 12, "应有 12 行快捷键，实际 \(rows.count)")
        #expect(hkStack.frame.height > 250, "快捷键栈不应塌陷，实际 \(hkStack.frame.height)")
        #expect(abs(hkStack.frame.maxY - hotkeys.bounds.height) < 30, "快捷键栈应顶对齐，实际 \(hkStack.frame)")
        tab.selectTabViewItem(at: 0)

        // 离屏渲染 PNG 存档（人工复核定位用；文字渲染缺失是离屏局限）
        if let rep = content.bitmapImageRepForCachingDisplay(in: bounds),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: "/tmp/wtidy-settings-general.png"))
        }
    }
}
