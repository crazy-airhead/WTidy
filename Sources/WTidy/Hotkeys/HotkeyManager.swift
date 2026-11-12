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
    /// 快速布局全局热键（对齐原版 Quick Layout Activation）
    var quickLayoutHandler: (() -> Void)?

    private var hotKeyRefs: [SnapAction: EventHotKeyRef] = [:]
    private var qlHotKeyRef: EventHotKeyRef?
    private var layoutHotKeyRefs: [EventHotKeyRef] = []
    /// 每布局激活快捷键：热键 id → 布局 id（原版每布局 Activation Shortcut）
    private var layoutShortcutMap: [UInt32: String] = [:]
    var layoutShortcutHandler: ((String) -> Void)?
    private var handlerInstalled = false
    private let signature: OSType = 0x57546479 // 'WTdy'
    private static let qlHotKeyID: UInt32 = 999
    private static let layoutHotKeyBase: UInt32 = 3000

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

        // 快速布局热键
        var qlRef: EventHotKeyRef?
        let qlID = EventHotKeyID(signature: signature, id: Self.qlHotKeyID)
        let qlErr = RegisterEventHotKey(Prefs.qlKeyCode, UInt32(Prefs.qlModifiers), qlID,
                                        GetApplicationEventTarget(), 0, &qlRef)
        if qlErr == noErr, let qlRef = qlRef {
            qlHotKeyRef = qlRef
        } else {
            AppLog.warn("注册快速布局热键失败 err=\(qlErr)")
        }

        // 每布局激活快捷键（原版 Activation Shortcut）：应用到前台窗口
        layoutShortcutMap.removeAll()
        var seq = Self.layoutHotKeyBase
        for layout in LayoutStore.layouts {
            guard let kc = layout.activationKeyCode, kc > 0,
                  let mods = layout.activationModifiers else { continue }
            let hkID = EventHotKeyID(signature: signature, id: seq)
            var ref: EventHotKeyRef?
            if RegisterEventHotKey(UInt32(kc), UInt32(mods), hkID,
                                   GetApplicationEventTarget(), 0, &ref) == noErr, let ref = ref {
                layoutHotKeyRefs.append(ref)
                layoutShortcutMap[seq] = layout.id
            }
            seq += 1
        }
        AppLog.info("快捷键已注册 \(hotKeyRefs.count)/\(SnapAction.allCases.count) + 快速布局 + 布局快捷键 \(layoutShortcutMap.count)")
    }

    func unregisterAll() {
        for (_, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        if let ref = qlHotKeyRef {
            UnregisterEventHotKey(ref)
            qlHotKeyRef = nil
        }
        for ref in layoutHotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        layoutHotKeyRefs.removeAll()
        layoutShortcutMap.removeAll()
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
            if hkID.id == HotkeyManager.qlHotKeyID {
                DispatchQueue.main.async {
                    manager.quickLayoutHandler?()
                }
                return noErr
            }
            if hkID.id >= HotkeyManager.layoutHotKeyBase,
               let layoutID = manager.layoutShortcutMap[hkID.id] {
                DispatchQueue.main.async {
                    manager.layoutShortcutHandler?(layoutID)
                }
                return noErr
            }
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
