import Foundation

actor CodexAppServerClient {
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
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

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
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
                  let id = object["id"] as? Int,
                  let continuation = pending.removeValue(forKey: id) else { continue }
            if let error = object["error"] as? [String: Any] {
                continuation.resume(throwing: UsageError.server(error["message"] as? String ?? "Codex 请求失败"))
            } else if let result = object["result"] as? [String: Any] {
                continuation.resume(returning: result)
            } else {
                continuation.resume(throwing: UsageError.invalidResponse)
            }
        }
    }

    private func parseWindows(_ result: [String: Any]) throws -> [UsageWindow] {
        let snapshot = (result["rateLimits"] as? [String: Any]) ?? (result["rate_limits"] as? [String: Any])
        guard let snapshot else { throw UsageError.invalidResponse }
        var values: [UsageWindow] = []
        if let primary = snapshot["primary"] as? [String: Any], let window = makeWindow(primary, fallback: "5 小时") { values.append(window) }
        if let secondary = snapshot["secondary"] as? [String: Any], let window = makeWindow(secondary, fallback: "7 天") { values.append(window) }
        return values
    }

    private func makeWindow(_ json: [String: Any], fallback: String) -> UsageWindow? {
        let used = (json["usedPercent"] as? NSNumber)?.doubleValue ?? (json["used_percent"] as? NSNumber)?.doubleValue
        guard let used else { return nil }
        let minutes = (json["windowDurationMins"] as? NSNumber)?.intValue ?? (json["window_duration_mins"] as? NSNumber)?.intValue
        let title: String
        if let minutes, minutes >= 10000 { title = "7 天" }
        else if let minutes, minutes >= 240 { title = "5 小时" }
        else { title = fallback }
        let epoch = (json["resetsAt"] as? NSNumber)?.doubleValue ?? (json["resets_at"] as? NSNumber)?.doubleValue
        return UsageWindow(id: title, title: title, usedPercent: used, resetsAt: epoch.map { Date(timeIntervalSince1970: $0) })
    }

    private func findCodex() -> String? {
        let fm = FileManager.default

        // 新版 Codex 已集成进 ChatGPT.app，优先复用 ChatGPT 自带的 codex。
        // 这样用户无需额外安装 Codex CLI。
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            NSHomeDirectory() + "/Applications/ChatGPT.app/Contents/Resources/codex",

            // 兼容独立安装的 Codex CLI。
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            NSHomeDirectory() + "/.local/bin/codex",
            NSHomeDirectory() + "/.npm-global/bin/codex"
        ]

        if let hit = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) {
            return hit
        }

        // 最后再尝试用户 PATH 中的 codex。
        let shell = Process()
        let pipe = Pipe()
        shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
        shell.arguments = ["-lc", "command -v codex"]
        shell.standardOutput = pipe
        shell.standardError = FileHandle.nullDevice

        do {
            try shell.run()
            shell.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let path, !path.isEmpty, fm.isExecutableFile(atPath: path) else {
            return nil
        }

        return path
    }
}
