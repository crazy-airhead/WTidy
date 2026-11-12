import Foundation
import Carbon.HIToolbox

enum Prefs {
    static let defaults = UserDefaults.standard

    enum Keys {
        static let onboardingDone = "onboardingCompleted"
        static let dragEnabled = "dragSnappingEnabled"
        static let hotkeysEnabled = "hotkeysEnabled"
        static let windowGap = "windowGap"
        static let lastSnap = "lastSnapDescription"
        static let hotkeyEnabledPrefix = "hotkey.enabled."
        // 定位（原版 Positioning）
        static let stripVertical = "stripOrientationVertical"
        static let stripPosX = "stripPosX"          // 0..1，0=左
        static let stripPosY = "stripPosY"          // 0..1，0=顶
        static let stripMaxWidth = "stripMaxWidth"  // 整条最大宽度
        static let stripMargin = "stripMargin"      // 屏幕边距
        // 行为（原版 Options）
        static let optionKeyMode = "optionKeyMode"  // 0=按住⌥隐藏 1=按住⌥显示 2=不使用
        static let showStatusIcon = "showStatusIcon"
        static let showLayoutNames = "showLayoutNames"
        static let warnOnFail = "warnOnFail"
        static let stripBackground = "stripBackground" // 0=默认深色 1=桌面壁纸
        // 快速布局（原版 Quick Layout）
        static let qlKeyCode = "qlKeyCode"
        static let qlModifiers = "qlModifiers"
        static let qlNearCursor = "qlNearCursor"
        static let qlPosX = "qlPosX"
        static let qlPosY = "qlPosY"
        static let qlWidth = "qlWidth"
        static let qlHeight = "qlHeight"
    }

    static var onboardingDone: Bool {
        get { defaults.bool(forKey: Keys.onboardingDone) }
        set { set(newValue, forKey: Keys.onboardingDone) }
    }

    static var dragEnabled: Bool {
        get { defaults.object(forKey: Keys.dragEnabled) == nil ? true : defaults.bool(forKey: Keys.dragEnabled) }
        set { set(newValue, forKey: Keys.dragEnabled) }
    }

    static var hotkeysEnabled: Bool {
        get { defaults.object(forKey: Keys.hotkeysEnabled) == nil ? true : defaults.bool(forKey: Keys.hotkeysEnabled) }
        set { set(newValue, forKey: Keys.hotkeysEnabled) }
    }

    /// 吸附后窗口之间的间隙（点），0 = 完全贴合（原版行为）
    static var windowGap: CGFloat {
        get {
            let raw = defaults.double(forKey: Keys.windowGap)
            return CGFloat(min(max(raw, 0), 32))
        }
        set { set(Double(min(max(newValue, 0), 32)), forKey: Keys.windowGap) }
    }

    static var lastSnap: String? {
        get { defaults.string(forKey: Keys.lastSnap) }
        set { set(newValue, forKey: Keys.lastSnap) }
    }

    static func hotkeyEnabled(_ id: String) -> Bool {
        let key = Keys.hotkeyEnabledPrefix + id
        return defaults.object(forKey: key) == nil ? true : defaults.bool(forKey: key)
    }

    static func setHotkeyEnabled(_ enabled: Bool, id: String) {
        set(enabled, forKey: Keys.hotkeyEnabledPrefix + id)
    }

    // MARK: - 定位（原版 Positioning）

    /// 图标条排列方向：false=横向（默认），true=纵向
    static var stripVertical: Bool {
        get { defaults.bool(forKey: Keys.stripVertical) }
        set { set(newValue, forKey: Keys.stripVertical) }
    }

    /// 图标条水平位置系数 0..1（0=贴左，0.5=居中默认）
    static var stripPosX: Double {
        get {
            let v = defaults.object(forKey: Keys.stripPosX) == nil ? 0.5 : defaults.double(forKey: Keys.stripPosX)
            return min(max(v, 0), 1)
        }
        set { set(min(max(newValue, 0), 1), forKey: Keys.stripPosX) }
    }

    /// 图标条垂直位置系数 0..1（0=贴顶默认）
    static var stripPosY: Double {
        get {
            let v = defaults.object(forKey: Keys.stripPosY) == nil ? 0 : defaults.double(forKey: Keys.stripPosY)
            return min(max(v, 0), 1)
        }
        set { set(min(max(newValue, 0), 1), forKey: Keys.stripPosY) }
    }

    /// 整条最大宽度（原版默认 512）
    static var stripMaxWidth: Double {
        get {
            let v = defaults.object(forKey: Keys.stripMaxWidth) == nil ? 512 : defaults.double(forKey: Keys.stripMaxWidth)
            return min(max(v, 200), 1600)
        }
        set { set(min(max(newValue, 200), 1600), forKey: Keys.stripMaxWidth) }
    }

    /// 屏幕边距（原版默认 0）
    static var stripMargin: Double {
        get {
            let v = defaults.object(forKey: Keys.stripMargin) == nil ? 0 : defaults.double(forKey: Keys.stripMargin)
            return min(max(v, 0), 100)
        }
        set { set(min(max(newValue, 0), 100), forKey: Keys.stripMargin) }
    }

    // MARK: - 行为（原版 Options）

    /// ⌥ 键模式：0=按住隐藏图标（默认），1=按住显示图标，2=不使用 ⌥
    static var optionKeyMode: Int {
        get {
            let v = defaults.object(forKey: Keys.optionKeyMode) == nil ? 0 : defaults.integer(forKey: Keys.optionKeyMode)
            return min(max(v, 0), 2)
        }
        set { set(newValue, forKey: Keys.optionKeyMode) }
    }

    static var showStatusIcon: Bool {
        get { defaults.object(forKey: Keys.showStatusIcon) == nil ? true : defaults.bool(forKey: Keys.showStatusIcon) }
        set { set(newValue, forKey: Keys.showStatusIcon) }
    }

    static var showLayoutNames: Bool {
        get { defaults.bool(forKey: Keys.showLayoutNames) }
        set { set(newValue, forKey: Keys.showLayoutNames) }
    }

    static var warnOnFail: Bool {
        get { defaults.object(forKey: Keys.warnOnFail) == nil ? true : defaults.bool(forKey: Keys.warnOnFail) }
        set { set(newValue, forKey: Keys.warnOnFail) }
    }

    /// 图标条背景：0=默认深色，1=桌面壁纸
    static var stripBackground: Int {
        get { defaults.integer(forKey: Keys.stripBackground) }
        set { set(newValue, forKey: Keys.stripBackground) }
    }

    // MARK: - 快速布局（原版 Quick Layout）

    /// 全局快捷键（Carbon 键码 + 修饰键），默认 ⌃⌥⌘L（L 键码 37）
    static var qlKeyCode: UInt32 {
        get {
            let v = defaults.object(forKey: Keys.qlKeyCode) == nil ? 37 : defaults.integer(forKey: Keys.qlKeyCode)
            return UInt32(v)
        }
        set { set(Int(newValue), forKey: Keys.qlKeyCode) }
    }

    static var qlModifiers: Int {
        get {
            let v = defaults.object(forKey: Keys.qlModifiers) == nil
                ? (cmdKey | optionKey | controlKey) : defaults.integer(forKey: Keys.qlModifiers)
            return v
        }
        set { set(newValue, forKey: Keys.qlModifiers) }
    }

    static var qlNearCursor: Bool {
        get { defaults.object(forKey: Keys.qlNearCursor) == nil ? true : defaults.bool(forKey: Keys.qlNearCursor) }
        set { set(newValue, forKey: Keys.qlNearCursor) }
    }

    static var qlPosX: Double {
        get {
            let v = defaults.object(forKey: Keys.qlPosX) == nil ? 0.5 : defaults.double(forKey: Keys.qlPosX)
            return min(max(v, 0), 1)
        }
        set { set(min(max(newValue, 0), 1), forKey: Keys.qlPosX) }
    }

    static var qlPosY: Double {
        get {
            let v = defaults.object(forKey: Keys.qlPosY) == nil ? 0.5 : defaults.double(forKey: Keys.qlPosY)
            return min(max(v, 0), 1)
        }
        set { set(min(max(newValue, 0), 1), forKey: Keys.qlPosY) }
    }

    /// 快速布局面板宽度（原版默认 512）
    static var qlWidth: Double {
        get {
            let v = defaults.object(forKey: Keys.qlWidth) == nil ? 512 : defaults.double(forKey: Keys.qlWidth)
            return min(max(v, 240), 1200)
        }
        set { set(min(max(newValue, 240), 1200), forKey: Keys.qlWidth) }
    }

    /// 快速布局面板高度（原版默认 288）
    static var qlHeight: Double {
        get {
            let v = defaults.object(forKey: Keys.qlHeight) == nil ? 288 : defaults.double(forKey: Keys.qlHeight)
            return min(max(v, 160), 800)
        }
        set { set(min(max(newValue, 160), 800), forKey: Keys.qlHeight) }
    }

    private static func set(_ value: Any?, forKey key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: .prefsChanged, object: nil)
    }
}

extension Notification.Name {
    static let prefsChanged = Notification.Name("WTidyPrefsChanged")
}
