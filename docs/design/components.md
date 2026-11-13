# 组件与页面（Components）

> 令牌（`Design.*`）见 [foundations.md](foundations.md)。每节末尾标注实现位置。

## 1. 拖拽 Overlay

**窗口规则**（`Overlay/OverlayWindow.swift`）：`.borderless` NSPanel，透明、`ignoresMouseEvents = true`、`.floating` 层级、`canJoinAllSpaces`——纯视觉层，绝不拦截系统拖拽。

**两段式交互**（对齐原版）：
1. 拖动窗口 → 仅出现紧凑布局图标条（几何由 `StripGeometry.iconRects` 计算，方向/位置/宽度来自「定位」页）。
2. 光标在图标条内瞄准：图标内相对位置投影到布局区域（`SnapEngine.zoneIndexInIcon`），命中的区域块点亮；选中布局后整屏出现落点预览。
3. 松手在图标上=吸投影区域；屏内分区上=吸该分区；其余=不打扰。

**图标条本体不铺底**（`OverlayView.drawStrip`）：整条无边框、无背景色——「背景」设置作用于每个布局图标自身：
- 默认背景：图标铺主题 `bgColors` 渐变；
- 桌面壁纸：图标铺本屏壁纸（整图缩放 + `stripWallpaperVeil` 蒙板，按屏幕+壁纸路径缓存，换壁纸自动失效）。

**整屏分区预览**（`OverlayView.draw`）：**纯边框语言，不填充**。
- 选中分区：黑外衬 4pt（`zoneHoverShadow`）+ 白线 3pt（`zoneHoverLine`），圆角 `zone`，内缩 3/2pt 双层矩形；
- 未选中分区：黑外衬 2pt（`zoneIdleShadow`）+ 暗白线 1.5pt（`zoneIdleLine`）。

实现：`Sources/WTidy/Overlay/OverlayView.swift`、`OverlayWindow.swift`、`OverlayController.swift`；几何 `Core/StripGeometry.swift`。

## 2. 布局图标（`LayoutIconRenderer`）

全应用唯一的布局图标绘制器（拖拽条 / 定位页预览 / 编辑器缩略图 / 列表缩略图共用）。两种风格：

| 槽位 | `.dark`（拖拽条/快速面板） | `.light`（设置缩略图/迷你屏/画布） |
|---|---|---|
| 底色 | 主题 `bgColors` 渐变；图标条选「使用桌面壁纸」时整图缩放铺本屏壁纸 + `stripWallpaperVeil` 蒙板 | `wallpaperRamp` 三 stop 渐变 |
| 网格线 | `gridLineDark`，0.5pt | `gridLineLight`，0.5pt |
| 区域块常规 | 主题 `cellFill` + `cellStroke`，内缩 `cellInsetDark` 1.5pt（贴满图标） | `cellInkFill` + `cellAccentStroke`，内缩 `min(cellInsetLight, 高度×7%)`（壁纸底带必须可见，且随图标尺寸等比收缩） |
| 区域块命中 | `activeCellFill` + `activeCellStroke`，其余块压暗至 40% alpha | —（投影瞄准只在拖拽条） |

> `.light` 的内缩是硬性验收项，且必须**双向**满足：① 大图标上 ≥3pt（84pt 参考高度）——rows=1 的布局区域块近乎满高，内缩过小会把壁纸底盖死，缩略图退化成「白底深块」（断言 `thumbnailsShowWallpaperRamp`；6pt 曾被用户嫌边距过宽，定稿 3pt）；② 小图标上按高度 7% 收缩——定位页预览图标仅 ~28pt 高，绝对内缩会让区域块「漂浮」在卡片中央、rows=1 布局全部变形（断言 `thumbnailsScaleCellsToSize`）。布局编辑器画布不在此列——它是编辑工具，区域块贴满便于精确编辑。

**外框**：圆角 `icon`；悬停 = `focusLine` 2pt，未悬停 = `iconBorderDarkIdle`/`iconBorderLightIdle` 1pt。悬停不加蒙板——内部点亮由 `activeRegion` 负责。

**名称标注**（`Prefs.showLayoutNames`）：底部 `Spacing.nameBandHeight`（15pt）高横带，`iconNameBandFill`，圆角 `nameBand`，文字 `Font.iconName` + `Color.nameBandText`（white@0.95）。

实现：`Sources/WTidy/Overlay/OverlayView.swift`。

## 3. 设置窗口（`UI/SettingsWindow.swift`）

**窗口骨架**：720×760 固定尺寸，`.titled + .closable`，**每次 `present()` 都 `center()` 屏幕居中**（创建于 (0,0) 不居中会落在主屏左下角；引导窗与布局编辑器同理居中）；`NSTabView` 用 **frame + autoresizingMask 零约束** 贴满内容区（血泪教训：根视图无尺寸约束必塌陷）；底部 46pt 原版式底栏（自启勾选 + 分隔线 + 「完成」按钮），**底栏控件左右边距 = `barInset` 24pt**（与 pageInsets 同值，对齐页面卡片；旧值 16 是规范外魔法数），tab 容器占底栏以上区域。

**页面骨架**（`makePage()`）：每页 = NSScrollView 包垂直 `PageStackView`。两条硬规则：
1. **文档视图必须翻转**：本环境 NSStackView 实测 `isFlipped = false`，非翻转文档视图内容短于视口时被 NSClipView 底对齐——整页下沉、顶部空白 137pt（2026-11-13 实测翻车；`PageStackView` 覆写 `isFlipped = true` 修复）。注意 NSClipView 的方向跟随文档视图。
2. **元素与内容列同宽**：内容列宽 = 628（页面 676 − pageInsets 左右 48）。布局列表、表列、按钮行、分组框一律用此常量（`columnWidth`），禁止 660 等超宽硬编码——「恢复内置布局」曾被顶出右缘。窗口固定 720 不可缩放，用常量 + 冒烟断言保护；跨视图约束需在视图入树后激活（否则 NSGenericException），故不取「相对栈宽」方案。

栈 `alignment = .leading`，边距 `Spacing.pageInsets`，节距 `Spacing.stackGap`。小节结构固定为：**小节标题（`Text.sectionTitle`）→ 分组框 / 控件 → 说明文字（`Text.caption`）**。

**分组框**（`groupBox(_:)`）：标题在外的小节标题 + `NSBox(.primary)` 圆角框，内部垂直栈行距 `groupGap`、边距 `groupInsets`。

**说明文字**：`Text.caption`（`CaptionField`，见 §7）——10pt、`secondaryLabelColor`、最多 2 行换行；**必须限宽在内容列内**（`Text.capped`：页面级 ≤628、分组框内 ≤600、编辑器 ≤512），并用 `wrapWidth` 让两行高度计算正确——英文翻译比中文长，放任固有宽度会溢出窗口被裁断（2026-11-13 实测）。

**布局页**：布局列表 NSTableView（行高 108（`rowHeight` 常量：容四区域 4×24pt 录制钮；96 配 22pt 钮偏矮）、拖拽排序、双击编辑）+ 左下 ＋/− 圆角小按钮 + 右侧「恢复内置布局」。**列表高度吃掉页面剩余（≥420 下限）**：本页独用 `.fill` 分布 + 栈高 ≥ 视口（优先级 900）+ 列表垂直拥抱 200（全页最低），底部无大空白；行多时列表内部滚动，页面不溢出。列表行结构：缩略图 150×84（共用渲染器 `.light`，行内垂直居中）→ 名称 `listTitle` → 描述 `body` → 作用域 `hint`+tertiary → 右侧快捷键纵列（每区域一行「区域 N」角标 + 录制钮 + ✕ 清除钮；按下直接吸到该区域，跳过投影选区。**角标钉宽 44、纵列右缘留 16pt、✕ 钉死 16×16 并关 translates**——列几何恒定，按钮跨行/跨布局同一条竖线，✕ 紧贴按钮 6pt 不悬空（不钉约束时 NSStackView fittingSize 只按图像 intrinsic 计 ~3pt，列宽错、✕ 悬空 13pt）；右缘 12pt 会贴 overlay 滚动条。布局级快捷键已删——2026-11-13 用户定案只要区域级）。

**快捷键录制**（只在列表行内按区域录制，编辑器不设——一处配置、冲突一目了然；`HotkeyRecorderButton` + 行尾 `HotkeyClearButton`，`makeShortcutRecorder`/`makeClearButton` 统一接线）：**标题一律由状态派生**（录制中「输入快捷键…」/ 未录占位「录制」/ 已录回显组合文本）——禁止用 previousTitle 之类回填（视图离树触发 `viewDidMoveToWindow(nil)` 会把标题抹空 → 空白灰钮，2026-11-13 用户截图定位）；且 init 里的属性赋值不触发 didSet（Swift 观察者不跑于初始化期，实测），构造后必须显式 `syncTitle()`。点击进入录制态（强调色 bezel 高亮）；含修饰键组合即录；Esc 取消；清除两条路：行尾 ✕（未录制**淡出禁点但占位**——不用 isHidden 折叠，折叠会让已录制行比未录制行宽 22pt 致跨行不对齐；悬停强调色）或录制中按 ⌫/⌦；无修饰键按键即时短提示「需修饰键」。录制完成先过 `HotkeyManager.conflictOwner` 冲突校验（固定动作 + 区域级，豁免精确同位），冲突弹窗指名占用者并保留原组合。

**行为页**：三组分组框（行为 / 图标条配色 / 背景）。拖拽分屏、全局快捷键、吸附动画为常开行为，不设开关（对齐原版，2026-11-13 删除「窗口调整」组）。配色主题四单选；背景组含 220×124 预览井（图标主题深底或壁纸+蒙板，铺法与图标条一致）+ 两按钮。缺权限时页首追加黄色警告行（`systemYellow` 图标 + `body` 文字 + 「去授权」按钮）。

**定位页**：排列方向单选 → 迷你屏预览（`screenFrame` 圆角 + `wallpaperRamp` + `.light` 图标，「预览即真实」）+ 联动滑块（横排只留纵向滑块，纵排只留横向滑块）→ 尺寸字段行 → 窗口间隙分段控件。滑杆必须显式高度约束（防溢出遮挡）。

**关于页**：居中栈——品牌符号 48/light → 标题 `dialogTitle` → 说明 `hint` → 日志路径 `monoSmall`+secondary → 「打开日志」按钮。

实现：`Sources/WTidy/UI/SettingsWindow.swift`。

## 4. 布局编辑器（`LayoutEditorWindowController` + `LayoutGridCanvasView`）

- 560×740 弹窗，页面栈边距与设置页一致（`pageInsets`）；**内容列宽 512**（`columnWidth` = 560 − pageInsets 左右 48，与设置页「元素与内容列同宽」同一硬规则）：说明文字限宽换行、画布（512×320，16:10 与真实屏等比）、取消/保存行（512，取消居左、保存贴列右缘，默认键 ⏎）一律按它对齐。字段行 = `Text.bodyLabel` 标签 + 控件，行距 `groupGap`；小节间距 `stackGap`，画布与删除钮行贴 `groupGap`。内容装滚动容器（`PageStackView` 翻转文档视图），超高内容滚动不溢出。快捷键不在编辑器设——统一在布局列表行内按区域录制。
- **说明文字**：`Text.caption` + `Text.capped(…, width: 512)`——英文翻译比中文长（~557pt > 512），未限宽会满窗溢出并连带挤歪取消/保存行（2026-11-13 用户截图两处红框同根因）；caption 必须走 `CaptionField`（§7：simple label 单行钉宽在本机压不住）。
- **网格画布**：`wallpaperRamp` 三 stop 底 + `gridLineLight` 网格 + 区域块（`cellInkFill`/`cellAccentStroke`，圆角 `cell`，内缩 1.5pt）——与图标 `.light` 风格同源。选中 = `focusLine` 2.5pt。交互：空白拖=画、点住拖=移、画错点删。
- **预览**：共用渲染器缩略图，CALayer 边框 `separatorColor` + 圆角 `insetFrame`。
- 控制器必须静态持有到窗口关闭（`isReleasedWhenClosed = false`，防提前释放）。

实现：`Sources/WTidy/UI/SettingsWindow.swift`。

## 5. 引导窗口（`UI/Onboarding.swift`）

- 560×430，居中栈：头部（符号 44/light + `heroTitle` + `body` 副标题，行距 `headerGap`）→ 步骤卡（圆角 `onboardingCard`、底 `cardFill`、边距 `cardInsets`、行距 `cardGap`）→ 完成按钮（`controlSize = .large`，授权完成前禁用）→ 提示文字 `hint`。（宽 560 而非 500：英文授权按钮与步骤文案实测需 440pt 行宽，500 会挤爆步骤行。）
- 步骤行：圆号符号（强调色）+ 标题 `stepTitle` + 详情 `hint`+secondary，两行等宽；卡内 trailing 控件右对齐。
- 授权轮询 1s（功能性刷新，非动效令牌）。

实现：`Sources/WTidy/UI/Onboarding.swift`。

## 6. 菜单栏状态项（`UI/StatusMenuController.swift`）

- 双态：🟢 正常（template 主符号）/ ⚠️ 缺权限（`systemYellow` 叹号 + 0.6s attract 脉冲，授权后自停）。无「暂停」态——拖拽分屏与全局快捷键为常开行为，不设开关。
- 状态行富文本：`menuDot` 圆点 + `menuTitle` 正文 + `menuDetail` 详情（`secondaryLabelColor`），详情位显示最近吸附。
- 「应用布局」子菜单每项带 36×20 迷你预览（`menuMiniFill` 块，圆角 `menuMini`）；语言/外观子菜单为应用级偏好（`AppearancePrefs`）。

实现：`Sources/WTidy/UI/StatusMenuController.swift`。

## 7. 通用文本助手（`Design.Text`）

| 助手 | 产出 |
|---|---|
| `sectionTitle(_:)` | 小节标题：`Font.sectionTitle`，默认 label 色 |
| `bodyLabel(_:)` | 正文标签：`Font.body` |
| `caption(_:wrapWidth:)` | 说明文字：`CaptionField`——`Font.caption` + `secondaryLabelColor` + 2 行换行 |
| `capped(_:width:)` | 限宽 ≤ 内容列（等宽约束 + 拔 autoresizing 宽度钉）；设置页 `columnCapped` 是其包装 |

设置窗口与布局编辑器**必须共用**这些助手，不得各自再造私有版本。

**`CaptionField`（caption 专用字段）**：macOS 26/27 的 NSTextField 内嵌 `NSTextFieldSimpleLabel` 渲染视图，单行钉宽（`width == 单行固有宽` 必需 autoresizing 约束，`translatesAutoresizingMaskIntoConstraints=false` 对其无效）+ intrinsic 恒报单行高——普通 label 的「限宽 + 2 行换行」在本机根本不成立：宽度与列宽约束打架时求解器任意破约（实测长文案 631pt 越过 628 列宽、编辑器说明横穿窗口），高度恒单行导致第二行被裁。对策三件套：cell 配 `wraps=true`；每次布局拔内嵌宽度钉（AppKit 会重挂，随 `layout()` 自愈）；换行 intrinsic 按列宽向 cell 求 fitted 尺寸自算，并钳制 `setFrameSize`（自绘层会绕过约束直接按 fitted 尺寸 + 内嵌 padding 赋 frame）。

## 8. 动效与窗口动画（`Core/WindowAnimator.swift`）

吸附动画参数全部取自 `Design.Motion`：同屏 smoothstep 插值 10 步；跨屏三阶段（移到目标屏原点→原地调尺寸 0.03s→移到最终位置）各 8 步；后台队列分步 AX 写入，不阻塞主线程。
