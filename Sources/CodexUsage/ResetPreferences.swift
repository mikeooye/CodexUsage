import Foundation

/// 用量重置后的提醒偏好；未保存过配置时默认全部关闭。
struct ResetPreferences {
    private enum Key {
        static let notificationEnabled = "CodexUsage.resetNotificationEnabled"
        static let celebrationEnabled = "CodexUsage.resetCelebrationEnabled"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isNotificationEnabled: Bool {
        get { defaults.bool(forKey: Key.notificationEnabled) }
        nonmutating set { defaults.set(newValue, forKey: Key.notificationEnabled) }
    }

    var isCelebrationEnabled: Bool {
        get { defaults.bool(forKey: Key.celebrationEnabled) }
        nonmutating set { defaults.set(newValue, forKey: Key.celebrationEnabled) }
    }
}
