import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = UsageStore()
    private let celebrationOverlay = CelebrationOverlay()
    private let resetPreferences = ResetPreferences()
    /// 菜单里那块用量信息（自定义视图，保留进度条）。
    private let usageView = UsageMenuView()
    private var statusItem: NSStatusItem!
    private var launchAtLoginItem: NSMenuItem?
    /// 「刷新」那一项 —— 标题里会带上最后更新时间。
    private var refreshItem: NSMenuItem?
    private var resetNotificationItem: NSMenuItem?
    private var resetCelebrationItem: NSMenuItem?
    /// 登录项状态的缓存。`SMAppService.status` 是同步 XPC：平时 2ms，但系统服务偶尔
    /// 变慢时会变成几百毫秒。它绝不能出现在菜单展开路径上，否则菜单会卡住才弹出。
    private var launchAtLoginEnabled = false
    /// 禁止 App Nap 的活动令牌（见 applicationDidFinishLaunching 里的说明）。
    private var activityToken: NSObjectProtocol?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 菜单栏 App 没有窗口，闲置一会儿就会被系统判为「无事可做」而进入 App Nap：
        // 表现为「隔一阵点一次图标要卡一下菜单才弹出，紧接着再点就很快」。
        // 持有一个 user-initiated 活动令牌即可关掉这个节流；它不阻止系统休眠，
        // 只是让本进程保持正常优先级。
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "菜单栏图标需要随时响应点击"
        )

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.imageScaling = .scaleNone
        // 挂上原生菜单：磨砂背景、无箭头、点面板外自动收起，全部交给系统。
        statusItem.menu = makeMenu()

        observeStore()
        observeAppearance()
        observeWake()

        // 启动时就把登录项状态读进缓存，这样第一次展开菜单也不用同步等 XPC。
        refreshLaunchAtLoginCache()

        if resetPreferences.isNotificationEnabled {
            ResetNotifier.shared.prepare()
        }
        store.onReset = { windows in
            if self.resetPreferences.isNotificationEnabled {
                ResetNotifier.shared.notify(windows)
            }
            if self.resetPreferences.isCelebrationEnabled {
                self.celebrationOverlay.show()
            }
        }

        renderIcon()
        Task { await store.start() }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        // 只读信息区：不设 action，因此不会参与菜单高亮。
        let usageItem = NSMenuItem()
        usageItem.view = usageView
        menu.addItem(usageItem)

        menu.addItem(.separator())

        let refreshItem = NSMenuItem(title: "刷新", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        self.refreshItem = refreshItem

        menu.addItem(.separator())

        let resetNotificationItem = NSMenuItem(
            title: "重置通知",
            action: #selector(toggleResetNotification),
            keyEquivalent: ""
        )
        resetNotificationItem.target = self
        resetNotificationItem.state = resetPreferences.isNotificationEnabled ? .on : .off
        menu.addItem(resetNotificationItem)
        self.resetNotificationItem = resetNotificationItem

        let resetCelebrationItem = NSMenuItem(
            title: "重置庆祝动画",
            action: #selector(toggleResetCelebration),
            keyEquivalent: ""
        )
        resetCelebrationItem.target = self
        resetCelebrationItem.state = resetPreferences.isCelebrationEnabled ? .on : .off
        menu.addItem(resetCelebrationItem)
        self.resetCelebrationItem = resetCelebrationItem

        let loginItem = NSMenuItem(title: "登录时自动启动",
                                   action: #selector(toggleLaunchAtLogin),
                                   keyEquivalent: "")
        loginItem.target = self
        loginItem.state = launchAtLoginEnabled ? .on : .off
        menu.addItem(loginItem)
        launchAtLoginItem = loginItem

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    /// 菜单展开就算一次「点击状态栏」：先刷新一次，
    /// 新数据回来后 renderIcon() 会让这块自定义视图重绘，菜单保持展开。
    ///
    /// 这里只做内存操作 + 起异步任务，任何同步 XPC／磁盘访问都不许有 —— 否则
    /// 菜单会先卡住再弹出。
    func menuWillOpen(_ menu: NSMenu) {
        Task { await store.refresh() }
        // 用户可能在「系统设置 → 登录项」里改过，按缓存的真实状态回显，
        // 同时丢一个后台任务去更新缓存（供下一次展开使用）。
        launchAtLoginItem?.state = launchAtLoginEnabled ? .on : .off
        refreshLaunchAtLoginCache()
    }

    /// 在后台线程读登录项状态，再回主线程更新缓存与勾选态。
    private func refreshLaunchAtLoginCache() {
        Task.detached(priority: .utility) { [weak self] in
            let enabled = LaunchAtLogin.isEnabled
            // 先把 weak 解包成本地常量，避免在内层并发闭包里引用被捕获的 var。
            guard let self else { return }
            await MainActor.run { self.applyLaunchAtLogin(enabled) }
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginEnabled = enabled
        launchAtLoginItem?.state = enabled ? .on : .off
    }

    @objc private func refreshNow() {
        Task { await store.refresh() }
    }

    @objc private func toggleResetNotification() {
        let enabled = !resetPreferences.isNotificationEnabled
        resetPreferences.isNotificationEnabled = enabled
        resetNotificationItem?.state = enabled ? .on : .off
        if enabled {
            ResetNotifier.shared.prepare()
        }
    }

    @objc private func toggleResetCelebration() {
        let enabled = !resetPreferences.isCelebrationEnabled
        resetPreferences.isCelebrationEnabled = enabled
        resetCelebrationItem?.state = enabled ? .on : .off
    }

    @objc private func toggleLaunchAtLogin() {
        guard LaunchAtLogin.isAvailable else {
            presentAlert(title: "无法设置开机自启动",
                         message: "这个开关只在以 .app 形式运行时可用；直接运行可执行文件时系统不允许注册登录项。")
            return
        }

        // 这里已经是菜单关闭之后，同步读写 XPC 不影响菜单弹出速度。
        let enabling = !launchAtLoginEnabled
        do {
            try LaunchAtLogin.setEnabled(enabling)
        } catch {
            presentAlert(
                title: "设置开机自启动失败",
                message: """
                \(error.localizedDescription)

                常见原因：App 不在启动磁盘上（例如放在外置硬盘或构建目录里），\
                或签名不被系统接受。建议先安装到 /Applications 再开启。
                """
            )
            refreshLaunchAtLoginCache()
            return
        }

        applyLaunchAtLogin(LaunchAtLogin.isEnabled)
        if enabling, LaunchAtLogin.requiresApproval {
            presentAlert(
                title: "还需要你批准一次",
                message: "已登记为登录项，但被系统标记为「需要批准」。请在「系统设置 → 通用 → 登录项」里允许 Codex Usage。",
                offerSystemSettings: true
            )
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func presentAlert(title: String, message: String, offerSystemSettings: Bool = false) {
        // 菜单刚关闭，把 App 提到前面，否则无边框的 accessory 应用可能把弹窗留在后面。
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        if offerSystemSettings {
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "稍后")
            if alert.runModal() == .alertFirstButtonReturn {
                LaunchAtLogin.openSystemSettingsLoginItems()
            }
        } else {
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }

    // MARK: - 数据

    private func observeStore() {
        store.$windows
            .combineLatest(store.$error)
            // `@Published` 在赋值前发出通知，这里切到下一轮 runloop，
            // 保证 renderIcon() 读到的已经是新值。不要把 receive(on:) 去掉。
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.renderIcon() }
            .store(in: &cancellables)
    }

    /// 切换浅色/深色外观时重新绘制，保证菜单栏图标与菜单配色跟着系统走。
    private func observeAppearance() {
        NSApp.publisher(for: \.effectiveAppearance)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.renderIcon() }
            .store(in: &cancellables)
    }

    /// 休眠唤醒后立刻刷新，避免显示睡眠前的旧数据。
    private func observeWake() {
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { await self?.store.refresh() }
            }
            .store(in: &cancellables)
    }

    private func renderIcon() {
        let hasError = store.error != nil
        statusItem.button?.image = StatusBarIcon.image(windows: store.windows, hasError: hasError)
        statusItem.button?.toolTip = store.toolTip
        usageView.update(windows: store.windows, error: store.error)
        // 最后更新时间挂在「刷新」那一行：刷新  09:35        ⌘R
        refreshItem?.title = store.lastUpdated
            .map { "刷新  " + $0.formatted(date: .omitted, time: .shortened) } ?? "刷新"
    }
}
