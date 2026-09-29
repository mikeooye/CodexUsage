import Foundation

/// 额度剩余的健康程度，用于状态栏与面板配色。
enum UsageLevel {
    case healthy   // 剩余充足
    case warning   // 剩余偏低
    case critical  // 剩余告急
}

struct UsageWindow: Identifiable, Equatable {
    let id: String
    let title: String
    let usedPercent: Double
    let resetsAt: Date?

    var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }

    /// 例如 `82%`。
    var remainingText: String { "\(Int(remainingPercent.rounded()))%" }

    var level: UsageLevel {
        if remainingPercent >= 50 { return .healthy }
        if remainingPercent >= 20 { return .warning }
        return .critical
    }
}

enum UsageError: LocalizedError {
    case codexNotFound
    case notLoggedIn
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .codexNotFound: return "找不到 codex CLI。请确认已安装 ChatGPT.app（自带 codex），或单独安装 Codex CLI 并确保终端里能执行 `codex --version`。"
        case .notLoggedIn: return "Codex 尚未登录 ChatGPT 账号。"
        case .invalidResponse: return "Codex 返回了无法识别的用量数据。"
        case .server(let message): return message
        }
    }
}
