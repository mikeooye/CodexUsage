import AppKit
import Foundation

actor CodexAppServerClient {
    /// 单次 JSON-RPC 请求的最长等待时间，避免 codex 卡死时永久挂起。
    private static let requestTimeout: Duration = .seconds(15)

    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var timeouts: [Int: Task<Void, Never>] = [:]
    private var buffer = Data()

    func rateLimits() async throws -> [UsageWindow] {
        try await ensureStarted()
        let account = try await request(method: "account/read", params: ["refreshToken": false])
        if account["account"] is NSNull || account["account"] == nil { throw UsageError.notLoggedIn }
        let result = try await request(method: "account/rateLimits/read", params: [:])
        return try parseWindows(result)
    }

    private func ensureStarted() async throws {
        if let process, process.isRunning { return }
        guard let codex = findCodex() else { throw UsageError.codexNotFound }

        let p = Process()
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        p.executableURL = URL(fileURLWithPath: codex)
        p.arguments = ["app-server"]
        p.standardInput = stdin
        p.standardOutput = stdout
        p.standardError = stderr
        try p.run()
        process = p
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading

        // codex 崩溃或被结束时，必须让所有等待中的请求立刻失败，
        // 否则 isLoading 会一直为 true，之后再也刷新不了。
        p.terminationHandler = { [weak self] _ in
            Task { await self?.handleTermination() }
        }

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                Task { await self?.handleTermination() }
                return
            }
            Task { await self?.consume(data) }
        }

        _ = try await request(method: "initialize", params: [
            "clientInfo": ["name": "codex-usage", "title": "Codex Usage", "version": "0.1.0"],
            "capabilities": ["experimentalApi": true]
        ])
        try notify(method: "initialized", params: [:])
    }

    private func request(method: String, params: [String: Any]) async throws -> [String: Any] {
        let id = nextID; nextID += 1
        let payload: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
        try write(payload)
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            timeouts[id] = Task { [weak self] in
                try? await Task.sleep(for: CodexAppServerClient.requestTimeout)
                guard !Task.isCancelled else { return }
                await self?.settle(id: id, with: .failure(UsageError.server("Codex 响应超时。")))
            }
        }
    }

    /// 结束一个等待中的请求；重复调用是安全的。
    private func settle(id: Int, with result: Result<[String: Any], Error>) {
        timeouts.removeValue(forKey: id)?.cancel()
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(with: result)
    }

    private func handleTermination() {
        guard process != nil || !pending.isEmpty else { return }
        process = nil
        input = nil
        output?.readabilityHandler = nil
        output = nil
        buffer.removeAll()
        for id in Array(pending.keys) {
            settle(id: id, with: .failure(UsageError.server("Codex app-server 已退出。")))
        }
    }

    private func notify(method: String, params: [String: Any]) throws {
        try write(["jsonrpc": "2.0", "method": method, "params": params])
    }

    private func write(_ object: [String: Any]) throws {
        guard let input else { throw UsageError.server("Codex app-server 未启动。") }
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try input.write(contentsOf: data)
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[..<newline]
            buffer.removeSubrange(...newline)
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let id = object["id"] as? Int else { continue }
            if let error = object["error"] as? [String: Any] {
                settle(id: id, with: .failure(UsageError.server(error["message"] as? String ?? "Codex 请求失败")))
            } else if let result = object["result"] as? [String: Any] {
                settle(id: id, with: .success(result))
            } else {
                settle(id: id, with: .failure(UsageError.invalidResponse))
            }
        }
    }

    private func parseWindows(_ result: [String: Any]) throws -> [UsageWindow] {
        let snapshot = (result["rateLimits"] as? [String: Any]) ?? (result["rate_limits"] as? [String: Any])
        guard let snapshot else { throw UsageError.invalidResponse }
        var values: [UsageWindow] = []
        if let primary = snapshot["primary"] as? [String: Any],
           let window = makeWindow(primary, id: "primary", fallback: "5 小时") { values.append(window) }
        if let secondary = snapshot["secondary"] as? [String: Any],
           let window = makeWindow(secondary, id: "secondary", fallback: "7 天") { values.append(window) }
        return values
    }

    private func makeWindow(_ json: [String: Any], id: String, fallback: String) -> UsageWindow? {
        let used = (json["usedPercent"] as? NSNumber)?.doubleValue ?? (json["used_percent"] as? NSNumber)?.doubleValue
        guard let used else { return nil }
        let minutes = (json["windowDurationMins"] as? NSNumber)?.intValue ?? (json["window_duration_mins"] as? NSNumber)?.intValue

        let title: String
        if let minutes, minutes >= 10000 { title = "7 天" }
        else if let minutes, minutes >= 240 { title = "5 小时" }
        else { title = fallback }

        let epoch = (json["resetsAt"] as? NSNumber)?.doubleValue ?? (json["resets_at"] as? NSNumber)?.doubleValue
        return UsageWindow(
            id: id,
            title: title,
            usedPercent: used,
            resetsAt: epoch.map { Date(timeIntervalSince1970: $0) }
        )
    }

    private func findCodex() -> String? {
        let fm = FileManager.default

        // 新版 Codex 已集成进 ChatGPT.app，优先复用 ChatGPT 自带的 codex，
        // 这样用户无需额外安装 Codex CLI。
        var candidates = chatGPTAppBundles().flatMap { codexPaths(insideApp: $0) }

        // 兼容独立安装的 Codex CLI。
        candidates += [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            NSHomeDirectory() + "/.local/bin/codex",
            NSHomeDirectory() + "/.npm-global/bin/codex"
        ]
        // nvm 之类的全局安装会按 node 版本分目录。
        candidates += nvmCodexCandidates()

        if let hit = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) {
            return hit
        }

        // 最后再尝试用户 PATH 中的 codex。
        for shell in ["/bin/zsh", "/bin/bash"] {
            if let hit = codexFromLoginShell(shell) { return hit }
        }

        return nil
    }

    /// 一个 app 包内部 codex 可执行文件的候选位置。
    /// 0.156 起 ChatGPT.app 把可执行文件挪进了 `Contents/Resources/codex-cli/`，
    /// 旧布局（`Contents/Resources/codex`）保留在最后兜底。
    private func codexPaths(insideApp app: String) -> [String] {
        [
            app + "/Contents/Resources/codex-cli/bin/codex",
            app + "/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            app + "/Contents/Resources/codex"
        ]
    }

    /// 找出本机所有可能自带 codex 的 app 包路径（ChatGPT.app / ChatGPT Classic.app 等）。
    private func chatGPTAppBundles() -> [String] {
        let fm = FileManager.default
        var apps: [String] = []

        // 先用 bundle id 定位：App 改名或被装到别处（如 ~/Applications）也能命中。
        for id in ["com.openai.chat", "com.openai.codex", "com.openai.codex.cli"] {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                apps.append(url.path)
            }
        }

        let searchDirs = ["/Applications", NSHomeDirectory() + "/Applications"]
        for name in ["ChatGPT.app", "ChatGPT Classic.app"] {
            for dir in searchDirs { apps.append(dir + "/" + name) }
        }

        // 兜底：扫一遍常见安装目录，兼容被改名成别的（例如带版本号的副本）。
        for dir in searchDirs {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let lower = entry.lowercased()
                guard lower.contains("chatgpt") || lower.contains("codex") else { continue }
                apps.append(dir + "/" + entry)
            }
        }

        var seen = Set<String>()
        return apps.filter { seen.insert($0).inserted }
    }

    private func nvmCodexCandidates() -> [String] {
        let root = NSHomeDirectory() + "/.nvm/versions/node"
        guard let versions = try? FileManager.default.contentsOfDirectory(atPath: root) else { return [] }
        // 新版本优先，命中率更高。
        return versions.sorted(by: >).map { root + "/" + $0 + "/bin/codex" }
    }

    /// 在登录 shell 里跑 `command -v codex`，取最后一行真实可执行的结果。
    private func codexFromLoginShell(_ shell: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lc", "command -v codex"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        let fm = FileManager.default
        // 登录脚本（rvm/nvm 等）可能往 stdout 里塞别的东西，只认真正可执行的那一行。
        return raw
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty && fm.isExecutableFile(atPath: $0) }
    }
}
