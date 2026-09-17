import Foundation

/// 判断额度周期是否刚刚重置 —— 纯逻辑，便于单独验证。
///
/// 主判据是 `resetsAt` 向后滚动（窗口翻篇），这比「百分比回升」可靠得多：
/// 用量在同一窗口内只会单调累积，不会无缘无故涨回去。只有当服务端没给重置时间时，
/// 才退化为「剩余量明显回升」这一兜底判据。
struct ResetDetector {
    /// 只有上一轮真的用过额度（剩余低于该值）才值得提醒，
    /// 否则未使用过的窗口每 5 小时翻篇一次，会变成纯噪音。
    static let meaningfulUsageThreshold: Double = 95
    /// `resetsAt` 至少向后移动这么久才算翻篇，避免时间戳秒级抖动导致误报。
    static let rolloverTolerance: TimeInterval = 120
    /// 兜底判据：剩余量回升超过这么多个百分点，视为重置。
    static let reboundThreshold: Double = 15

    struct State: Codable, Equatable {
        var remainingPercent: Double
        var resetsAt: Date?
    }

    private let defaults: UserDefaults
    private let storageKey: String
    private(set) var previous: [String: State]

    init(defaults: UserDefaults = .standard,
         storageKey: String = "CodexUsage.lastWindowState") {
        self.defaults = defaults
        self.storageKey = storageKey
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: State].self, from: data) {
            previous = decoded
        } else {
            previous = [:]
        }
    }

    /// 记录本次读数，并返回其中发生重置的周期。
    mutating func note(_ windows: [UsageWindow]) -> [UsageWindow] {
        var resets: [UsageWindow] = []
        // 以旧状态为基础：某个周期偶发缺失时保留基线，等它回来还能继续比对。
        var current = previous

        for window in windows {
            let state = State(remainingPercent: window.remainingPercent, resetsAt: window.resetsAt)
            current[window.id] = state
            // 首次见到这个窗口（或刚启动且没有历史记录）时只建立基线，不提醒。
            guard let last = previous[window.id] else { continue }
            if Self.isReset(from: last, to: state) { resets.append(window) }
        }

        previous = current
        persist()
        return resets
    }

    static func isReset(from last: State, to current: State) -> Bool {
        guard last.remainingPercent < meaningfulUsageThreshold else { return false }

        if let before = last.resetsAt, let after = current.resetsAt {
            return after.timeIntervalSince(before) > rolloverTolerance
        }
        return current.remainingPercent - last.remainingPercent >= reboundThreshold
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(previous) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
