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
    private var customHotKeyRefs: [EventHotKeyRef] = []
    /// 每区域快捷键：热键 id → (布局 id, 区域下标)——直接吸到指定区域，跳过投影选区
    private var regionShortcutMap: [UInt32: (layoutID: String, region: Int)] = [:]
    var layoutRegionHandler: ((String, Int) -> Void)?
    private var handlerInstalled = false
    private let signature: OSType = 0x57546479 // 'WTdy'
    private static let regionHotKeyBase: UInt32 = 6000

    static let shared = HotkeyManager()

    /// 冲突查询：该组合是否已被固定动作或其他布局的区域快捷键占用（录制前校验）。
    /// excluding 指明正在录制的对象 (layoutID, region)，只有精确同位才豁免（重录自己）。
    /// 返回占用者的显示名；无冲突返回 nil。
    func conflictOwner(keyCode: UInt32, modifiers: Int,
                       excluding layoutID: String, region: Int) -> String? {
        for action in SnapAction.allCases where Prefs.hotkeyEnabled(action.rawValue) {
            if action.defaultKeyCode == keyCode && action.defaultModifiers == modifiers {
                return action.displayName
            }
        }
        for layout in LayoutStore.layouts {
            let isSelf = (layout.id == layoutID)
            for (idx, hk) in layout.regionHotkeys where hk.keyCode > 0 {
                if isSelf && region == idx { continue }   // 豁免精确同位
                if hk.keyCode == Int(keyCode), hk.modifiers == modifiers {
                    return layout.name + " · " + LF("区域 %d", idx + 1)
                }
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

        // 每区域快捷键：直接吸到指定区域
        regionShortcutMap.removeAll()
        var regionSeq = Self.regionHotKeyBase
        for layout in LayoutStore.layouts {
            for (region, hk) in layout.regionHotkeys where hk.keyCode > 0 {
                let hkID = EventHotKeyID(signature: signature, id: regionSeq)
                var ref: EventHotKeyRef?
                let err = RegisterEventHotKey(UInt32(hk.keyCode), UInt32(hk.modifiers), hkID,
                                              GetApplicationEventTarget(), 0, &ref)
                if err == noErr, let ref = ref {
                    customHotKeyRefs.append(ref)
                    regionShortcutMap[regionSeq] = (layout.id, region)
                } else {
                    // 注册失败多半是与本应用外占用的组合冲突——至少留痕，别静默
                    AppLog.warn("区域快捷键注册失败 \(layout.name) 区域\(region + 1) kc=\(hk.keyCode) err=\(err)")
                }
                regionSeq += 1
            }
        }
        AppLog.info("快捷键已注册 \(hotKeyRefs.count)/\(SnapAction.allCases.count) + 区域快捷键 \(regionShortcutMap.count)")
    }

    func unregisterAll() {
        for (_, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        for ref in customHotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        customHotKeyRefs.removeAll()
        regionShortcutMap.removeAll()
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
            if hkID.id >= HotkeyManager.regionHotKeyBase,
               let target = manager.regionShortcutMap[hkID.id] {
                DispatchQueue.main.async {
                    manager.layoutRegionHandler?(target.layoutID, target.region)
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
