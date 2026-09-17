import Foundation
import ServiceManagement

/// 登录时自动启动（macOS 13+ 的 `SMAppService`）。
///
/// 注意：系统会把「登录项」记成 app 包的**当前路径**。所以务必先把 App 放到
/// 稳定位置（`/Applications`）再开启，否则一旦移动 App 或重新构建删掉
/// 构建目录里的包，自启动就会失效。
enum LaunchAtLogin {
    /// 直接跑裸二进制（例如 `swift run`）时没有 bundle，系统不允许注册登录项。
    static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    static var status: SMAppService.Status {
        guard isAvailable else { return .notFound }
        return SMAppService.mainApp.status
    }

    static var isEnabled: Bool { status == .enabled }

    /// 已注册但被用户在系统设置里关掉了，需要用户手动批准。
    static var requiresApproval: Bool { status == .requiresApproval }

    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }
    }

    static func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
