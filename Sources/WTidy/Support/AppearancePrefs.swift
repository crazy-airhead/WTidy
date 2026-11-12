import Foundation
import AppKit

/// 应用级外观偏好：界面语言与外观模式（菜单可直接切换）。
enum AppearancePrefs {
    enum Language: String, CaseIterable {
        case system   // 跟随系统
        case zhHans   // 简体中文
        case en       // English
    }

    enum Appearance: String, CaseIterable {
        case system  // 跟随系统
        case light   // 浅色
        case dark    // 深色
    }

    private static let languageKey = "appLanguage"
    private static let appearanceKey = "appAppearance"

    static var language: Language {
        get { Language(rawValue: UserDefaults.standard.string(forKey: languageKey) ?? "") ?? .system }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: languageKey)
            apply()
        }
    }

    static var appearance: Appearance {
        get { Appearance(rawValue: UserDefaults.standard.string(forKey: appearanceKey) ?? "") ?? .system }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: appearanceKey)
            apply()
        }
    }

    /// 应用当前选择：
    /// - 语言：写 AppleLanguages（应用级覆写）。NSBundle 的 Localizable 查找即时生效，
    ///   但**已构建的 UI 文本不会自动重绘**——需要重启应用。菜单上明确标注。
    /// - 外观：NSApp.appearance 即时生效（无需重启）。
    static func apply() {
        switch language {
        case .system:
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case .zhHans:
            UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
        case .en:
            UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        }

        switch appearance {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// 语言变更需要重启才能全面生效
    static var needsRestartForLanguage: Bool { true }
}
