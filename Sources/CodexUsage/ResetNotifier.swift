import UserNotifications

/// 把「额度已重置」发成系统通知。
@MainActor
final class ResetNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ResetNotifier()

    /// 直接跑裸二进制（例如 `swift run`）时没有 bundle id，`UNUserNotificationCenter` 不可用。
    private let isAvailable = Bundle.main.bundleIdentifier != nil

    private override init() { super.init() }

    /// 请求通知权限；只在第一次真正弹窗，之后重复调用是空操作。
    func prepare() {
        guard isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notify(_ windows: [UsageWindow]) {
        guard isAvailable, !windows.isEmpty else { return }
        let center = UNUserNotificationCenter.current()

        for window in windows {
            let content = UNMutableNotificationContent()
            content.title = "Codex \(window.title)额度已重置"
            content.body = "当前剩余 \(window.remainingText)"
            content.sound = .default

            // 同一个周期复用标识，新的重置提醒会替换旧的，不会堆一屏。
            let request = UNNotificationRequest(
                identifier: "reset-\(window.id)",
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }

    /// 面板正开着（App 在前台）时也要把横幅显示出来。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
