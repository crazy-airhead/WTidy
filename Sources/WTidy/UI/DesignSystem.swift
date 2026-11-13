import AppKit

/// WTidy 设计令牌唯一来源（规范：docs/design/）。
/// 颜色、字体、圆角、间距、动效只在此定义一次；
/// 界面代码禁止内联 NSColor(red:…) / systemFont(ofSize:…) / 魔法圆角数字。
/// 改动任何值必须同步更新 docs/design/foundations.md。
enum Design {
    // MARK: - 色彩

    /// 应用界面用系统语义色（随浅色/深色外观自动适配）；
    /// 只有 Overlay 浮层与衍生表面使用下面的固定/半透明色板。
    enum Color {
        // —— Overlay 固定色板（刻意不随系统外观：压在任意壁纸上的浮层）——
        static let stripWallpaperVeil = NSColor.black.withAlphaComponent(0.25)        // 图标壁纸底的压暗蒙板（够轻，与主题深底拉开差距）
        static let iconNameBandFill = NSColor.black.withAlphaComponent(0.55)          // 图标内名称标注带

        // 整屏分区预览：纯边框语言，不填充
        static let zoneHoverShadow = NSColor.black.withAlphaComponent(0.45)           // 选中分区黑外衬
        static let zoneHoverLine = NSColor.white.withAlphaComponent(0.98)             // 选中分区白线
        static let zoneIdleShadow = NSColor.black.withAlphaComponent(0.22)            // 未选中分区黑外衬
        static let zoneIdleLine = NSColor.white.withAlphaComponent(0.45)              // 未选中分区暗白线

        // 布局图标网格与区域块
        static let gridLineDark = NSColor.white.withAlphaComponent(0.28)              // .dark 图标网格线
        static let gridLineLight = NSColor.white.withAlphaComponent(0.40)             // .light 图标网格线（画布共用）
        static let cellInkFill = NSColor(red: 0.09, green: 0.14, blue: 0.23, alpha: 0.94)      // .light 区域块填充
        static let cellAccentStroke = NSColor(red: 0.38, green: 0.68, blue: 0.95, alpha: 0.85) // .light 区域块描边
        static let focusLine = NSColor.white.withAlphaComponent(0.95)                 // 焦点描边（画布选中/图标悬停）
        static let iconBorderDarkIdle = NSColor.white.withAlphaComponent(0.70)        // .dark 图标未悬停外框
        static let iconBorderLightIdle = NSColor.white.withAlphaComponent(0.55)       // .light 图标未悬停外框
        static let nameBandText = focusLine                                           // 图标名称标注文字（与焦点描边同值 white@0.95）

        // —— 浅色壁纸色带：.light 图标底 / 迷你屏 / 编辑器画布的唯一渐变 ——
        static let wallpaperRampTop = NSColor(red: 0.80, green: 0.87, blue: 0.95, alpha: 1)
        static let wallpaperRampMid = NSColor(red: 0.52, green: 0.67, blue: 0.86, alpha: 1)
        static let wallpaperRampBottom = NSColor(red: 0.34, green: 0.50, blue: 0.76, alpha: 1)
        static let wallpaperRampLocations: [CGFloat] = [0, 0.55, 1]

        /// 三 stop 壁纸渐变（顶→底）。预览即真实：迷你屏与画布必须用它，不得取二 stop 近似。
        static func makeWallpaperGradient() -> NSGradient? {
            NSGradient(colors: [wallpaperRampTop, wallpaperRampMid, wallpaperRampBottom],
                       atLocations: wallpaperRampLocations,
                       colorSpace: NSColorSpace.deviceRGB)
        }

        // —— 衍生表面色（语义色 + alpha，随系统外观）——
        static let cardFill = NSColor.quaternaryLabelColor.withAlphaComponent(0.12)   // 引导步骤卡底色
        static let badgeFill = NSColor.quaternaryLabelColor.withAlphaComponent(0.25)  // 快捷键徽章底色
        static let menuMiniFill = NSColor.controlAccentColor.withAlphaComponent(0.8)  // 菜单迷你预览块
    }

    // MARK: - 圆角

    enum Radius {
        static let menuMini: CGFloat = 2         // 菜单迷你预览块
        static let cell: CGFloat = 4             // 图标/画布内区域块
        static let insetFrame: CGFloat = 4       // 背景井/画布/预览的 CALayer 圆角
        static let badge: CGFloat = 5            // 快捷键徽章
        static let nameBand: CGFloat = 6         // 图标名称标注带
        static let icon: CGFloat = 8             // 布局图标外框
        static let zone: CGFloat = 10            // 整屏分区预览矩形
        static let screenFrame: CGFloat = 4      // 定位页迷你屏外框（真实屏圆角按预览缩放比例只有 ~3pt，10pt 明显过大）
        static let onboardingCard: CGFloat = 12  // 引导步骤卡
    }

    // MARK: - 字体

    enum Font {
        static let heroTitle = NSFont.systemFont(ofSize: 26, weight: .bold)          // 引导主标题
        static let dialogTitle = NSFont.systemFont(ofSize: 20, weight: .bold)        // 关于页标题
        static let listTitle = NSFont.systemFont(ofSize: 14, weight: .semibold)      // 列表行主标题
        static let sectionTitle = NSFont.systemFont(ofSize: 13, weight: .semibold)   // 小节标题
        static let tab = NSFont.systemFont(ofSize: 13)                               // 设置 tab 标签
        static let menuDot = NSFont.systemFont(ofSize: 13, weight: .semibold)        // 菜单状态行圆点
        static let menuTitle = NSFont.menuFont(ofSize: 13)                           // 菜单状态行正文
        static let menuDetail = NSFont.menuFont(ofSize: 11)                          // 菜单状态行详情
        static let body = NSFont.systemFont(ofSize: 12)                              // 正文标签
        static let bodyEmphasis = NSFont.systemFont(ofSize: 12, weight: .medium)     // 正文强调
        static let stepTitle = NSFont.systemFont(ofSize: 13, weight: .medium)        // 引导步骤标题
        static let hint = NSFont.systemFont(ofSize: 11)                              // 次要提示
        static let caption = NSFont.systemFont(ofSize: 10)                           // 说明文字
        static let iconName = NSFont.systemFont(ofSize: 9, weight: .medium)          // 图标条名称标注
        static let monoSmall = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular) // 日志路径
        static let monoBadge = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular) // 快捷键徽章
        static let monoField = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular) // 网格密度数字框
    }

    // MARK: - 间距

    enum Spacing {
        static let pageInsets = NSEdgeInsets(top: 18, left: 24, bottom: 18, right: 24)       // 页面栈边距
        static let groupInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)      // 分组框内边距
        static let cardInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)       // 引导卡内边距
        static let onboardingInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24) // 引导页边距
        static let stackGap: CGFloat = 10     // 页面栈小节间距
        static let groupGap: CGFloat = 8      // 分组框内行距 / 行内控件间距
        static let cardGap: CGFloat = 16      // 卡片内行距、引导页节距
        static let headerGap: CGFloat = 6     // 头部行距
        static let cellInsetDark: CGFloat = 1.5 // .dark 图标区域块内缩（贴满图标，拖拽条语义）；编辑器画布区域块同用
        static let cellInsetLight: CGFloat = 3  // .light 区域块内缩目标值（84pt 参考高度；6pt 用户嫌边距过宽）
        static let barInset: CGFloat = 24       // 窗口底栏控件左右边距（与 pageInsets 左值一致；旧值 16 是规范外魔法数）
        static let nameBandHeight: CGFloat = 15 // 图标名称标注带高度
    }

    // MARK: - 动效

    enum Motion {
        static let frameInterval: TimeInterval = 0.016       // 吸附动画帧步进
        static let sameScreenSteps = 10                      // 同屏插值步数
        static let crossScreenSteps = 8                      // 跨屏每阶段步数
        static let crossScreenResizeHold: TimeInterval = 0.03 // 跨屏第二阶段停留
        static let attractPulseInterval: TimeInterval = 0.6  // 缺权限菜单图标闪烁周期
        // 缓动统一为 smoothstep t²(3−2t)（WindowAnimator 内实现）
    }

    // MARK: - 通用文本助手

    /// 设置窗口与布局编辑器共用的文本构造器；禁止各窗口再造私有版本。
    enum Text {
        /// 小节标题（分组框标题在外）：13pt semibold
        static func sectionTitle(_ text: String) -> NSTextField {
            let f = NSTextField(labelWithString: text)
            f.font = Design.Font.sectionTitle
            return f
        }

        /// 正文标签：12pt
        static func bodyLabel(_ text: String) -> NSTextField {
            let f = NSTextField(labelWithString: text)
            f.font = Design.Font.body
            return f
        }

        /// 说明文字：10pt 灰色小字，最多 2 行换行；wrapWidth 限定换行宽度
        static func caption(_ text: String, wrapWidth: CGFloat? = nil) -> NSTextField {
            let f = NSTextField(labelWithString: text)
            f.font = Design.Font.caption
            f.textColor = .secondaryLabelColor
            f.lineBreakMode = .byWordWrapping
            f.maximumNumberOfLines = 2
            if let wrapWidth { f.preferredMaxLayoutWidth = wrapWidth }
            return f
        }
    }
}

/// 图标条配色主题（规范：foundations.md §1.5）。行为页「图标条配色」可选；
/// 每套主题五个槽位，新增主题需同步 Prefs.stripTheme 上限。
enum StripTheme {
    case ink        // 墨蓝（默认）：深藏青底 + 雾蓝块
    case graphite   // 石墨
    case teal       // 青碧
    case violet     // 紫罗兰

    static func at(_ index: Int) -> StripTheme {
        [StripTheme.ink, .graphite, .teal, .violet][max(0, min(3, index))]
    }

    var bgColors: [NSColor] {
        switch self {
        case .ink:     return [NSColor(red: 0.13, green: 0.17, blue: 0.26, alpha: 1),
                               NSColor(red: 0.09, green: 0.12, blue: 0.19, alpha: 1)]
        case .graphite: return [NSColor(red: 0.18, green: 0.18, blue: 0.19, alpha: 1),
                                NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)]
        case .teal:    return [NSColor(red: 0.05, green: 0.17, blue: 0.19, alpha: 1),
                               NSColor(red: 0.03, green: 0.11, blue: 0.13, alpha: 1)]
        case .violet:  return [NSColor(red: 0.16, green: 0.10, blue: 0.25, alpha: 1),
                               NSColor(red: 0.10, green: 0.06, blue: 0.17, alpha: 1)]
        }
    }

    var cellFill: NSColor {
        switch self {
        case .ink:     return NSColor(red: 0.44, green: 0.65, blue: 0.94, alpha: 0.92)
        case .graphite: return NSColor(red: 0.82, green: 0.82, blue: 0.84, alpha: 0.88)
        case .teal:    return NSColor(red: 0.25, green: 0.78, blue: 0.74, alpha: 0.92)
        case .violet:  return NSColor(red: 0.71, green: 0.55, blue: 0.95, alpha: 0.92)
        }
    }

    var cellStroke: NSColor {
        NSColor.white.withAlphaComponent(0.30)
    }

    /// 悬停投影命中的区域块（亮色填充，与压暗的其余块强对比）
    var activeCellFill: NSColor {
        switch self {
        case .ink:     return NSColor(red: 0.95, green: 0.97, blue: 1.00, alpha: 0.97)
        case .graphite: return NSColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.97)
        case .teal:    return NSColor(red: 0.75, green: 1.00, blue: 0.95, alpha: 0.97)
        case .violet:  return NSColor(red: 0.90, green: 0.82, blue: 1.00, alpha: 0.97)
        }
    }

    /// 选中区域的描边（醒目强调色）
    var activeCellStroke: NSColor {
        switch self {
        case .ink:     return NSColor(red: 0.30, green: 0.55, blue: 0.95, alpha: 1)
        case .graphite: return NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1)
        case .teal:    return NSColor(red: 0.10, green: 0.65, blue: 0.60, alpha: 1)
        case .violet:  return NSColor(red: 0.55, green: 0.35, blue: 0.90, alpha: 1)
        }
    }
}
