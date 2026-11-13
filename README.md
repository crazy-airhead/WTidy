# WTidy

原生重制的 macOS 窗口分屏工具，致敬 [Window Tidy](https://apps.apple.com/app/window-tidy/id449515544)（Light Pillar, 2011–2017）。

**English / 中文**：界面跟随系统语言自动切换（简体中文 / English）。

## License / 开源协议

[Apache License 2.0](LICENSE)

原版是 2017 年的 x86_64 应用：登录自启在 macOS 26/27 的 BTM 下早已失效，拖拽监听在睡眠唤醒 / 显示器插拔后会静默失灵且无法自愈，还依赖正在被淘汰的 Rosetta 2。WTidy 用 Swift + AppKit 原生重写，专治这三个病根。

## 功能

### 拖拽分屏（招牌交互，还原原版）

1. 按住任意窗口的标题栏拖动，屏幕上浮现**紧凑布局图标条**（位置/方向/最大宽度可调）
2. **瞄准在图标条内完成**：图标内的相对位置投影到布局区域——比如「左右半屏」图标偏左=左半、偏右=右半，单图标即可选区，鼠标行程最短
3. 悬停图标后整屏显示落点预览；松手在图标上即吸附；也可移入屏内精确选区
4. 其他位置松手 = 正常拖拽，不打扰

### 布局自定义（原版 Layouts）

设置「布局」页：内置 8 种布局，支持新增/删除/排序/恢复；编辑器采用原版的**网格 + 区域**模型（如 6×6 网格区域 `(2,2)-(5,5)` = 居中），实时预览缩略图，支持**作用域**（所有屏幕 / 仅指定显示器，对齐原版 "All Screens"）。

### 菜单栏（原版 Apply Layout 菜单）

- **应用布局到前台窗口**：子菜单列出全部布局（带迷你预览图），区域按窗口中心位置投影选择
- **恢复所有窗口位置**：一键还原本会话内吸附过的全部窗口
- **发送窗口到另一块屏幕（前台窗口发往它不在的那块屏；多屏时以鼠标所在屏为目标）**：前台窗口移到光标所在屏（保持相对位置）
- 最近吸附记录（菜单状态行实时显示）

### 吸附动画（原版 AnimateWindows）

窗口吸附带平滑动画；**跨屏吸附自动分三阶段**（移到目标屏原点留出空间 → 调整尺寸 → 移到最终位置），避免大窗口跨屏时被裁剪。可在「行为」页关闭。

### 自动分组（原版 AutoGroupLayouts）

相邻的同网格互补布局自动合并为一个图标（图标内投影选区），可在「行为」页关闭。

### 设置页（对齐原版四页）

- **布局**：布局列表管理 + 编辑器；每区域快捷键在列表行内直接录制（按下直接吸附到该区域，冲突自动拦截）
- **行为**：⌥ 键隐藏/显示图标条、状态图标显隐、图标名称标注、尺寸失败警告、图标条背景（默认深色/桌面壁纸）、吸附动画、自动分组、开机自启
- **定位**：图标条横/纵排列、屏幕位置（可视化预览 + 滑块）、最大宽度、屏幕边距、窗口间隙

### 全局快捷键（兜底）

| 动作 | 快捷键 | 动作 | 快捷键 |
|---|---|---|---|
| 左 / 右半屏 | `⌥⌘←` / `⌥⌘→` | 左 / 中 / 右 1/3 | `⌥⌘[` / `⌥⌘\` / `⌥⌘]` |
| 上 / 下半屏 | `⌃⌥⌘↑` / `⌃⌥⌘↓` | 左 / 右 2/3 | `⌃⌥⌘[` / `⌃⌥⌘]` |
| 最大化 | `⌃⌥⌘F` | 居中（保持尺寸） | `⌃⌥⌘C` |

快捷键作用于最前面的窗口；个别不发拖拽通知的应用（部分 Java/Electron）正好被它覆盖。

### 可靠性（与原版的核心差异）

- **看门狗自愈**：切换前台应用、屏幕唤醒、显示器插拔、Space 切换时事件驱动重挂监听；每 10 秒心跳校验；每 60 秒无条件重建监听链
- **状态可见**：菜单栏图标双态（🟢 正常 / ⚠️ 缺权限闪烁提醒），菜单实时显示「最近吸附」，静默失效从此看得见
- **现代登录项**：SMAppService（BTM 原生），开机自启稳定
- **全程日志**：`~/Library/Logs/WTidy.log`（512KB 自动轮转），出问题可追溯
- **arm64 原生**：不依赖 Rosetta 2

## 首次使用

1. 构建：`scripts/build-app.sh --install`（装入 `/Applications` 并启动）
2. 首次启动会弹出引导：在 **系统设置 → 隐私与安全性 → 辅助功能** 中给 WTidy 授权
3. 授权后引导页自动打勾，点「开始使用」即可

> 与 macOS 15+ 自带的「窗口拖到屏幕边缘磁贴」可共存：WTidy 由顶部布局条触发，原生磁贴由屏幕边缘触发。若嫌冲突，可在 系统设置 → 桌面与程序坞 中关闭「将窗口拖到屏幕边缘时平铺」。

## 构建与开发

仅需 Command Line Tools（无需 Xcode）：

```bash
swift build -c Release          # 编译
scripts/build-app.sh            # 组装 + ad-hoc 签名 → build/WTidy.app
scripts/build-app.sh --install  # 安装到 /Applications 并启动
```

运行测试（CLT 的 Testing 宏插件在子目录，需显式指定路径）：

```bash
swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```

技术要点：AX observer 挂 `kCFRunLoopCommonModes`（否则窗口拖拽期间收不到通知——原版的坑）；拖拽期间用 `CGEventSource.buttonState` 轮询判定松手；设置/引导界面为纯 AppKit（CLT 无 SwiftUI 宏插件）。

## 目录结构

```
Sources/WTidy/
├── main.swift / AppDelegate.swift     # 入口与装配（含看门狗）
├── Core/          # SnapEngine 几何 / AXWindow 封装 / AX 监听服务 / 拖拽状态机
├── Overlay/       # 两段式拖拽 UI（布局条 + 分区高亮）
├── Hotkeys/       # Carbon 全局快捷键
├── UI/            # 菜单栏状态 / 引导 / 设置 / 设计令牌（DesignSystem.swift）
└── Support/       # 偏好 / 日志 / SMAppService 登录项
Tests/WTidyTests/  # 几何与映射的 swift-testing 测试
docs/design/       # 设计语言规范（改 UI 先查这里）
```

## License

[Apache License 2.0](LICENSE)。向 Window Tidy 的开发者 [Light Pillar](https://lightpillar.com) 致敬。
