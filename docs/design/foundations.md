# 基元（Foundations）

所有令牌定义于 `Sources/WTidy/UI/DesignSystem.swift` 的 `Design` 命名空间。本文档的表格与代码一一对应；改值必须两边同步。

## 1. 色彩

### 1.1 应用界面（随系统外观）

设置窗口、引导窗口、菜单栏等应用界面**只允许**使用下列系统语义色，禁止自调灰值：

| 语义色 | 用途 |
|---|---|
| `labelColor` | 默认前景（由控件默认提供） |
| `secondaryLabelColor` | 说明文字、次要详情、菜单状态行详情 |
| `tertiaryLabelColor` | 列表行的作用域角标 |
| `separatorColor` | 分隔线、画布/预览/背景井的边框 |
| `controlAccentColor` | 品牌强调（引导徽标、步骤圆号、关于图标） |
| `quaternaryLabelColor` | 衍生表面色（见 1.4） |
| `systemGreen / systemYellow` | 状态语义：正常 / 缺权限 |

### 1.2 Overlay 固定色板（不随外观）

图标条是压在任意壁纸上的浮层，配色固定。定义于 `Design.Color`：

| 令牌 | 值 | 用途 |
|---|---|---|
| `stripWallpaperVeil` | black @ 0.25 | 图标壁纸底的压暗蒙板（够轻，与主题深底拉开差距） |
| `iconNameBandFill` | black @ 0.55 | 图标内名称标注带 |
| `zoneHoverShadow` | black @ 0.45 | 选中分区预览的黑外衬 |
| `zoneHoverLine` | white @ 0.98 | 选中分区预览的白线 |
| `zoneIdleShadow` | black @ 0.22 | 未选中分区的黑外衬 |
| `zoneIdleLine` | white @ 0.45 | 未选中分区的暗白线 |
| `gridLineDark` | white @ 0.28 | `.dark` 图标网格线 |
| `gridLineLight` | white @ 0.40 | `.light` 图标网格线（编辑器画布共用） |
| `cellInkFill` | RGB(0.09, 0.14, 0.23) @ 0.94 | `.light` 图标区域块填充（深墨蓝） |
| `cellAccentStroke` | RGB(0.38, 0.68, 0.95) @ 0.85 | `.light` 图标区域块描边（亮蓝） |
| `focusLine` | white @ 0.95 | 焦点描边（画布选中区域、图标悬停外框）；`nameBandText` 同值别名，兼作图标名称标注文字色 |
| `iconBorderDarkIdle` | white @ 0.70 | `.dark` 图标未悬停外框 |
| `iconBorderLightIdle` | white @ 0.55 | `.light` 图标未悬停外框 |

### 1.3 浅色壁纸色带（唯一渐变）

「银蓝壁纸」是 `.light` 图标底、定位页迷你屏、编辑器画布的共同底色，全应用**只有这一份定义**（`Design.Color.wallpaperRamp`，deviceRGB）：

| stop | RGB | 位置 |
|---|---|---|
| 顶 | (0.80, 0.87, 0.95) | 0 |
| 中 | (0.52, 0.67, 0.86) | 0.55 |
| 底 | (0.34, 0.50, 0.76) | 1 |

「预览即真实」原则：迷你屏与画布必须用这条三 stop 色带（不是取两端的二 stop 近似），保证与图标缩略图观感一致。

行为页「背景」井预览与图标条铺法一致（预览即真实）：默认背景 = 图标主题深底（`StripTheme.at(Prefs.stripTheme).bgColors`），桌面壁纸 = 壁纸整图缩放 + `stripWallpaperVeil` 蒙板。

### 1.4 衍生表面色（语义色 + alpha）

| 令牌 | 值 | 用途 |
|---|---|---|
| `cardFill` | quaternaryLabelColor @ 0.12 | 引导窗步骤卡底色 |
| `badgeFill` | quaternaryLabelColor @ 0.25 | 快捷键徽章底色 |
| `menuMiniFill` | controlAccentColor @ 0.8 | 菜单「应用布局」迷你预览块 |

### 1.5 图标条配色主题（`StripTheme`，用户可选）

行为页「图标条配色」四选一（`Prefs.stripTheme`：0 墨蓝 / 1 石墨 / 2 青碧 / 3 紫罗兰）。每套主题五个槽位：

| 槽位 | 语义 |
|---|---|
| `bgColors: [NSColor]`（2 个） | 图标底渐变（视觉顶→底） |
| `cellFill` | 区域块常规填充（投影选中时其余块压暗至 40%） |
| `cellStroke` | 区域块描边（white @ 0.30，四套共享） |
| `activeCellFill` | 投影命中区域块的高亮填充（近白） |
| `activeCellStroke` | 投影命中区域块的强调描边 |

具体值见 `DesignSystem.swift`。新增主题 = 新增枚举值 + 五槽位 + `Prefs.stripTheme` 上限同步。

## 2. 字体排印

系统字体（SF Pro），尺寸阶梯如下；`Design.Font` 中各取一名：

| 字号 | 权重 | 令牌 | 用途 |
|---|---|---|---|
| 26 | bold | `heroTitle` | 引导窗主标题 |
| 20 | bold | `dialogTitle` | 关于页标题 |
| 14 | semibold | `listTitle` | 布局列表行主标题 |
| 13 | semibold | `sectionTitle` | 小节标题（分组框标题在外） |
| 13 | regular | `tab` | 设置 tab 标签 |
| 13 | semibold | `menuDot` | 菜单状态行圆点 |
| 13 | menuFont | `menuTitle` | 菜单状态行正文（菜单字体） |
| 12 | regular | `body` | 正文标签、列表行描述 |
| 12 | medium | `bodyEmphasis` | 正文强调（授权状态） |
| 13 | medium | `stepTitle` | 引导步骤标题 |
| 11 | menuFont | `menuDetail` | 菜单状态行详情 |
| 11 | regular | `hint` | 次要提示、作用域角标、引导步骤详情 |
| 10 | regular | `caption` | 说明文字（灰色小字） |
| 10 | mono | `monoSmall` | 日志路径 |
| 11 | mono | `monoBadge` | 快捷键徽章 |
| 12 | mono | `monoField` | 网格密度数字输入框 |
| 9 | medium | `iconName` | 图标条上的布局名称标注 |

颜色配套规则：`caption`/`hint` 级别配 `secondaryLabelColor` 或 `tertiaryLabelColor`；其余默认 label 色。

## 3. 圆角（`Design.Radius`）

| 值 | 令牌 | 用途 |
|---|---|---|
| 2 | `menuMini` | 菜单迷你预览块 |
| 4 | `cell` | 图标/画布内的区域块 |
| 4 | `insetFrame` | 背景井、画布、预览的 CALayer 圆角 |
| 5 | `badge` | 快捷键徽章 |
| 6 | `nameBand` | 图标名称标注带 |
| 8 | `icon` | 布局图标外框 |
| 10 | `zone` | 整屏分区预览矩形 |
| 4 | `screenFrame` | 定位页迷你屏外框（真实屏圆角按预览缩放比例仅 ~3pt，10pt 明显过大） |
| 12 | `onboardingCard` | 引导步骤卡 |

## 4. 间距（`Design.Spacing`）

| 令牌 | 值 | 用途 |
|---|---|---|
| `pageInsets` | (18, 24, 18, 24) | 设置页/编辑器页面栈边距（上/左/下/右） |
| `groupInsets` | (10, 14, 10, 14) | 分组框内边距 |
| `cardInsets` | (16, 16, 16, 16) | 引导步骤卡内边距 |
| `onboardingInsets` | (24, 24, 24, 24) | 引导页边距 |
| `stackGap` | 10 | 页面栈小节间距 |
| `groupGap` | 8 | 分组框内行距、行内控件间距 |
| `cardGap` | 16 | 卡片内行距、引导页节距 |
| `headerGap` | 6 | 头部（图标/标题/副标题）行距 |
| `cellInsetDark` | 1.5 | `.dark` 图标区域块内缩（贴满图标，拖拽条语义；图标 52–87pt 高，固定值占比 ≤3%）；编辑器画布区域块同用（贴满便于精确编辑） |
| `cellInsetLight` | 3 | `.light` 区域块内缩目标值（84pt 参考高度）；**随图标高度按 7% 比例收缩**：`min(3, h×0.07)`——绝对内缩在小图标（定位页预览约 28pt 高）上会吃掉 40%+ 高度 |
| `barInset` | 24 | 窗口底栏控件左右边距（与 pageInsets 左值一致；底栏勾选框左缘、完成按钮右缘均按此定位） |
| `nameBandHeight` | 15 | 图标名称标注带高度 |

图标条自身的尺寸/间距不属于本表，集中在 `OverlayMetrics`（`OverlayView.swift`），是几何规范而非视觉令牌。

## 5. 描边宽度

| 值 | 用途 |
|---|---|
| 0.5 | 图标网格线 |
| 1 | 常规外框、区域块描边、CALayer 边框 |
| 1.5 | 未选中分区白线 |
| 2 | 图标悬停外框、未选中分区黑外衬、画布选中区域 |
| 2.5 | 画布选中区域（区别于图标悬停的 2） |
| 3 | 选中分区白线 |
| 4 | 选中分区黑外衬 |

## 6. 动效（`Design.Motion`）

| 令牌 | 值 | 用途 |
|---|---|---|
| `frameInterval` | 0.016s | 吸附动画帧步进 |
| `sameScreenSteps` | 10 | 同屏插值步数 |
| `crossScreenSteps` | 8 | 跨屏每阶段步数 |
| `crossScreenResizeHold` | 0.03s | 跨屏第二阶段（原地调尺寸）停留 |
| `attractPulseInterval` | 0.6s | 缺权限时菜单图标闪烁周期 |

缓动统一为 **smoothstep** `t²(3−2t)`（`WindowAnimator`）。不使用其他缓动曲线。

## 7. 图标与符号

- 只用 SF Symbols（`NSImage(systemSymbolName:)`），品牌主符号 `rectangle.split.2x2`。
- 需要着色时用 `contentTintColor`（强调色/状态色），菜单栏三态图标中着色版用 `sourceAtop` 叠染；不着色时必须 `isTemplate = true`。
- 尺寸用 `NSImage.SymbolConfiguration(pointSize:weight:)`：引导徽标 44/light、关于徽标 48/light、步骤圆号 20/semibold。
