# WTidy 设计语言规范

本目录是 WTidy 视觉与界面语言的唯一权威来源。改任何 UI 代码之前先查这里；改了观感就同步更新这里。规范与代码的关系是**一一映射**：每条规范都能落到 `Sources/WTidy/UI/DesignSystem.swift` 的一个令牌或一条绘制规则上。

## 文档索引

| 文档 | 内容 |
|---|---|
| [foundations.md](foundations.md) | 基元：色彩、字体排印、圆角、间距、描边、动效、图标 |
| [components.md](components.md) | 组件与页面：拖拽 Overlay、布局图标、设置窗口、引导窗口、菜单栏 |
| [audit.md](audit.md) | 规范符合性核对记录（首次核对：2026-11-12） |

## 设计原则

1. **纯 AppKit，系统语义色优先。** 无 SwiftUI（CLT 工具链限制）。设置/引导/菜单等「应用界面」一律使用系统语义色（`labelColor`、`separatorColor`、`controlAccentColor`…），**禁止硬编码 label/背景灰值**，浅色/深色外观自动适配（菜单「外观」子菜单可即时切换）。
2. **Overlay 固定色板是刻意的例外。** 拖拽图标条是「壁纸上的浮层」，其深色系配色（`StripTheme` 四套主题、蒙板）刻意不随系统外观变化，以稳定压住任意桌面壁纸。
3. **对齐原版 Window Tidy 的视觉母题。** 复刻观感而非像素：双风格布局图标（`.dark` 拖拽条 / `.light` 设置页）、图标条内瞄准、整屏分区预览的纯边框语言，都源自原版取证。
4. **预览即真实。** 设置页「定位」预览、布局编辑器画布与拖拽 Overlay 共用同一份几何（`StripGeometry`）、同一个渲染器（`LayoutIconRenderer`）、同一条壁纸色带（`Design.Color.wallpaperRamp`）。预览里看到的就是拖拽时得到的。
5. **令牌只有一个来源。** 颜色、字体、圆角、间距、动效参数只允许在 `DesignSystem.swift` 定义一次；界面代码禁止内联 `NSColor(red:…)`、`systemFont(ofSize:…)`、魔法圆角数字。同一视觉值出现在两处即视为缺陷。
6. **文案全走 `L()`/`LF()`。** 中文串即键（`Support/L10n.swift`），`AppResources/en.lproj/Localizable.strings` 提供英文；含插值的串必须用 `LF()` 与格式占位符，不得 `"前缀\(插值)后缀"` 拼接。`AppLog` 日志不本地化。
7. **反馈克制。** 悬停/选中反馈用边框与内部点亮表达，不加蒙板；Overlay 窗口不拦截鼠标（`ignoresMouseEvents`），不打断系统拖拽。
8. **一个控件实例只挂一个父视图。** 复用同一 NSView/NSButton 到第二个容器会静默从原容器移除——需要同样开关出现在两处时创建两个实例。
9. **视觉验收是规范的一部分。** 数值断言只保结构不保观感：凡是「渲染结果」层面的规范（页顶对齐、底色带可见、图标比例），必须用几何换算 + 位图像素采样断言锁死（见 `SettingsRenderTests.layoutsPageTopAligned` / `thumbnailsShowWallpaperRamp`），或用真窗口截图核对。改观感的 PR 必须附一种。
10. **本地化完整性可机检。** `L()`/`LF()` 包裹只是第一步——键必须存在于 `en.lproj`（和 zh-Hans 表）才算完成，改文案后跑「键完整性脚本」核查（见 audit.md §五）。内置布局等持久化数据名称按稳定 id 在展示时实时本地化，不信任存储值。

## 代码映射

| 关注点 | 位置 |
|---|---|
| 设计令牌（色彩/字体/圆角/间距/动效）与共用文本助手 | `Sources/WTidy/UI/DesignSystem.swift`（`Design` 命名空间 + `StripTheme`） |
| 图标条几何（overlay 与预览共用） | `Sources/WTidy/Core/StripGeometry.swift` |
| 图标尺寸/命中常量 | `Sources/WTidy/Overlay/OverlayView.swift`（`OverlayMetrics`） |
| 布局图标唯一渲染器 | `Sources/WTidy/Overlay/OverlayView.swift`（`LayoutIconRenderer`） |
| 本地化 | `Sources/WTidy/Support/L10n.swift` + `AppResources/en.lproj/Localizable.strings` |
