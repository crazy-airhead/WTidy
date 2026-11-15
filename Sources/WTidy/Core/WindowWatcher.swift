import Foundation
import AppKit
import CoreGraphics

/// 拖拽检测状态机。
///
/// 输入：AX 的 windowMoved 通知 + 33ms 轮询（光标位置 / 鼠标按键状态）。
/// 窗口拖拽期间全局鼠标监听不可靠，因此用 CGEventSource 轮询按钮状态——
/// 这是 macOS 分屏工具的成熟做法。
final class WindowWatcher {
    enum Phase {
        case idle          // 未在拖拽
        case watching      // 按住窗口且开始移动，未达阈值
        case active        // 超过阈值，Overlay 已展示
    }

    private(set) var phase: Phase = .idle

    /// 判定拖拽成立的阈值：至少 2 次 moved 事件，累计位移 ≥ 24pt
    static let moveCountThreshold = 2
    static let moveDistanceThreshold: CGFloat = 24

    private(set) var window: AXWindow?
    private(set) var originalFrame: CGRect?   // 拖拽开始时的 frame（恢复用）
    private var firstFrame: CGRect?
    private var moveCount = 0

    private var pollTimer: Timer?
    private var leftDownLastTick = false

    // 每次拖拽会话的编号，便于日志追踪
    private var dragSession = 0

    var isActive: Bool { phase == .active }

    /// 系统级鼠标左键是否按下
    static var isLeftButtonDown: Bool {
        CGEventSource.buttonState(.combinedSessionState, button: .left)
    }

    // MARK: - 输入：moved 通知

    func registerMove(_ w: AXWindow, frame: CGRect) {
        guard w.canSnap else {
            // 不可吸附的窗口（面板/全屏）出现移动：若正在拖拽它则取消
            if phase != .idle, let cur = window, CFEqual(cur.ref, w.ref) {
                cancel()
            }
            return
        }

        if phase == .idle {
            guard WindowWatcher.isLeftButtonDown else { return } // 非拖拽位移（程序挪窗）
            if CFEqual(w.ref, (window?.ref ?? w.ref)) == false || window == nil {
                // 新窗口：重置会话
                window = w
                originalFrame = frame
                firstFrame = frame
                moveCount = 1
                phase = .watching
                dragSession += 1
                startPolling()   // watching 期也盯左键：松手即丢弃会话，不留旧 firstFrame 给下次拖拽
                return
            }
        }

        guard let cur = window, CFEqual(cur.ref, w.ref) else {
            // 换了窗口：重置
            reset()
            registerMove(w, frame: frame)
            return
        }

        // 拖拽进展要求左键仍按住：松手后才到达的收尾事件（落位回弹等）不计入判定
        if !WindowWatcher.isLeftButtonDown {
            if phase == .active {
                finishDrag()   // 已激活：等同松手结束，照常评估吸附
            } else {
                AppLog.info("未达阈值即松手，丢弃 session=\(dragSession)")
                reset()
            }
            return
        }

        moveCount += 1
        guard let first = firstFrame else { return }
        let dist = hypot(frame.midX - first.midX, frame.midY - first.midY)
        if phase == .watching,
           moveCount >= WindowWatcher.moveCountThreshold,
           dist >= WindowWatcher.moveDistanceThreshold {
            phase = .active
            AppLog.info("拖拽判定成立 session=\(dragSession) 窗口='\(w.title ?? "?")' 位移=\(Int(dist))pt")
            delegate?.dragDidBegin(w, originalFrame: originalFrame ?? frame)
            startPolling()
        }
    }

    // MARK: - 轮询

    private func startPolling() {
        stopPolling()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func tick() {
        let leftDown = WindowWatcher.isLeftButtonDown
        leftDownLastTick = leftDown
        guard leftDown else {
            if phase == .active {
                // 松手 → 结束拖拽，交给 Overlay 决定吸附与否
                finishDrag()
            } else {
                // watching 期松手：丢弃未成型的会话，避免旧 firstFrame 污染下次拖拽
                AppLog.info("未达阈值即松手，丢弃 session=\(dragSession)")
                reset()
            }
            return
        }
        guard phase == .active else { return }
        delegate?.dragTick(cursor: NSEvent.mouseLocation)
    }

    private func finishDrag() {
        stopPolling()
        let cursor = NSEvent.mouseLocation
        let session = dragSession
        let ended = phase == .active
        phase = .idle
        let win = window
        window = nil
        firstFrame = nil
        moveCount = 0
        if ended {
            AppLog.info("拖拽结束 session=\(session)")
            delegate?.dragDidEnd(cursor: cursor, window: win)
        }
    }

    func cancel() {
        guard phase != .idle else { return }
        stopPolling()
        AppLog.info("拖拽取消 session=\(dragSession)")
        phase = .idle
        window = nil
        firstFrame = nil
        moveCount = 0
        delegate?.dragDidCancel()
    }

    private func reset() {
        stopPolling()
        phase = .idle
        window = nil
        firstFrame = nil
        moveCount = 0
    }

    weak var delegate: WindowWatcherDelegate?
}

protocol WindowWatcherDelegate: AnyObject {
    /// 拖拽判定成立（达到阈值），应展示 Overlay
    func dragDidBegin(_ window: AXWindow, originalFrame: CGRect)
    /// 拖拽进行中（30Hz），光标位置更新
    func dragTick(cursor: CGPoint)
    /// 松手，光标位置在此；据此决定吸附或放弃
    func dragDidEnd(cursor: CGPoint, window: AXWindow?)
    /// 拖拽被取消（窗口不可吸附 / 焦点切换）
    func dragDidCancel()
}
