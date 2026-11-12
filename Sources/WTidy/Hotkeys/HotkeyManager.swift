import Foundation
import AppKit
import Carbon.HIToolbox

// MARK: - 快捷键动作定义

enum SnapAction: String, CaseIterable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case leftThird
    case middleThird
    case rightThird
    case twoThirdsLeft
    case twoThirdsRight
    case maximize
    case center
    case restore

    var displayName: String {
        switch self {
        case .leftHalf: return "左半屏"
        case .rightHalf: return "右半屏"
        case .topHalf: return "上半屏"
        case .bottomHalf: return "下半屏"
        case .leftThird: return "左 1/3"
        case .middleThird: return "中 1/3"
        case .rightThird: return "右 1/3"
        case .twoThirdsLeft: return "左 2/3"
        case .twoThirdsRight: return "右 2/3"
        case .maximize: return "最大化"
        case .center: return "居中"
        case .restore: return "恢复位置"
        }
    }

    /// Carbon 键码与修饰键
    var defaultKeyCode: UInt32 {
        switch self {
        case .leftHalf: return 123   // ←
        case .rightHalf: return 124  // →
        case .topHalf: return 126    // ↑
        case .bottomHalf: return 125 // ↓
        case .leftThird: return 33   // [
        case .middleThird: return 42 // \
        case .rightThird: return 30  // ]
        case .twoThirdsLeft: return 33
        case .twoThirdsRight: return 30
        case .maximize: return 3     // F
        case .center: return 8       // C
        case .restore: return 6      // Z
        }
    }

    var defaultModifiers: Int {
        switch self {
        case .leftHalf, .rightHalf, .leftThird, .middleThird, .rightThird:
            return cmdKey | optionKey                      // ⌥⌘
        case .topHalf, .bottomHalf, .twoThirdsLeft, .twoThirdsRight,
             .maximize, .center, .restore:
            return cmdKey | optionKey | controlKey         // ⌃⌥⌘
        }
    }

    /// 设置界面里的可读形式
    var keyDescription: String {
        let base: String
        switch self {
        case .leftHalf: base = "←"
        case .rightHalf: base = "→"
        case .topHalf: base = "↑"
        case .bottomHalf: base = "↓"
        case .leftThird: base = "["
        case .middleThird: base = "\\"
        case .rightThird: base = "]"
        case .twoThirdsLeft: base = "["
        case .twoThirdsRight: base = "]"
        case .maximize: base = "F"
        case .center: base = "C"
        case .restore: base = "Z"
        }
        let ctrl = defaultModifiers & controlKey != 0 ? "⌃" : ""
        let opt = defaultModifiers & optionKey != 0 ? "⌥" : ""
        let cmd = defaultModifiers & cmdKey != 0 ? "⌘" : ""
        return ctrl + opt + cmd + base
    }
}

// MARK: - Carbon 全局快捷键管理

/// 与拖拽分屏互为兜底：个别应用不发 AX moved 通知时，快捷键仍可用。
final class HotkeyManager {
    var actionHandler: ((SnapAction) -> Void)?

    private var hotKeyRefs: [SnapAction: EventHotKeyRef] = [:]
    private var handlerInstalled = false
    private let signature: OSType = 0x57546479 // 'WTdy'

    static let shared = HotkeyManager()

    /// 依据偏好整体重注册
    func refresh() {
        unregisterAll()

        guard Prefs.hotkeysEnabled, AccessibilityService.isTrusted else { return }
        installHandlerIfNeeded()

        for (index, action) in SnapAction.allCases.enumerated() {
            guard Prefs.hotkeyEnabled(action.rawValue) else { continue }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: signature, id: UInt32(index + 1))
            let err = RegisterEventHotKey(action.defaultKeyCode,
                                          UInt32(action.defaultModifiers),
                                          id,
                                          GetApplicationEventTarget(),
                                          0,
                                          &ref)
            if err == noErr, let ref = ref {
                hotKeyRefs[action] = ref
            } else {
                AppLog.warn("注册快捷键失败 \(action.rawValue) err=\(err)")
            }
        }
        AppLog.info("快捷键已注册 \(hotKeyRefs.count)/\(SnapAction.allCases.count)")
    }

    func unregisterAll() {
        for (_, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event = event else { return noErr }
            var hkID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           UInt32(kEventParamDirectObject),
                                           UInt32(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hkID)
            guard status == noErr else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData!).takeUnretainedValue()
            let index = Int(hkID.id) - 1
            guard SnapAction.allCases.indices.contains(index) else { return noErr }
            let action = SnapAction.allCases[index]
            DispatchQueue.main.async {
                manager.actionHandler?(action)
            }
            return noErr
        }
        let status = InstallEventHandler(GetApplicationEventTarget(),
                                         callback,
                                         1,
                                         &spec,
                                         Unmanaged.passUnretained(self).toOpaque(),
                                         nil)
        handlerInstalled = (status == noErr)
        if !handlerInstalled {
            AppLog.warn("InstallEventHandler 失败 status=\(status)")
        }
    }
}
