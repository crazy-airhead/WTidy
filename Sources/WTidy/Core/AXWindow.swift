import Foundation
import AppKit
import ApplicationServices

// MARK: - AX 属性读写小工具

@discardableResult
func axCopyValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard err == .success else { return nil }
    return value
}

func axAttributeBool(_ element: AXUIElement, _ attribute: String) -> Bool? {
    guard let v = axCopyValue(element, attribute) else { return nil }
    if let n = v as? NSNumber { return n.boolValue }
    return nil
}

func axAttributeString(_ element: AXUIElement, _ attribute: String) -> String? {
    axCopyValue(element, attribute) as? String
}

func axAttributeElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
    guard let v = axCopyValue(element, attribute) else { return nil }
    guard CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
    return (v as! AXUIElement)
}

func axAttributePoint(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
    guard let v = axCopyValue(element, attribute),
          CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    var p = CGPoint()
    guard AXValueGetValue(v as! AXValue, .cgPoint, &p) else { return nil }
    return p
}

func axAttributeSize(_ element: AXUIElement, _ attribute: String) -> CGSize? {
    guard let v = axCopyValue(element, attribute),
          CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    var s = CGSize()
    guard AXValueGetValue(v as! AXValue, .cgSize, &s) else { return nil }
    return s
}

@discardableResult
func axSetPoint(_ element: AXUIElement, _ attribute: String, _ point: CGPoint) -> Bool {
    var p = point
    guard let value = AXValueCreate(.cgPoint, &p) else { return false }
    return AXUIElementSetAttributeValue(element, attribute as CFString, value) == .success
}

@discardableResult
func axSetSize(_ element: AXUIElement, _ attribute: String, _ size: CGSize) -> Bool {
    var s = size
    guard let value = AXValueCreate(.cgSize, &s) else { return false }
    return AXUIElementSetAttributeValue(element, attribute as CFString, value) == .success
}

// MARK: - AXWindow

/// 一个可操作的外部窗口（AX 元素封装）。
/// frame 全部使用 AppKit 全局坐标；与 AX 顶左坐标的换算封装在内。
final class AXWindow {
    let ref: AXUIElement
    let pid: pid_t

    init(element: AXUIElement, pid: pid_t) {
        self.ref = element
        self.pid = pid
    }

    var title: String? { axAttributeString(ref, kAXTitleAttribute) }
    var role: String? { axAttributeString(ref, kAXRoleAttribute) }
    var subrole: String? { axAttributeString(ref, kAXSubroleAttribute) }

    var isStandardWindow: Bool {
        subrole == (kAXStandardWindowSubrole as String)
    }

    var isMinimized: Bool {
        axAttributeBool(ref, kAXMinimizedAttribute) ?? false
    }

    var isFullScreen: Bool {
        // kAXFullScreenAttribute 未公开导入到 Swift，用其底层字符串
        axAttributeBool(ref, "AXFullScreen") ?? false
    }

    /// 适合吸附：标准窗口、未最小化、非全屏
    var canSnap: Bool {
        isStandardWindow && !isMinimized && !isFullScreen
    }

    // MARK: - frame（AppKit 全局坐标）

    /// 窗口 frame（AppKit 全局坐标），读取失败返回 nil
    var nsFrame: CGRect? {
        get {
            guard let p = axAttributePoint(ref, kAXPositionAttribute),
                  let s = axAttributeSize(ref, kAXSizeAttribute) else { return nil }
            return ScreenGeometry.nsRect(fromAX: CGRect(origin: p, size: s),
                                         primaryScreenHeight: ScreenGeometry.currentPrimaryHeight)
        }
        set {
            guard let rect = newValue else { return }
            setNSFrame(rect)
        }
    }

    /// 写入 frame：先位置后尺寸，再做一次位置校正
    /// （部分应用在改尺寸时会自行挪动窗口）
    func setNSFrame(_ rect: CGRect) {
        let h = ScreenGeometry.currentPrimaryHeight
        let axR = ScreenGeometry.axRect(fromNS: rect, primaryScreenHeight: h)
        axSetPoint(ref, kAXPositionAttribute, axR.origin)
        axSetSize(ref, kAXSizeAttribute, axR.size)
        // 校正：读回比较，偏差大于 1pt 就再写一次位置
        if let cur = nsFrame,
           abs(cur.minX - rect.minX) > 1 || abs(cur.minY - rect.minY) > 1 {
            axSetPoint(ref, kAXPositionAttribute, axR.origin)
        }
    }

    /// 只写位置（动画分阶段用）
    func setNSPosition(_ point: CGPoint) {
        let h = ScreenGeometry.currentPrimaryHeight
        axSetPoint(ref, kAXPositionAttribute, ScreenGeometry.axPoint(fromNS: point, primaryScreenHeight: h))
    }

    /// 只写尺寸（动画分阶段用）；尺寸不涉及原点翻转，无需坐标换算
    func setNSSize(_ size: CGSize) {
        axSetSize(ref, kAXSizeAttribute, size)
    }

    /// 用于 FrameMemory 的稳定键（pid + 标题，会话内足够）
    var memoryKey: String {
        "\(pid)|\(title ?? "")"
    }
}

// MARK: - 实时主屏高度（AppKit 坐标换算轴）

enum ScreenGeometryLive {
    static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 1080
    }
}

extension ScreenGeometry {
    static var currentPrimaryHeight: CGFloat { ScreenGeometryLive.primaryHeight }
}
