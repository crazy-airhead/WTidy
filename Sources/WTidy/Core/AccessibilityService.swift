import Foundation
import AppKit
import ApplicationServices

/// AX 事件监听服务：盯住前台 app 的聚焦窗口，转发 windowMoved / focusedWindowChanged。
///
/// 原版 Window Tidy 的病根就在这里：observer 挂到 run loop 的 default mode，
/// 而窗口拖拽期间主线程进入 event tracking mode，通知丢失且永不自愈。
/// 本实现：
/// 1. observer source 挂 kCFRunLoopCommonModes（拖拽期间也能收到通知）；
/// 2. 提供事件驱动的 retarget + 看门狗定期 forceRebuild，静默失灵可自愈。
final class AccessibilityService {
    var delegate: ((AccessibilityService.Event) -> Void)?

    private(set) var observedPID: pid_t?
    private var observer: AXObserver?
    private var appElement: AXUIElement?
    private var observedWindow: AXUIElement?
    /// 跨 teardown 保留：上次报告过的聚焦窗口。
    /// 看门狗重建监听链时会重新 observe 同一个窗口，此时不应再发
    /// focusedWindowChanged——否则正在进行的拖拽会被误取消。
    private var lastReportedWindow: AXUIElement?

    enum Event {
        case windowDidMove(AXWindow)
        case focusedWindowChanged(AXWindow?)
    }

    // 通知名（SDK 把 CFSTR 常量导入为 String）
    private static let focusedChanged = kAXFocusedWindowChangedNotification as String
    private static let windowMoved = kAXWindowMovedNotification as String
    private static let elementMoved = kAXMovedNotification as String
    private static let destroyed = kAXUIElementDestroyedNotification as String

    // MARK: - 信任状态

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// 触发系统授权弹窗（不阻塞）
    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - 启动 / 重挂

    func start() {
        ActiveInstanceKeeper.retain(self)
        retargetFrontmost(force: true)
    }

    func stop() {
        teardown()
        ActiveInstanceKeeper.release()
    }

    /// 指向当前前台 app；pid 未变时只补挂聚焦窗口
    func retargetFrontmost(force: Bool = false) {
        guard AccessibilityService.isTrusted else { return }
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        let pid = front.processIdentifier
        guard pid != getpid() else { return }

        if force || pid != observedPID {
            teardown()
            if pid != observedPID {
                lastReportedWindow = nil   // 换 app：允许重新报告
            }
            buildObserver(pid: pid)
        } else {
            observeFocusedWindow()
        }
    }

    /// 看门狗用：无条件拆除重建
    func forceRebuild() {
        guard AccessibilityService.isTrusted else { return }
        teardown()
        retargetFrontmost(force: true)
    }

    /// 供快捷键路径使用：当前前台 app 的聚焦窗口
    func frontmostWindow() -> AXWindow? {
        guard AccessibilityService.isTrusted,
              let front = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = front.processIdentifier
        guard pid != getpid() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        guard let win = axAttributeElement(app, kAXFocusedWindowAttribute as String) else { return nil }
        return AXWindow(element: win, pid: pid)
    }

    var currentFocusedWindow: AXWindow? {
        guard let pid = observedPID, let app = appElement,
              let win = axAttributeElement(app, kAXFocusedWindowAttribute as String) else { return nil }
        return AXWindow(element: win, pid: pid)
    }

    // MARK: - Observer 生命周期

    private func buildObserver(pid: pid_t) {
        var obs: AXObserver?
        let err = AXObserverCreate(pid, AccessibilityService.axCallback, &obs)
        guard err == .success, let observer = obs else {
            AppLog.warn("AXObserverCreate 失败 pid=\(pid) err=\(err)")
            return
        }
        let app = AXUIElementCreateApplication(pid)

        // 关键：common modes，窗口拖拽（event tracking mode）期间通知照常送达
        let source = AXObserverGetRunLoopSource(observer)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        let addErr = AXObserverAddNotification(observer, app, Self.focusedChanged as CFString, ctx)
        if addErr != .success {
            AppLog.warn("AddNotification(focusedWindowChanged) 失败 pid=\(pid) err=\(addErr)")
        }

        self.observer = observer
        self.appElement = app
        self.observedPID = pid
        observeFocusedWindow()
        AppLog.info("开始监听 app pid=\(pid) (\(NSRunningApplication(processIdentifier: pid)?.localizedName ?? "?"))")
    }

    private func teardown() {
        if let obs = observer, let app = appElement {
            AXObserverRemoveNotification(obs, app, Self.focusedChanged as CFString)
        }
        unobserveWindow()
        if let observer = observer {
            let source = AXObserverGetRunLoopSource(observer)
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        observer = nil
        appElement = nil
        observedPID = nil
    }

    private func unobserveWindow() {
        if let obs = observer, let win = observedWindow {
            AXObserverRemoveNotification(obs, win, Self.windowMoved as CFString)
            AXObserverRemoveNotification(obs, win, Self.elementMoved as CFString)
            AXObserverRemoveNotification(obs, win, Self.destroyed as CFString)
        }
        observedWindow = nil
    }

    private func observeFocusedWindow() {
        guard let observer = observer, let app = appElement, let pid = observedPID else { return }
        guard let win = axAttributeElement(app, kAXFocusedWindowAttribute as String) else {
            unobserveWindow()
            return
        }

        // 同一个窗口就不重复挂
        if let old = observedWindow, CFEqual(old, win) { return }
        unobserveWindow()

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        var movedErr = AXObserverAddNotification(observer, win, Self.windowMoved as CFString, ctx)
        if movedErr != .success {
            // 部分应用不支持 windowMoved，退回通用 moved 通知
            movedErr = AXObserverAddNotification(observer, win, Self.elementMoved as CFString, ctx)
        }
        let destroyedErr = AXObserverAddNotification(observer, win, Self.destroyed as CFString, ctx)
        observedWindow = win
        if movedErr != .success && destroyedErr != .success {
            AppLog.warn("窗口通知挂载失败 pid=\(pid) movedErr=\(movedErr)")
        }

        // 同一窗口（如看门狗重建后重新 observe）：不重复报告，避免误取消进行中的拖拽
        if let last = lastReportedWindow, CFEqual(last, win) { return }
        lastReportedWindow = win

        let axWin = AXWindow(element: win, pid: pid)
        DispatchQueue.main.async { [weak self] in
            self?.delegate?(.focusedWindowChanged(axWin))
        }
    }

    // MARK: - C 回调

    private static let axCallback: AXObserverCallback = { observer, element, notification, context in
        guard let context = context else { return }
        let service = Unmanaged<AccessibilityService>.fromOpaque(context).takeUnretainedValue()
        service.handleNotification(notification as String, element: element)
    }

    private func handleNotification(_ name: String, element: AXUIElement) {
        let capturedPID = observedPID
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let pid = capturedPID, self.observedPID == pid else { return }
            switch name {
            case Self.windowMoved, Self.elementMoved:
                self.delegate?(.windowDidMove(AXWindow(element: element, pid: pid)))
            case Self.focusedChanged:
                self.observeFocusedWindow()
            case Self.destroyed:
                self.unobserveWindow()
            default:
                break
            }
        }
    }
}

/// 保持实例存活（AX 回调 context 是 unretained 指针）
enum ActiveInstanceKeeper {
    private static var retained: AccessibilityService?
    static func retain(_ s: AccessibilityService) { retained = s }
    static func release() { retained = nil }
}
