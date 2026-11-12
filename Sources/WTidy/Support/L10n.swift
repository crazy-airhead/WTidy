import Foundation

/// 本地化助手：源码内以中文串为键，en.lproj 提供英文翻译；
/// zh-Hans 系统直接回退显示键本身（即中文），无需翻译文件。
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// 带参数的本地化（键内使用 %d / %@ 占位）
func LF(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), locale: Locale.current, arguments: args)
}
