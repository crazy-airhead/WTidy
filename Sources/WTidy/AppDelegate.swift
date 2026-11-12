import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let overlay = OverlayController()
    let status = StatusMenuController()

    private var watchdog: Timer?
    private var watchdogTickCount = 0
    private var lastKnownTrusted = false
    private var hotkeyRefreshDebounce: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        AppLog.info("WTidy \(version)(\(build)) 启动 · \(ProcessInfo.processInfo.operatingSystemVersionString) · \(Host.current().name ?? "?")")

        // 历史遗留迁移：旧默认 512 / 旧建议值 880 → 1320（图标基准 150pt 所需总宽）
        let legacyMaxWidth = UserDefaults.standard.object(forKey: Prefs.Keys.stripMaxWidth) as? Double
        if legacyMaxWidth == 512 || legacyMaxWidth == 880 {
            Prefs.stripMaxWidth = 1320
            AppLog.info("迁移最大宽度 \(legacyMaxWidth!) → 1320")
        }

        status.configure(hooks: .init(
            openSettings: { [weak self] in self?.openSettings() },
            requestPermissions: { [weak self] in self?.requestPermissions() },
            applyLayoutByID: { [weak self] id in
                _ = self?.overlay.applyLayoutByID(id)
            },
            restoreAllWindows: { [weak self] in
                self?.overlay.restoreAllWindows()
            },
            moveToActiveDisplay: { [weak self] in
                _ = self?.overlay.moveFrontmostToActiveDisplay()
            }
        ))
        status.setVisible(Prefs.showStatusIcon)

        if let last = Prefs.lastSnap {
            status.setLastSnap(last)
        }

        overlay.onSnapApplied = { [weak self] desc in
            let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            let full = "\(desc) · \(time)"
            Prefs.lastSnap = full
            self?.status.setLastSnap(full)
        }

        overlay.start()

        HotkeyManager.shared.actionHandler = { [weak self] action in
            self?.overlay.snapFrontmost(action)
        }
        HotkeyManager.shared.layoutShortcutHandler = { [weak self] layoutID in
            _ = self?.overlay.applyLayoutByID(layoutID)
        }
        HotkeyManager.shared.refresh()

        registerWorkspaceNotifications()
        startWatchdog()

        NotificationCenter.default.addObserver(
            forName: .prefsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.status.setVisible(Prefs.showStatusIcon)
            // 防抖：滑杆连续滑动等场景会高频触发，Carbon 重注册开销大
            // （曾把滑杆拖拽跟踪循环卡死），200ms 合并一次
            self?.hotkeyRefreshDebounce?.invalidate()
            let timer = Timer(timeInterval: 0.2, repeats: false) { _ in
                HotkeyManager.shared.refresh()
            }
            RunLoop.main.add(timer, forMode: .common)
            self?.hotkeyRefreshDebounce = timer
        }

        lastKnownTrusted = AccessibilityService.isTrusted
        if !lastKnownTrusted || !Prefs.onboardingDone {
            OnboardingWindowController.shared.present()
        }
        status.update(state: lastKnownTrusted ? .ok : .noPermission)
        AppLog.info("启动完成 trusted=\(lastKnownTrusted)")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !AccessibilityService.isTrusted {
            OnboardingWindowController.shared.present()
        } else {
            openSettings()
        }
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: - 看门狗
    //
    // 治原版病根：2017 年的老代码在睡眠唤醒 / 显示器插拔 / 切前台后丢监听且不自愈。
    // 这里三层防护：事件驱动重挂 + 10s 心跳检查 + 60s 无条件重建。

    private func startWatchdog() {
        let timer = Timer(timeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.watchdogTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    private func watchdogTick() {
        watchdogTickCount += 1

        let trusted = AccessibilityService.isTrusted
        if trusted != lastKnownTrusted {
            AppLog.info("权限状态变化 trusted=\(trusted)")
            lastKnownTrusted = trusted
            if trusted {
                overlay.ax.retargetFrontmost(force: true)
                HotkeyManager.shared.refresh()
            } else if !Prefs.onboardingDone || true {
                // 授权被收回：弹引导（已完成过引导的用户也提醒一次）
                OnboardingWindowController.shared.present()
            }
            status.update(state: trusted ? .ok : .noPermission)
        }

        // 事件驱动重挂兜底：前台 app 变了就重挂
        overlay.ax.retargetFrontmost()

        // 每 60s 无条件重建监听链，确保静默失灵可自愈
        if watchdogTickCount % 6 == 0 {
            overlay.ax.forceRebuild()
            AppLog.info("心跳：watchdog ok trusted=\(trusted) pid=\(overlay.ax.observedPID.map(String.init) ?? "nil")")
        }
    }

    // MARK: - 工作区通知（事件驱动的重挂时机）

    private func registerWorkspaceNotifications() {
        let ws = NSWorkspace.shared
        let center = ws.notificationCenter

        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.overlay.ax.retargetFrontmost()
        }
        // 睡眠唤醒：老应用的经典死亡场景
        center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            AppLog.info("屏幕唤醒 → 重建监听")
            self?.overlay.ax.forceRebuild()
        }
        // 显示器热插拔
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            AppLog.info("显示器配置变化 → 清缓存重建")
            self?.overlay.screenConfigurationChanged()
            self?.overlay.ax.forceRebuild()
        }
        // Space 切换
        center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.overlay.ax.retargetFrontmost()
        }
    }

    // MARK: - 菜单动作

    @objc private func openSettings() {
        SettingsWindowController.shared.present()
    }

    @objc private func requestPermissions() {
        AccessibilityService.requestTrust()
        OnboardingWindowController.shared.present()
    }

    @objc private func restart() {
        AppLog.info("用户请求重启")
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-c", "sleep 0.6; open \"\(bundlePath)\""]
        do {
            try task.run()
            NSApp.terminate(nil)
        } catch {
            AppLog.error("重启失败: \(error)")
        }
    }
}
