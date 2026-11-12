import Foundation

enum Prefs {
    static let defaults = UserDefaults.standard

    enum Keys {
        static let onboardingDone = "onboardingCompleted"
        static let dragEnabled = "dragSnappingEnabled"
        static let hotkeysEnabled = "hotkeysEnabled"
        static let windowGap = "windowGap"
        static let lastSnap = "lastSnapDescription"
        static let hotkeyEnabledPrefix = "hotkey.enabled."
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

    private static func set(_ value: Any?, forKey key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: .prefsChanged, object: nil)
    }
}

extension Notification.Name {
    static let prefsChanged = Notification.Name("WTidyPrefsChanged")
}
