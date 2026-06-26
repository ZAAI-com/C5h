import Foundation
import Darwin

/// Spawns `codex app-server` and exchanges JSON-RPC messages over stdio
/// (newline-delimited JSON, not LSP-style Content-Length framing) to read the
/// account rate limits the Codex CLI itself receives from chatgpt.com.
///
/// The Codex CLI brokers OAuth + token refresh: we never read `~/.codex/auth.json`
/// ourselves, so no TCC dialog. TCC attribution flows to the `codex` binary via
/// `DisclaimingSpawn`.
public struct CodexAppServerClient: Sendable {
    public static let methodInitialize = "initialize"
    public static let methodRateLimits = "account/rateLimits/read"

    public let executableURL: URL
    public let environment: [String: String]
    public let timeoutSeconds: TimeInterval
    /// Cold-starting `codex app-server` (first spawn, or after the binary is
    /// paged out) can take longer than a single rate-limits read, so the
    /// `initialize` handshake gets its own, more generous budget.
    public let initializeTimeoutSeconds: TimeInterval
    public let clientName: String
    public let clientVersion: String

    public init(
        executableURL: URL,
        environment: [String: String] = EnvironmentResolver.defaultEnvironment(),
        timeoutSeconds: TimeInterval = 15,
        initializeTimeoutSeconds: TimeInterval = 30,
        clientName: String = "C5h",
        clientVersion: String = "0.4.0"
    ) {
        self.executableURL = executableURL
        self.environment = environment
        self.timeoutSeconds = timeoutSeconds
        self.initializeTimeoutSeconds = initializeTimeoutSeconds
        self.clientName = clientName
        self.clientVersion = clientVersion
    }

    /// Fetches the account rate limits as raw JSON-RPC `result` payload (the
    /// `GetAccountRateLimitsResponse` shape).
    public func fetchRateLimitsResult() async throws -> String {
        // Unstructured Task (not detached) so caller cancellation can propagate
        // and tear down the codex app-server subprocess promptly.
        try await Task(priority: .utility) {
            try fetchRateLimitsResultBlocking()
        }.value
    }

    /// Runs the app-server exchange, retrying once on a fast failure. Transient
    /// launch errors and network blips (codex reaches chatgpt.com to read rate
    /// limits) often fail the first attempt but succeed right after, so a single
    /// bounded retry cuts spurious failures. A slow failure already spent its
    /// timeout budget, so it is not retried (that would just double the wait).
    private func fetchRateLimitsResultBlocking() throws -> String {
        let start = Date()
        do {
            return try attemptFetchBlocking()
        } catch let error as C5hError {
            let elapsed = Date().timeIntervalSince(start)
            guard case .processLaunchFailed = error,
                  elapsed < timeoutSeconds,
                  !Task.isCancelled else { throw error }
            usleep(500_000)
            return try attemptFetchBlocking()
        }
    }

    private func attemptFetchBlocking() throws -> String {
        let launched: LaunchedProcess
        do {
            launched = try DisclaimingSpawn.launch(
                executableURL: executableURL,
                arguments: ["app-server"],
                environment: environment,
                workingDirectory: nil,
                stdin: .pipe,
                stdout: .pipe,
                stderr: .pipe
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
            try? launched.stderrHandle?.close()
        }

        let stdoutFD = stdoutHandle.fileDescriptor
        setNonBlocking(stdoutFD)

        // Capture stderr (instead of routing it to /dev/null) so an opaque "no
        // response" becomes an actionable message. Draining it every loop also
        // keeps a chatty app-server from blocking on a full stderr pipe.
        let stderrFD = launched.stderrHandle?.fileDescriptor
        if let stderrFD { setNonBlocking(stderrFD) }
        var stderrTail = ""

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
        let initializeDeadline = Date().addingTimeInterval(initializeTimeoutSeconds)

        guard try readResponse(
            id: initializeID,
            buffer: &buffer,
            fd: stdoutFD,
            stderrFD: stderrFD,
            stderrTail: &stderrTail,
            deadline: initializeDeadline
        ) != nil else {
            throw C5hError.processLaunchFailed(
                "codex app-server: no initialize response\(stderrDetail(stderrTail))"
            )
        }

        try writeMessage([
            "jsonrpc": "2.0",
            "id": rateLimitsID,
            "method": Self.methodRateLimits,
            "params": [:] as [String: String]
        ], to: stdinHandle)

        let rateLimitsDeadline = Date().addingTimeInterval(timeoutSeconds)
        guard let result = try readResponse(
            id: rateLimitsID,
            buffer: &buffer,
            fd: stdoutFD,
            stderrFD: stderrFD,
            stderrTail: &stderrTail,
            deadline: rateLimitsDeadline
        ) else {
            throw C5hError.processLaunchFailed(
                "codex app-server: no rate-limits response within timeout\(stderrDetail(stderrTail))"
            )
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
        stderrFD: Int32?,
        stderrTail: inout String,
        deadline: Date
    ) throws -> String? {
        while Date() < deadline {
            if Task.isCancelled {
                throw CancellationError()
            }
            if let stderrFD {
                drainStderr(stderrFD, into: &stderrTail)
            }
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

    private func setNonBlocking(_ fd: Int32) {
        let flags = fcntl(fd, F_GETFL, 0)
        if flags >= 0 { _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK) }
    }

    /// Drains whatever is currently buffered on the child's stderr (non-blocking)
    /// into `tail`, keeping only the most recent bytes so a noisy app-server
    /// cannot grow this without bound.
    private func drainStderr(_ fd: Int32, into tail: inout String) {
        var bytes = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(fd, &bytes, bytes.count)
            guard count > 0 else { break }
            tail.append(String(decoding: bytes.prefix(count), as: UTF8.self))
            if tail.count > Self.maxStderrTailCharacters {
                tail = String(tail.suffix(Self.maxStderrTailCharacters))
            }
        }
    }

    private func stderrDetail(_ tail: String) -> String {
        let trimmed = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : " (stderr: \(trimmed))"
    }

    private static let maxStderrTailCharacters = 2000

    /// JSON-RPC permits string or number ids; accept either so a codex build that
    /// echoes `"id":"1"` is not mistaken for a missing response. Internal so the
    /// id-matching contract can be unit tested without a live app-server.
    static func idMatches(_ value: Any?, _ targetID: Int) -> Bool {
        if let intID = value as? Int { return intID == targetID }
        if let strID = value as? String { return strID == String(targetID) }
        return false
    }

    private func matchResult(in line: String, id targetID: Int) throws -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard Self.idMatches(obj["id"], targetID) else {
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
