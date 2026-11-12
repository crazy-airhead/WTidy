import Foundation
import ServiceManagement
import AppKit

/// 基于 SMAppService（macOS 13+）的登录自启管理——
/// 这是现代 BTM 原生 API，治好原版 Window Tidy「自启悄悄失效」的老毛病。
enum LoginItemController {
    /// 只有从 .app bundle 运行时才能注册；开发期直接跑二进制时不可用。
    static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ on: Bool) -> Bool {
        guard isAvailable else {
            AppLog.warn("登录自启不可用：未从 .app bundle 运行（\(Bundle.main.bundlePath)）")
            return false
        }
        do {
            if on {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            AppLog.info("登录自启 → \(on)（status=\(SMAppService.mainApp.status.rawValue)）")
            return true
        } catch {
            AppLog.error("登录自启设置失败 (on=\(on)): \(error)")
            return false
        }
    }
}
