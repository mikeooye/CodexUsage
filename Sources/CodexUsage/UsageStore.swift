import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published var windows: [UsageWindow] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var lastUpdated: Date?

    private let client = CodexAppServerClient()
    private var loop: Task<Void, Never>?

    var menuTitle: String {
        guard !windows.isEmpty else { return "Codex" }
        return windows.map { "\($0.title) \(Int($0.remainingPercent.rounded()))%" }.joined(separator: " · ")
    }

    func start() async {
        guard loop == nil else { return }
        await refresh()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                await self?.refresh()
            }
        }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true; defer { isLoading = false }
        do {
            windows = try await client.rateLimits()
            lastUpdated = Date(); error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
