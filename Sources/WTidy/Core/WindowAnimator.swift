import Foundation
import AppKit

/// 吸附动画（对齐原版 AnimateWindows）：
/// - 同屏：位置与尺寸插值渐进
/// - 跨屏（对齐原版的多阶段移动，避免大尺寸窗口跨屏时被目标屏裁剪）：
///   1) 先移动到目标屏可用区原点（留出调整空间）
///   2) 调整到目标尺寸
///   3) 移动到最终位置
/// AX 写入为同步往返，动画在专用后台队列分步执行，不阻塞主线程。
enum WindowAnimator {
    private static let queue = DispatchQueue(label: "com.allblue.wtidy.animate", qos: .userInteractive)

    /// 动画或直接应用目标 frame（拿不到当前 frame 时直接落位）
    static func apply(_ win: AXWindow, to target: CGRect, completion: (() -> Void)? = nil) {
        guard let from = win.nsFrame else {
            win.setNSFrame(target)
            DispatchQueue.main.async(execute: completion ?? {})
            return
        }

        let fromCenter = CGPoint(x: from.midX, y: from.midY)
        let crossingScreen = !(NSScreen.screens.first { $0.frame.contains(fromCenter) }?
            .frame.contains(CGPoint(x: target.midX, y: target.midY)) ?? true)

        queue.async {
            if crossingScreen {
                animateCrossScreen(win, from: from, to: target)
            } else {
                animateInterpolated(win, from: from, to: target)
            }
            // 最终以校正写法收尾（部分应用 resize 后会自行挪窗）
            win.setNSFrame(target)
            DispatchQueue.main.async(execute: completion ?? {})
        }
    }

    /// 同屏插值：位置与尺寸同步渐进
    private static func animateInterpolated(_ win: AXWindow, from: CGRect, to: CGRect,
                                            steps: Int = Design.Motion.sameScreenSteps) {
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let eased = t * t * (3 - 2 * t)   // smoothstep 缓动
            let frame = interpolate(from, to, t: eased)
            win.setNSFrame(frame)
            Thread.sleep(forTimeInterval: Design.Motion.frameInterval)
        }
    }

    /// 跨屏三阶段（原版："Move to interim origin with room to resize" → resize → "Move to final position"）
    private static func animateCrossScreen(_ win: AXWindow, from: CGRect, to: CGRect,
                                           steps: Int = Design.Motion.crossScreenSteps) {
        guard let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: to.midX, y: to.midY)) })
                ?? NSScreen.main else {
            win.setNSFrame(to)
            return
        }
        let vf = targetScreen.visibleFrame

        // 阶段 1：移动到目标屏可用区左上（保留调整空间），尺寸渐缩到不超过目标屏
        let interimSize = CGSize(width: min(from.width, vf.width),
                                 height: min(from.height, vf.height))
        let interim = CGRect(origin: CGPoint(x: vf.minX, y: vf.maxY - interimSize.height),
                             size: interimSize)
        animateInterpolated(win, from: from, to: interim, steps: steps)

        // 阶段 2：在原点处调整到目标尺寸
        let resized = CGRect(origin: interim.origin, size: to.size)
        win.setNSFrame(resized)
        Thread.sleep(forTimeInterval: Design.Motion.crossScreenResizeHold)

        // 阶段 3：移动到最终位置
        animateInterpolated(win, from: resized, to: to, steps: steps)
    }

    private static func interpolate(_ a: CGRect, _ b: CGRect, t: CGFloat) -> CGRect {
        CGRect(x: a.minX + (b.minX - a.minX) * t,
               y: a.minY + (b.minY - a.minY) * t,
               width: a.width + (b.width - a.width) * t,
               height: a.height + (b.height - a.height) * t)
    }
}
