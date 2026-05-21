import Foundation
import Darwin

/// Spawns `codex app-server` and exchanges JSON-RPC messages over stdio
/// (newline-delimited JSON, not LSP-style Content-Length framing) to read the
/// account rate limits the Codex CLI itself receives from chatgpt.com.
///
/// The Codex CLI brokers OAuth + token refresh — we never read `~/.codex/auth.json`
/// ourselves, so no TCC dialog. TCC attribution flows to the `codex` binary via
/// `DisclaimingSpawn`.
public struct CodexAppServerClient: Sendable {
    public static let methodInitialize = "initialize"
    public static let methodRateLimits = "account/rateLimits/read"

    public let executableURL: URL
    public let environment: [String: String]
    public let timeoutSeconds: TimeInterval
    public let clientName: String
    public let clientVersion: String

    public init(
        executableURL: URL,
        environment: [String: String] = EnvironmentResolver.defaultEnvironment(),
        timeoutSeconds: TimeInterval = 15,
        clientName: String = "C5h",
        clientVersion: String = "0.3.0"
    ) {
        self.executableURL = executableURL
        self.environment = environment
        self.timeoutSeconds = timeoutSeconds
        self.clientName = clientName
        self.clientVersion = clientVersion
    }

    /// Fetches the account rate limits as raw JSON-RPC `result` payload (the
    /// `GetAccountRateLimitsResponse` shape).
    public func fetchRateLimitsResult() async throws -> String {
        try await Task.detached(priority: .utility) {
            try fetchRateLimitsResultBlocking()
        }.value
    }

    private func fetchRateLimitsResultBlocking() throws -> String {
        let launched: LaunchedProcess
        do {
            launched = try DisclaimingSpawn.launch(
                executableURL: executableURL,
                arguments: ["app-server"],
                environment: environment,
                workingDirectory: nil,
                stdin: .pipe,
                stdout: .pipe,
                stderr: .devNull
            )
        } catch {
            throw C5hError.processLaunchFailed(String(describing: error))
        }

        guard let stdinHandle = launched.stdinHandle,
              let stdoutHandle = launched.stdoutHandle else {
            launched.terminate()
            _ = launched.waitBlocking()
            throw C5hError.processLaunchFailed("codex app-server: missing stdio pipes")
        }

        defer {
            if launched.isRunning {
                launched.terminate()
            }
            _ = launched.waitBlocking()
            try? stdinHandle.close()
            try? stdoutHandle.close()
        }

        let stdoutFD = stdoutHandle.fileDescriptor
        let flags = fcntl(stdoutFD, F_GETFL, 0)
        if flags >= 0 { _ = fcntl(stdoutFD, F_SETFL, flags | O_NONBLOCK) }

        let initializeID = 1
        let rateLimitsID = 2

        try writeMessage([
            "jsonrpc": "2.0",
            "id": initializeID,
            "method": Self.methodInitialize,
            "params": [
                "clientInfo": [
                    "name": clientName,
                    "version": clientVersion
                ]
            ]
        ], to: stdinHandle)

        var buffer = ""
        let deadline = Date().addingTimeInterval(timeoutSeconds)

        guard try readResponse(id: initializeID, buffer: &buffer, fd: stdoutFD, deadline: deadline) != nil else {
            throw C5hError.processLaunchFailed("codex app-server: no initialize response")
        }

        try writeMessage([
            "jsonrpc": "2.0",
            "id": rateLimitsID,
            "method": Self.methodRateLimits,
            "params": [:] as [String: String]
        ], to: stdinHandle)

        guard let result = try readResponse(id: rateLimitsID, buffer: &buffer, fd: stdoutFD, deadline: deadline) else {
            throw C5hError.processLaunchFailed("codex app-server: no rate-limits response within timeout")
        }
        return result
    }

    private func writeMessage(_ body: [String: Any], to handle: FileHandle) throws {
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        var line = data
        line.append(0x0A)
        try handle.write(contentsOf: line)
    }

    /// Reads NDJSON messages until one matches the request `id`. Returns the raw
    /// `result` JSON object string. Notifications and other-id responses are
    /// discarded.
    private func readResponse(
        id targetID: Int,
        buffer: inout String,
        fd: Int32,
        deadline: Date
    ) throws -> String? {
        while Date() < deadline {
            if let line = takeLine(from: &buffer) {
                if let result = try matchResult(in: line, id: targetID) {
                    return result
                }
                continue
            }

            var bytes = [UInt8](repeating: 0, count: 4096)
            let count = Darwin.read(fd, &bytes, bytes.count)
            if count > 0 {
                buffer.append(String(decoding: bytes.prefix(count), as: UTF8.self))
                continue
            }
            if count == 0 {
                if let line = takeLine(from: &buffer) {
                    if let result = try matchResult(in: line, id: targetID) {
                        return result
                    }
                    continue
                }
                return nil
            }
            if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR {
                usleep(50_000)
                continue
            }
            throw C5hError.processLaunchFailed("codex app-server: read errno \(errno)")
        }
        return nil
    }

    private func takeLine(from buffer: inout String) -> String? {
        guard let newlineRange = buffer.range(of: "\n") else { return nil }
        let line = String(buffer[..<newlineRange.lowerBound])
        buffer.removeSubrange(buffer.startIndex..<newlineRange.upperBound)
        return line
    }

    private func matchResult(in line: String, id targetID: Int) throws -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard let idValue = obj["id"] as? Int, idValue == targetID else {
            return nil
        }
        if let err = obj["error"] as? [String: Any] {
            let message = (err["message"] as? String) ?? "unknown JSON-RPC error"
            throw C5hError.processLaunchFailed("codex app-server: \(message)")
        }
        guard let result = obj["result"] else {
            throw C5hError.processLaunchFailed("codex app-server: response missing result")
        }
        let resultData = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        return String(decoding: resultData, as: UTF8.self)
    }
}
