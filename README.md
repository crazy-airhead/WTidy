# WTidy

原生重制的 macOS 窗口分屏工具，致敬 [Window Tidy](https://apps.apple.com/app/window-tidy/id449515544)（Light Pillar, 2011–2017）。

原版是 2017 年的 x86_64 应用：登录自启在 macOS 26/27 的 BTM 下早已失效，拖拽监听在睡眠唤醒 / 显示器插拔后会静默失灵且无法自愈，还依赖正在被淘汰的 Rosetta 2。WTidy 用 Swift + AppKit 原生重写，专治这三个病根。

## 功能

### 拖拽分屏（招牌交互，还原原版）

1. 按住任意窗口的标题栏拖动，屏幕顶部浮现**布局条**
2. 把窗口悬停在某个布局缩略图上（左右半 / 上下半 / 三等分 / 2/3 / 四分 / 最大化），该布局在整屏展开
3. 悬停到目标分区，松手——窗口吸附到位
4. 在其他位置松手 = 正常拖拽，不打扰

### 全局快捷键（兜底）

| 动作 | 快捷键 | 动作 | 快捷键 |
|---|---|---|---|
| 左 / 右半屏 | `⌥⌘←` / `⌥⌘→` | 左 / 中 / 右 1/3 | `⌥⌘[` / `⌥⌘\` / `⌥⌘]` |
| 上 / 下半屏 | `⌃⌥⌘↑` / `⌃⌥⌘↓` | 左 / 右 2/3 | `⌃⌥⌘[` / `⌃⌥⌘]` |
| 最大化 | `⌃⌥⌘F` | 居中 | `⌃⌥⌘C` |
| 恢复位置 | `⌃⌥⌘Z` | | |

快捷键作用于最前面的窗口；个别不发拖拽通知的应用（部分 Java/Electron）正好被它覆盖。

### 可靠性（与原版的核心差异）

- **看门狗自愈**：切换前台应用、屏幕唤醒、显示器插拔、Space 切换时事件驱动重挂监听；每 10 秒心跳校验；每 60 秒无条件重建监听链
- **状态可见**：菜单栏图标三态（🟢 正常 / ⚠️ 缺权限 / ⚪ 暂停），菜单实时显示「最近吸附」，静默失效从此看得见
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
├── UI/            # 菜单栏状态 / 引导 / 设置
└── Support/       # 偏好 / 日志 / SMAppService 登录项
Tests/WTidyTests/  # 几何与映射的 15 项 swift-testing 测试
```

## License

MIT。向 Window Tidy 的开发者 [Light Pillar](https://lightpillar.com) 致敬。
