# 规范符合性核对记录

首次全面核对：2026-11-12（规范建立日）。核对范围：`Sources/WTidy/UI/`、`Sources/WTidy/Overlay/`、`Core/WindowAnimator.swift`（动效）。核对基准：[foundations.md](foundations.md) + [components.md](components.md)。本次核对后全部 UI 视觉值已收敛至 `Design` 令牌，验证：`swift build` 通过、`swift test` 25/25 通过。

## 一、核对结论

| 文件 | 结论 | 处理 |
|---|---|---|
| `Overlay/OverlayView.swift` | 部分不符 | 令牌化；`StripTheme` 迁出至 `DesignSystem.swift` |
| `Core/WindowAnimator.swift` | 部分不符 | 动效参数令牌化（`Design.Motion`） |
| `UI/SettingsWindow.swift` | 部分不符 | 去重文本助手、令牌化、修控件重复、补本地化 |
| `UI/Onboarding.swift` | 部分不符 | 令牌化、补本地化 |
| `UI/StatusMenuController.swift` | 部分不符 | 令牌化 |
| `Overlay/OverlayController.swift` | 部分不符 | 状态描述文案补 `LF()` |
| `Overlay/OverlayWindow.swift` | 符合 | —（无视觉值；`isReleasedWhenClosed=false` 已合规） |
| `Core/StripGeometry.swift` | 符合 | —（几何规范本体，非视觉令牌） |

## 二、令牌收敛（违背「值只定义一次」的重复项）

| 视觉值 | 原散落位置 | 收敛后 |
|---|---|---|
| 浅色壁纸色带 | `LayoutIconRenderer`（3 stop）、`ScreenPositionPreviewView` 与 `LayoutGridCanvasView`（各一份 2 stop 近似） | `Design.Color.wallpaperRamp` 唯一定义；迷你屏与画布改用同一 3 stop 渐变（预览即真实，观感与缩略图一致） |
| `.light` 区域块填充 | 渲染器 α0.94 / 画布 α0.92 | `cellInkFill`（取 0.94，两者本就肉眼不可辨） |
| `.light` 区域块描边 | 渲染器与画布各一份 `(0.38,0.68,0.95)` | `cellAccentStroke` |
| 网格线 alpha | 渲染器 0.40 / 画布 0.35 | `gridLineLight` 0.40 |
| 小节标题 / 说明文字 / 正文标签助手 | `SettingsWindowController` 与 `LayoutEditorWindowController` 各持私有 `sectionTitle`/`sectionCaption`/`captionText`/`label` | 删除四处私有版本，统一走 `Design.Text.sectionTitle/bodyLabel/caption` |
| 页面栈边距 | 设置页 (18,24) / 编辑器 (18,22) | `Spacing.pageInsets`（18,24，编辑器左右各 +2pt，宽预算 528 < 560 校验通过） |
| 引导卡底色 / 徽章底色 | Onboarding α0.12 / keyBadge α0.25 各自内联 | `cardFill` / `badgeFill` |

## 三、缺陷修复

1. **`groupCheck` 控件实例重复挂载（真 bug）**：行为页把同一个「自动分组相邻互补布局」勾选框同时加进「行为」与「窗口调整」两个分组框——`NSStackView.addArrangedSubview` 会把它从第一个框静默移走。已从「窗口调整」框移除，保留在语义正确的「行为」框。
2. **漏本地化的界面文案（违背规范第 6 条）**：编辑器窗口标题 `新增布局` / `编辑布局：\(name)`（键 `编辑布局：%@"` 此前已在 en.lproj 却未被代码引用）、编辑器作用域 `仅 \(屏名)`、关于页 credit、引导窗操作提示、布局列表行描述（三条网格描述）、快捷键路径状态描述（`恢复原位置 · %@` / `居中（保持尺寸） · %@` / `⚠️ 未能完全调整尺寸（偏差 %dpt）— `）。全部改走 `L()`/`LF()`，en.lproj 补 10 个键（`plutil -lint` 通过）。
3. **`dragDidEnd` 与 `updateHover` 的投影换算等非视觉逻辑**未动——仅视觉与文案层核对。

## 四、判定为合规、不改动

- 「简体中文」/「English」在语言子菜单保持原名不翻译——语言名各语言显示自身，是 i18n 惯例而非违规。
- `AppLog` 日志串不本地化（规范明确豁免）。
- `OverlayMetrics` 的图标尺寸/间距：属图标条几何规范（components.md §1），刻意不并入 `Design.Spacing`。
- Overlay 固定色板不随深浅色外观切换：设计原则第 2 条（壁纸浮层刻意固定）。
- 系统语义色（`secondaryLabelColor`、`separatorColor`、`controlAccentColor` 等）的使用：本就合规，无需改动。

## 五、验证

- `swift build -c release`：通过（仅 `AXWindow.swift` 既有告警，与本次无关）。
- `swift test`（CLT testing 插件路径）：**25/25 通过**，含 `SettingsRenderTests.settingsLayoutNumbers` 布局冒烟断言——groupCheck 修复与令牌替换未破坏页面结构。
- 残留扫描（UI/Overlay 目录无内联颜色/字体/圆角；未本地化 CJK 仅剩语言名，合理保留）：

```bash
grep -rn "NSColor(red:" Sources/WTidy/UI Sources/WTidy/Overlay | grep -v DesignSystem
grep -rn "systemFont(ofSize\|menuFont(ofSize\|monospacedSystemFont" Sources/WTidy/UI Sources/WTidy/Overlay | grep -v DesignSystem
grep -rn "xRadius\|cornerRadius" Sources/WTidy/UI Sources/WTidy/Overlay | grep -v "Design.Radius"
```

## 六、后续守则

1. 新增 UI 一律先查 foundations.md 取令牌，禁止内联值。
2. 改观感 = 改令牌 + 同步改 foundations.md 表格（两边 diff 必须成对出现）。
3. 新增主题（`StripTheme`）时同步 `Prefs.stripTheme` 上限与本目录 §1.5。
4. 再做 UI 大改后，按本文件的核对表跑一轮残留扫描（见第五节命令）。

---

## 二次核对：2026-11-13（用户截图驱动）

> ⚠️ **勘误（三次核对时补记）**：本节第 1 条与「遗留判定」第 2 条的结论是**错的**——几何断言公式漏算了 clip 的 `bounds.origin.y`（诊断输出里 `clipView.bounds=(0,137,676,652)`、`stack.isFlipped=false` 本是证据，当时误读为已顶对齐）。顶部空白的真实根因与修复见三次核对。

**触发**：用户发来英文界面下的布局页截图，质疑「这样的页面是有设计规范的？」——顶部大片空白、说明文字与列表描述仍为中文、缩略图呈「白底深块」。

**实证过程**（教训：首次核对只做了数值断言与令牌扫描，未做渲染验收，此为规范盲区）：

1. **几何诊断**（真窗口 + 布局后测 frame）：~~现版代码顶对齐正常~~ → 勘误见上方，实际非翻转文档视图被底对齐。
2. **陈旧包实锤**：截图里英文界面夹中文说明/描述 → 该包的 en.lproj 缺这些键。git 时间线：说明文案代码进于 316f1f1（11-12 22:24），其 en.lproj 键进于 cf036b9（11-13 05:53）；列表描述的 LF 键至今只在本工作树未提交。截图包早于这些修复。
3. **像素普查**：缩略图渐变在现版代码中正常绘制（环带采样为壁纸色带蓝）。但**「白底深块」观感另有真因**：`.light` 区域块内缩仅 1.5pt，rows=1 布局的区域块遮住 96% 底色，壁纸底带不可见——与规范「银蓝壁纸底」不符的真渲染缺陷。
4. **键完整性机检**：L()/LF() 键 vs en.lproj 全量 diff，零缺失（unused 键为已删功能遗留，无碍）。

**修复**：
- `.light` 区域块内缩 1.5 → 6pt（新令牌 `Design.Spacing.cellInsetDark/Light`，components.md §2 增硬性验收项）。拖拽条 `.dark` 贴满语义不变；编辑器画布不受影响（编辑工具，贴满便于精确编辑）。
- 规范补两原则（README §9 视觉验收、§10 本地化完整性）。
- 新增防回归断言并纳入套件：`layoutsPageTopAligned`（页顶对齐）、`thumbnailsShowWallpaperRamp`（底色带可见，含 2x 位图采样换算——NSImage lockFocus 在测试环境产生 Retina 分辨率位图，采样须按 pixelsWide 换算）。

**同期外部修复**（cf036b9，非本次工作树）：内置布局名按稳定 id 实时本地化（修「英文界面显示中文布局名」）、zh-Hans 翻译表补齐、语言名恒显原语言（确认非 bug）。

**验证**：`swift test` 27/27 通过（新增 2 断言）。

**遗留判定**：
- 布局页列表固定 420pt 高、页高约 650pt，顶部对齐后底部余白约 120pt——与 macOS 系统设置页一致的可接受留白，非缺陷。
- ~~旧包顶部空白的准确成因不再深挖（所有已提交版本均顶锚定）~~ → 勘误：现版代码即有顶部空白，见三次核对。

---

## 三次核对：2026-11-13（用户重建后截图，顶对齐 + 右边距两项）

**触发**：用户重建安装后发来深色模式截图：① 顶部仍有大片空白（推翻二次核对第 1 条结论）；② 「恢复内置布局」按钮被顶出右缘。

**根因**：
1. **顶部空白**：本环境 NSStackView 实测 `isFlipped = false`。非翻转文档视图内容短于视口（布局页内容 515pt < 视口 652pt）时，NSClipView 把文档底对齐——内容下沉、顶部空 137pt。二次核对诊断时这两个信号就在输出里，被断言公式的错误（未含 `bounds.origin`）掩盖。
2. **右边距**：页面宽 676 − pageInsets 48 = 内容列 628pt，而布局列表/表列/按钮行/分组框硬编码 660pt，超宽 32pt → 最右元素出缘。

**修复**：
- `PageStackView`（覆写 `isFlipped = true`）作页面文档视图；NSClipView 方向跟随文档视图，断言公式改为方向自适应。
- 内容列宽收敛为常量 `columnWidth = 628`：布局列表、表列（640→628）、＋/−按钮行、四个分组框；定位页横滑杆与迷你屏 600→594（628 − 纵滑杆 24 − 行距 10）。
- 两次弯路如实记录：① 先用「相对栈宽」跨视图约束，视图入树前激活抛 NSGenericException（测试进程崩溃）→ 回退为固定常量（窗口固定尺寸，确定性优先，代价是窗口若改尺寸需同步改常量）；② `perl -pi` 批量改调用点时啃坏一个多行调用 → 手工修复。教训：多行代码不要用单行 perl 改。

**环境事件**：仓库目录 WindowTidy → WTidy 改名，致 `.build` 内绝对路径失效（`swift package reset` 重建）与 shell 持久 cwd 失效（旧路径留占位目录规避，事后可删 `WindowTidy/.cwd-keeper` 整目录）。

**验证**：`swift test` 27/27 通过（含修正公式后的 `layoutsPageTopAligned`、`thumbnailsShowWallpaperRamp`）。

**规范沉淀**：components.md §3 页面骨架新增两条硬规则（文档视图必须翻转 / 元素与内容列 628 同宽）。

---

## 四次核对：2026-11-13（用户要求列表填满页面）

**触发**：顶对齐修复后，用户指出布局页底部仍有大空白，要求列表高度增加。

**修复**：布局页独用 `.fill` 分布 + 栈高 ≥ 视口（优先级 900，内容增长时自然降级为页面滚动）+ 列表垂直拥抱 200（全页最低，余量全进列表，下限 ≥420）。列表从固定 420pt 变为约 557pt（视口 652 − 说明/按钮等 95pt），可见行数 4 → 5+；＋/− 行落至页面底部。其他页不动（行为/定位页内容高于或接近视口，保持滚动语义）。

**防回归**：`layoutsPageTopAligned` 增补列表填充断言（列表高 >500pt）。

**验证**：`swift test` 27/27 通过。

---

## 五次核对：2026-11-13（用户要求：界面不体现原版）

**要求**：界面（用户可见文案）不得出现「原版 / Window Tidy / Light Pillar / 致敬」等内容。代码注释与 docs/ 设计文档不受影响（内部资料，保留取证溯源）。

**清理项**：① 引导窗副标题「原生重制的窗口分屏工具 · 致敬 Window Tidy」→「原生重制的窗口分屏工具」；② 关于页 credit 第二行「重制致敬 Window Tidy（Light Pillar, 2011–2017）」整体移除；③ 定位页窗口间隙说明「贴合为原版 Window Tidy 的行为…」→「贴合为窗口完全贴齐…」；④ Info.plist `NSHumanReadableCopyright`「重制致敬 Window Tidy (Light Pillar)」→「Copyright © 2026 WTidy.」。en.lproj / zh-Hans.lproj 同步换键。

**顺手修复**：删除 cf036b9 引入的两个「字面换行」重复键（.strings 内同一键定义两次，后者覆盖前者，存在解析告警风险）。

**验证**：残留扫描零命中（界面串 + .strings + Info.plist）、`plutil -lint` 全 OK、键完整性零缺失、`swift test` 27/27。


---

## 六次核对：2026-11-13（用户截图：定位页预览区域块变形）

**触发**：用户指出定位页「屏幕位置」预览里的图标条不等比、布局显示明显有问题。

**根因**（两次修复引入的回归 + 一处既有隐患）：
1. **主因——绝对内缩不随尺寸缩放**：四次核对的 6pt 内缩是绝对值，列表缩略图（150×84）占比合理，但定位页预览的图标只有 ~49×28pt（整屏等比缩到 594×340），上下各 6pt 吃掉 43% 高度——区域块「漂浮」在卡片中央，rows=1 布局全部变形。卡片外框本身是等比的，坏的只有区域块。
2. **既有隐患——预览坐标映射漏减 visibleFrame 原点**：`iconRects` 返回全局屏幕坐标，预览直接 `r.minY × k` 会把菜单栏高度（vf.minY≈38pt）一起缩放，条的位置偏高 ~12pt（主屏 vf.maxY≈高度 的巧合下才勉强可用）。

**修复**：
- `.light` 内缩改比例式：`min(cellInsetLight, 高度×7%)`——84pt 时 ≈5.9pt（与原值视觉无差），28pt 时 ≈2pt（等比）。`.dark` 保持固定 1.5pt（拖拽条图标尺寸范围小）。
- 预览映射改为 `(r.min − vf.min) × k`。

**防回归**：新增 `thumbnailsScaleCellsToSize`——60×34 小图标渲染「最大化」布局，区域块纵向覆盖 ≥70%（旧绝对内缩下 ~65%）；`thumbnailsShowWallpaperRamp` 继续守大图标端。两个断言合起来把「双向内缩」钉死。

**验证**：`swift test` 28/28 通过。

**教训沉淀**：components.md §2 内缩规则改为「双向验收」（大图标不露底 / 小图标不漂浮）；foundations.md `cellInsetLight` 标注比例语义。绝对 pt 值用于会缩放的绘图元素时必须换算成比例或 `min(绝对值, 参考比例×尺寸)`。

---

## 七次核对：2026-11-13（用户微调：迷你屏圆角）

**触发**：用户指出定位页迷你屏外框圆角过大。

**修复**：`Design.Radius.screenFrame` 10 → 4pt。依据：迷你屏是真实屏的 ~0.33 倍等比缩放，真实屏的物理圆角折算到预览上只有 ~3pt，10pt 明显失真。圆角表（foundations §3）同步。

**验证**：`swift build -c release` 通过。

---

## 八次核对：2026-11-13（用户微调：缩略图内缩边距）

**触发**：用户指出布局列表缩略图的壁纸底带（区域块内缩）过宽。

**修复**：`cellInsetLight` 目标值 6 → 3pt（比例规则不变：小图标仍 `min(3, 高度×7%)`）。缩略图壁纸带从 6pt 收窄到 3pt，单元格间距（2×内缩）6→3pt。六次核对定 6pt、本次定 3pt——两次都由用户截图定夺，规范只记录结果与双向约束，不再自定审美值。

**测试采样点同步**：左环带采样 (3,42)→(2,42)（3pt 内缩下左带净宽仅 1pt）；顶环带/中缝采样都在中缝列（无区域块），不受内缩影响。

**验证**：`swift build -c release` 通过，`swift test` 28/28 通过。

---

## 九次核对：2026-11-13（用户截图：英文界面残留「左 2/3」「右 2/3」）

**触发**：英文界面下内置布局大部分已翻译，唯「左 2/3」「右 2/3」仍是中文。

**根因**：这两条不是当前内置布局——当前内置表（75ac327 定稿）中它们已合并为 `narrowWide`「左 1/3 + 右 2/3」与 `wideNarrow`「左 2/3 + 右 1/3」；用户存储列表里的这两条（各 2 区域）是历史迭代的残留/改名数据，id 不在当前内置表，按 id 重译的机制（cf036b9）自然够不着。其余 6 条 id 匹配故正常翻译。

**修复**：`LayoutStore.layouts` 读取时做**结构收编迁移**——未知 id 但「结构（cols/rows/排序后 regions）恰好等于某当前内置 + 名称 ∈ 历史内置默认名（左/右 1/3、2/3）∪ 当前内置默认名」的条目，收编为该内置（换 id+名，保留每布局激活快捷键字段）；收编后 id 与既有条目冲突则放弃；名称为自定义的布局永不收编。

**防回归**：`staleBuiltinEntriesCanonicalized`——乱序区域 + 旧名 + 自定义快捷键的陈旧条目收编为 wideNarrow（快捷键保留），同结构的自定义命名布局不受影响。

**验证**：`swift test` 29/29 通过。「恢复内置布局」仍是整表重置的兜底入口（会丢每布局快捷键，迁移则保留）。

---

## 十次核对：2026-11-13（用户截图：底栏 Done 不守边距体系）

**触发**：用户圈出设置窗口底栏「Done」按钮，质疑仍不遵守设计语言。

**根因**：底栏控件用规范外魔法数 16pt 定位——与页面卡片（22..698）、内容列（46..674）都不对齐；九次核对只收编了页面内元素（columnWidth 628），底栏漏网。另：init 内注释仍写着旧窗口尺寸（580/680），编辑器按钮行 490pt 亦是旧几何残留（内容列现为 512）。

**修复**：新令牌 `Design.Spacing.barInset = 24`（与 pageInsets 左值一致）——底栏勾选框左缘、Done 右缘均按 24pt 定位，与页面卡片视觉对齐；编辑器取消/保存行 490 → 512（列宽）；纠正过期注释。

**验证**：`swift test` 29/29 通过。

---

## 十一次核对：2026-11-13（用户截图：英文说明文字溢出窗口被裁断）

**触发**：用户发英文界面布局页截图，右侧出现「空心沟」——说明文字（"Drag to reorder layouts…"）固有宽度 ~700pt+，越过内容列（674）直达窗口边缘被裁断。

**根因**：`Design.Text.caption` 无限宽约束，说明文字按固有宽度布局。中文固有宽度 ~556pt < 628 列宽，从未暴露；**英文翻译更长**——键完整性核查只查「键存在」，没查「更长翻译是否放得下」，i18n 落地时埋雷，英文界面一开就炸。

**修复**：新助手 `columnCapped(_:width:)`——页面级说明文字一律 `widthAnchor ≤ 内容列`（分组框内的按内宽 600）；布局页说明同时设 `preferredMaxLayoutWidth` 使两行换行高度计算正确。防回归：`layoutsPageTopAligned` 增补说明文字宽度 ≤ 628 断言。

**教训沉淀**：本地化完整性 = 键存在 **且** 更长翻译的布局安全（渲染层验收必须覆盖各语言，至少覆盖最长语言）。

**验证**：`swift test` 29/29 通过；`plutil`/键完整性复查通过（并发会话将「默认深色」改为「默认背景」时已同步 .strings，无缺口）。

---

## 十二次核对：2026-11-13（全量复核 + 修复）

**触发**：用户要求全面复核 UI 是否符合设计语言规范，并修复所有发现的问题。

**核对方式**：令牌残留扫描（内联颜色/字体/圆角）+ 逐文件对照 foundations/components + 本地化键完整性机检 + `swift build` / `swift test`。

**发现的真偏差与修复**：
1. **权限警告行位置**：components.md §3 规定「缺权限时页首追加」，代码实际加在行为页最底部。已移到页首（异常状态优先级最高，沉底不可见）。
2. **名称标注带内联值**：文字色 `white@0.95` 与 `focusLine` 同值重复、带高 15pt 两处硬编码。新增 `Color.nameBandText`（= `focusLine` 别名）与 `Spacing.nameBandHeight`（15），foundations §1.2/§4 同步。
3. **编辑器画布内缩 1.5pt 硬编码**：改引 `Spacing.cellInsetDark`（同值，语义即「贴满便于编辑」），foundations §4 标注画布共用。

**文档未跟上代码（已同步）**：
4. 引导窗 500×430 → 560×430（components.md §5；英文布局实测需求，代码注释本有依据）。
5. components.md §5 步骤标题字体笔误 `bodyEmphasis` → `stepTitle`（与 foundations §2 对齐）。
6. 「暂停」三态超前于实现：代码无暂停功能（State 仅 ok/noPermission），components.md §6 改双态、foundations §1.1 移除 `systemGray`；README「状态可见」同步。
7. README 菜单栏「拖拽/快捷键开关」不存在（且与「常开不设开关」矛盾），删除。
8. aboutTab 初始 frame 580×512 为旧窗口尺寸残留 → 696×698（tab 内容区）。

**本地化清理**：
9. en.lproj 删除 12 个废弃键（快速布局面板、「原版蓝」、独立快捷键页等已删功能遗留）。
10. 键完整性补齐：en.lproj 补 12 个符号键（←↑→↓↩⇥⇧⌃⌘⌥＋－，恒等映射），zh-Hans 补 24 键（含全部 LF 格式键）——两表机检零缺口。

**验证**：`plutil -lint` 两表 OK；键完整性机检 en/zh-Hans 均零缺失零冗余；`swift build` 通过；`swift test` 29/29 通过。
