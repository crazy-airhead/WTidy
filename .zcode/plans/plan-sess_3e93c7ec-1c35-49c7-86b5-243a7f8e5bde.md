# WTidy — 原生重制 Window Tidy 分屏工具

## Context（背景）

原版 Window Tidy 2.1.5（Light Pillar，2017）近半年「经常分屏失效、需手动重开」。诊断结论：
1. **登录自启早已失效**：BTM 记录 Last Use 停在 2026-07-03，重启后进程根本没起来；
2. **拖拽监听静默失灵**：无崩溃报告、30 天日志无系统拒绝/杀死记录——2017 年的 AX 观察代码在睡眠唤醒/显示器插拔/切前台后丢监听且不自愈；
3. **寿命问题**：纯 x86_64 靠 Rosetta 2 转译（Apple 淘汰中）、Crashlytics 域名已死、开发商停更多年。

重制目标：**arm64 原生 + 修复两个病根**（自启用现代 SMAppService；监听带看门狗自愈 + 状态可见）。功能 = 拖拽分屏（原版招牌）+ 全局快捷键兜底。命名 **WTidy**，与原版共存于 /Applications，验证后停用原版。

## 技术选型

- **Swift 6.4 工具链（CLT 即可，无需 Xcode）**：已验证 AppKit/SwiftUI swiftmodule 均在 SDK framework 内
- SwiftPM 管理，语言模式 Swift 5（规避 Carbon C 回调/AX RunLoop 与 strict concurrency 的摩擦）
- AppKit 为主（菜单栏、Overlay、拖拽监听），SwiftUI 仅设置窗口
- 部署目标 macOS 13.0（SMAppService 要求；本机 27.0.1）
- 无沙盒、ad-hoc 签名（本地构建不隔离，AX 权限走用户 TCC 授权）

## 项目结构

```
/Users/airhead/WorkSpace/allblue/WindowTidy/
├── Package.swift
├── README.md                     # 使用说明 + 权限引导 + 原版处置说明
├── scripts/
│   ├── build-app.sh              # swift build → 组装 WTidy.app → adhoc 签名；--install 装入 /Applications
│   └── make-icon.swift           # CoreGraphics 渲染 2×2 网格图标 → iconutil → icns
├── AppResources/Info.plist       # LSUIElement、NSAccessibilityUsageDescription、bundle id com.allblue.wtidy
└── Sources/WTidy/
    ├── main.swift                # NSApplication 程序化启动
    ├── AppDelegate.swift         # 装配各模块
    ├── Core/
    │   ├── AXWindow.swift        # AX 元素封装：读写 frame、pid、标题、role
    │   ├── WindowWatcher.swift   # 拖拽检测状态机（moved 通知 + 按键轮询）
    │   ├── SnapEngine.swift      # 布局与几何（纯函数，单元测试重点）
    │   └── AccessibilityService.swift  # AX 信任检查 + observer 生命周期
    ├── Overlay/
    │   ├── OverlayController.swift   # 每屏窗口生命周期
    │   ├── OverlayWindow.swift       # 透明、非激活、ignoresMouseEvents 的高层级窗口
    │   └── OverlayView.swift         # AppKit 绘制布局缩略图条 + 分区高亮
    ├── Hotkeys/HotkeyManager.swift  # Carbon RegisterEventHotKey
    ├── UI/
    │   ├── StatusMenuController.swift  # 状态图标（绿=正常/黄=缺权限）+ 菜单
    │   ├── SettingsWindow.swift       # SwiftUI 设置
    │   └── Onboarding.swift           # 首次启动权限引导
    └── Support/
        ├── Preferences.swift       # UserDefaults
        ├── LoginItem.swift         # SMAppService.mainApp
        └── AppLog.swift            # ~/Library/Logs/WTidy.log，512KB 自动轮转
└── Tests/WTidyTests/SnapEngineTests.swift
```

## 关键实现细节

**拖拽分屏（招牌功能，忠实还原原版两段式交互）**
1. 监听前台 app 的聚焦窗口 `kAXMovedNotification`；配合 `CGEventSource.buttonState(.combinedSessionState, .left)` 判定「正在拖拽」（窗口拖拽期间全局鼠标监听不可靠，按钮状态轮询 30Hz 是成熟做法）
2. 位移超过阈值（≥24pt 或 ≥2 次moved事件，去抖防误触）→ 在**光标所在屏**顶部弹出布局缩略图条：½左右、½上下、四分、三等分、2/3、最大化
3. 拖着窗口悬停某个缩略图 → 该布局在整屏展开为半透明分区并实时高亮光标下分区
4. 松手：分区有效 → AX 写入 position/size 吸附（带可配置间隙 gap，默认 0 还原原版）；其他位置松手 → 什么都不做（正常拖拽），Overlay 淡出
5. 跳过自身窗口、全屏窗口、无 AX 支持的窗口（快捷键兜底这类应用）

**看门狗（治原版病根之二）**
- 事件驱动重挂 observer：切换前台 app、屏幕睡眠/唤醒、显示器参数变化（`didChangeScreenParametersNotification`，对应外接屏插拔）、Space 切换
- 兜底心跳：每 10s 校验 AXIsProcessTrusted + observer 有效性，异常自动重建
- 菜单栏图标三态（绿/黄/灰），菜单直读显示「监听状态 + 最近一次吸附时间」——让「静默死亡」变得**可见**
- 全程文件日志，出问题可追溯

**登录自启（治原版病根之一）**：SMAppService（macOS 13+ 的现代 API，BTM 原生支持），Onboarding 和设置里一键开关。

**快捷键（兜底）**：⌥⌘←/→ 左右半，⌃⌥⌘↑/↓ 上下半，⌃⌥⌘F 最大化，⌃⌥⌘C 居中，⌥⌘[ / \ / ] 三等分，⌃⌥⌘Z 恢复吸附前位置（吸附前自动记录原 frame）。

**与 macOS 27 原生窗口磁贴共存**：两者可并存（我们由顶部缩略图条触发，原生由屏幕边缘触发）；README 说明如嫌冲突可在系统设置关闭原生磁贴。不改动用户系统设置。

## 实施步骤

1. 脚手架：Package.swift、Info.plist、main.swift、构建脚本骨架；`swift build` 通过
2. Core 层：AXWindow、SnapEngine（布局几何纯函数）+ 全量单元测试
3. 拖拽链路：AccessibilityService、WindowWatcher 状态机 → 手动验证 moved 事件到达
4. Overlay：两段式 UI + 拖拽全流程打通（此步结束后即可真机体验拖拽吸附）
5. 快捷键 + 恢复位置
6. UI：状态菜单、Onboarding、SwiftUI 设置（间隙/自启/开关）
7. 看门狗 + 日志 + 登录自启
8. 图标生成脚本、README、整包构建安装

## 验证

- `swift build -c release` + `swift test`（SnapEngine 几何：多屏不同 inset、gap、三等分、恢复逻辑）
- `scripts/build-app.sh --install` 产出 /Applications/WTidy.app，`codesign --verify` 通过，`open` 启动正常
- **需要你配合的 GUI 步骤**：系统设置里授予辅助功能权限（Onboarding 会引导）；然后手动验收清单——双屏拖拽吸附、全部快捷键、合盖唤醒后监听仍活（图标绿色）、拔插外接屏、重启后自启成功
- 查看日志确认心跳与吸附记录

## 收尾（验证通过后）

- 退出原版：`osascript -e 'quit app "Window Tidy"'`
- 引导你在「系统设置 → 通用 → 登录项」移除原版的登录条目（其自启本已失效，清掉避免歧义）；原版 app 保留在 /Applications 可随时回退
- WTidy 开启自启，正式接管

## 风险与对策

- SwiftUI 编译若遇 CLT 模块问题 → 设置窗口降级纯 AppKit（核心功能不依赖 SwiftUI）
- 部分应用（个别 Java/Electron）不发 AX moved 通知 → 快捷键兜底，属预期行为
- 窗口拖拽中按钮状态轮询为 30Hz 定时器，CPU 占用可忽略（仅在拖拽期间运行）