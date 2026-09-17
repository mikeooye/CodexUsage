import AppKit

/// 纯 AppKit 入口。
///
/// 这里刻意不使用 SwiftUI 的 `App` / `Scene`：之前用 `Settings { EmptyView() }` 占位，
/// 会留下一个 900×450 的空白窗口。菜单栏 App 不需要任何窗口，直接自己跑 NSApplication。
@main
struct CodexUsageMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        // 没有 Dock 图标、没有主菜单，只留菜单栏图标。
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
