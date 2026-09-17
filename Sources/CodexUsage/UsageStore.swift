import Foundation

@MainActor
final class UsageStore: ObservableObject {
    /// 自动刷新间隔。
    static let refreshInterval: Duration = .seconds(60)

    @Published var windows: [UsageWindow] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var lastUpdated: Date?

    /// 检测到额度重置时回调（由 App 层转成系统通知）。
    var onReset: (@MainActor ([UsageWindow]) -> Void)?

    private let client = CodexAppServerClient()
    private var loop: Task<Void, Never>?
    private var resetDetector = ResetDetector()

    /// 状态栏悬停提示。
    var toolTip: String {
        guard !windows.isEmpty else { return error ?? "Codex 用量" }
        var lines = windows.map { "\($0.title)剩余 \($0.remainingText)" }
        if let lastUpdated {
            lines.append("更新于 \(lastUpdated.formatted(date: .omitted, time: .shortened))")
        }
        if let error { lines.append(error) }
        return lines.joined(separator: "\n")
    }

    func start() async {
        guard loop == nil else { return }
        await refresh()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: UsageStore.refreshInterval)
                await self?.refresh()
            }
        }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true; defer { isLoading = false }
        do {
            let latest = try await client.rateLimits()
            windows = latest
            lastUpdated = Date(); error = nil
            let resets = resetDetector.note(latest)
            if !resets.isEmpty { onReset?(resets) }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
