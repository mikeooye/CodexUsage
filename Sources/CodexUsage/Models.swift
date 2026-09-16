import Foundation

struct UsageWindow: Identifiable, Equatable {
    let id: String
    let title: String
    let usedPercent: Double
    let resetsAt: Date?
    var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }
}

enum UsageError: LocalizedError {
    case codexNotFound
    case notLoggedIn
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .codexNotFound: return "找不到 codex CLI。请先安装 Codex CLI，并确保终端中可执行 `codex --version`。"
        case .notLoggedIn: return "Codex 尚未登录 ChatGPT 账号。"
        case .invalidResponse: return "Codex 返回了无法识别的用量数据。"
        case .server(let message): return message
        }
    }
}
