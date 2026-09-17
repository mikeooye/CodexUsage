import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = UsageStore()
    /// 菜单里那块用量信息（自定义视图，保留进度条）。
    private let usageView = UsageMenuView()
    private var statusItem: NSStatusItem!
    private var launchAtLoginItem: NSMenuItem?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.imageScaling = .scaleNone
        // 挂上原生菜单：磨砂背景、无箭头、点面板外自动收起，全部交给系统。
        statusItem.menu = makeMenu()

        observeStore()
        observeAppearance()
        observeWake()

        ResetNotifier.shared.prepare()
        store.onReset = { windows in
            ResetNotifier.shared.notify(windows)
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

        let loginItem = NSMenuItem(title: "登录时自动启动",
                                   action: #selector(toggleLaunchAtLogin),
                                   keyEquivalent: "")
        loginItem.target = self
        loginItem.state = LaunchAtLogin.isEnabled ? .on : .off
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
    func menuWillOpen(_ menu: NSMenu) {
        Task { await store.refresh() }
        // 用户可能在「系统设置 → 登录项」里改过，每次展开都按真实状态回显。
        launchAtLoginItem?.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    @objc private func refreshNow() {
        Task { await store.refresh() }
    }

    @objc private func toggleLaunchAtLogin() {
        guard LaunchAtLogin.isAvailable else {
            presentAlert(title: "无法设置开机自启动",
                         message: "这个开关只在以 .app 形式运行时可用；直接运行可执行文件时系统不允许注册登录项。")
            return
        }

        let enabling = !LaunchAtLogin.isEnabled
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
            launchAtLoginItem?.state = LaunchAtLogin.isEnabled ? .on : .off
            return
        }

        launchAtLoginItem?.state = LaunchAtLogin.isEnabled ? .on : .off
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
        usageView.update(windows: store.windows, error: store.error, lastUpdated: store.lastUpdated)
    }
}
