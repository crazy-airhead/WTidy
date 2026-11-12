import AppKit

/// 透明、非激活、完全忽略鼠标的高层级窗口——纯视觉层，不干扰系统拖拽。
final class OverlayWindow: NSPanel {
    let overlayView: OverlayView
    let screenNumber: CGDirectDisplayID

    init(screen: NSScreen) {
        screenNumber = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
        overlayView = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)

        // 拖拽中的窗口在本层之上（用户能看到自己拖的窗口），
        // overlay 盖住其余桌面内容
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        contentView = overlayView
    }

    func presentOverlay() {
        guard !isVisible else { return }
        alphaValue = 1
        orderFrontRegardless()
    }

    func dismissOverlay() {
        guard isVisible else { return }
        orderOut(nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }
}
