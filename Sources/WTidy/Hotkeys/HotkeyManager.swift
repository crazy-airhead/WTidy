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
        case .leftHalf: return L("左半屏")
        case .rightHalf: return L("右半屏")
        case .topHalf: return L("上半屏")
        case .bottomHalf: return L("下半屏")
        case .leftThird: return L("左 1/3")
        case .middleThird: return L("中 1/3")
        case .rightThird: return L("右 1/3")
        case .twoThirdsLeft: return L("左 2/3")
        case .twoThirdsRight: return L("右 2/3")
        case .maximize: return L("最大化")
        case .center: return L("居中")
        case .restore: return L("恢复位置")
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
        case .leftHalf: base = L("←")
        case .rightHalf: base = L("→")
        case .topHalf: base = L("↑")
        case .bottomHalf: base = L("↓")
        case .leftThird: base = "["
        case .middleThird: base = "\\"
        case .rightThird: base = "]"
        case .twoThirdsLeft: base = "["
        case .twoThirdsRight: base = "]"
        case .maximize: base = "F"
        case .center: base = "C"
        case .restore: base = "Z"
        }
        let ctrl = defaultModifiers & controlKey != 0 ? L("⌃") : ""
        let opt = defaultModifiers & optionKey != 0 ? L("⌥") : ""
        let cmd = defaultModifiers & cmdKey != 0 ? L("⌘") : ""
        return ctrl + opt + cmd + base
    }
}

// MARK: - Carbon 全局快捷键管理

/// 与拖拽分屏互为兜底：个别应用不发 AX moved 通知时，快捷键仍可用。
final class HotkeyManager {
    var actionHandler: ((SnapAction) -> Void)?

    private var hotKeyRefs: [SnapAction: EventHotKeyRef] = [:]
    private var layoutHotKeyRefs: [EventHotKeyRef] = []
    /// 每布局激活快捷键：热键 id → 布局 id（原版每布局 Activation Shortcut）
    private var layoutShortcutMap: [UInt32: String] = [:]
    var layoutShortcutHandler: ((String) -> Void)?
    private var handlerInstalled = false
    private let signature: OSType = 0x57546479 // 'WTdy'
    private static let layoutHotKeyBase: UInt32 = 3000

    static let shared = HotkeyManager()

    /// 冲突查询：该组合是否已被固定动作或其他布局占用（录制前校验）。
    /// 返回占用者的显示名；无冲突返回 nil。
    func conflictOwner(keyCode: UInt32, modifiers: Int, excluding layoutID: String?) -> String? {
        for action in SnapAction.allCases where Prefs.hotkeyEnabled(action.rawValue) {
            if action.defaultKeyCode == keyCode && action.defaultModifiers == modifiers {
                return action.displayName
            }
        }
        for layout in LayoutStore.layouts where layout.id != layoutID {
            if let kc = layout.activationKeyCode, kc > 0, kc == Int(keyCode),
               layout.activationModifiers == modifiers {
                return layout.name
            }
        }
        return nil
    }

    /// 依据偏好整体重注册
    func refresh() {
        unregisterAll()

        guard AccessibilityService.isTrusted else { return }
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

        // 每布局激活快捷键（原版 Activation Shortcut）：应用到前台窗口
        layoutShortcutMap.removeAll()
        var seq = Self.layoutHotKeyBase
        for layout in LayoutStore.layouts {
            guard let kc = layout.activationKeyCode, kc > 0,
                  let mods = layout.activationModifiers else { continue }
            let hkID = EventHotKeyID(signature: signature, id: seq)
            var ref: EventHotKeyRef?
            let err = RegisterEventHotKey(UInt32(kc), UInt32(mods), hkID,
                                          GetApplicationEventTarget(), 0, &ref)
            if err == noErr, let ref = ref {
                layoutHotKeyRefs.append(ref)
                layoutShortcutMap[seq] = layout.id
            } else {
                // 注册失败多半是与本应用外占用的组合冲突——至少留痕，别静默
                AppLog.warn("布局快捷键注册失败 \(layout.name) kc=\(kc) err=\(err)")
            }
            seq += 1
        }
        AppLog.info("快捷键已注册 \(hotKeyRefs.count)/\(SnapAction.allCases.count) + 布局快捷键 \(layoutShortcutMap.count)")
    }

    func unregisterAll() {
        for (_, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
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
