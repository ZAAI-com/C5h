import Foundation
import Darwin

/// PTY-drives the `claude` REPL with a `/usage` slash command and an injected
/// `statusLine` Node.js hook that emits a `C5H_RATE_LIMITS:{json}` sentinel.
/// Used by both the main app's `ClaudeProviderAdapter` and the background
/// `C5hHelper` polling loop.
public struct ClaudeUsageCollector: Sendable {
    public var executableURL: URL
    public var environment: [String: String]
    public var timeoutSeconds: TimeInterval
    public var maxTranscriptCharacters: Int

    public init(
        executableURL: URL,
        environment: [String: String] = EnvironmentResolver.defaultEnvironment(),
        timeoutSeconds: TimeInterval = 30,
        maxTranscriptCharacters: Int = 64 * 1024
    ) {
        self.executableURL = executableURL
        self.environment = environment
        self.timeoutSeconds = timeoutSeconds
        self.maxTranscriptCharacters = maxTranscriptCharacters
    }

    public func collect() async throws -> UsageSnapshot {
        // Unstructured Task (not detached) so caller cancellation reaches the
        // blocking work via Task.isCancelled checks below.
        try await Task(priority: .utility) {
            try collectBlocking()
        }.value
    }

    private func collectBlocking() throws -> UsageSnapshot {
        var masterFD: Int32 = -1
        var slaveFD: Int32 = -1
        var windowSize = winsize(ws_row: 40, ws_col: 1200, ws_xpixel: 0, ws_ypixel: 0)

        guard openpty(&masterFD, &slaveFD, nil, nil, &windowSize) == 0 else {
            throw C5hError.processLaunchFailed(Self.errnoMessage("openpty failed"))
        }

        let masterHandle = FileHandle(fileDescriptor: masterFD, closeOnDealloc: true)
        defer { try? masterHandle.close() }

        let inputFD = dup(slaveFD)
        let outputFD = dup(slaveFD)
        let errorFD = dup(slaveFD)
        close(slaveFD)

        guard inputFD >= 0, outputFD >= 0, errorFD >= 0 else {
            [inputFD, outputFD, errorFD]
                .filter { $0 >= 0 }
                .forEach { _ = Darwin.close($0) }
            throw C5hError.processLaunchFailed(Self.errnoMessage("dup failed"))
        }

        let inputHandle = FileHandle(fileDescriptor: inputFD, closeOnDealloc: true)
        let outputHandle = FileHandle(fileDescriptor: outputFD, closeOnDealloc: true)
        let errorHandle = FileHandle(fileDescriptor: errorFD, closeOnDealloc: true)
        defer {
            try? inputHandle.close()
            try? outputHandle.close()
            try? errorHandle.close()
        }

        let statusPayloadURL = try Self.statusPayloadURL()
        var launchEnvironment = environment
        launchEnvironment["C5H_USAGE_STATUS_PATH"] = statusPayloadURL.path
        defer { try? FileManager.default.removeItem(at: statusPayloadURL) }

        let arguments = try claudeArguments(settingsJSON: settingsJSON())

        let launched: LaunchedProcess
        do {
            launched = try DisclaimingSpawn.launch(
                executableURL: executableURL,
                arguments: arguments,
                environment: launchEnvironment,
                workingDirectory: Self.safeWorkingDirectory(),
                stdin: .fileHandle(inputHandle),
                stdout: .fileHandle(outputHandle),
                stderr: .fileHandle(errorHandle)
            )
        } catch {
            throw C5hError.processLaunchFailed(String(describing: error))
        }

        let existingFlags = fcntl(masterFD, F_GETFL, 0)
        if existingFlags >= 0 {
            _ = fcntl(masterFD, F_SETFL, existingFlags | O_NONBLOCK)
        }

        var output = ""
        var sentUsageCommand = false
        var sentUsageAt: Date?
        var dismissedUsageDialog = false
        let startedAt = Date()
        let deadline = startedAt.addingTimeInterval(timeoutSeconds)

        defer {
            if launched.isRunning {
                try? Self.write("/exit\r", to: masterFD)
                usleep(150_000)
                if launched.isRunning {
                    launched.terminate()
                    usleep(150_000)
                }
                if launched.isRunning {
                    launched.kill()
                }
            }
            _ = launched.waitBlocking()
        }

        while Date() < deadline {
            if Task.isCancelled {
                throw CancellationError()
            }
            if let chunk = try Self.readAvailable(from: masterFD) {
                Self.append(chunk, to: &output, limit: maxTranscriptCharacters)
                if let snapshot = try snapshotIfAvailable(in: output) {
                    try? Self.write("/exit\r", to: masterFD)
                    return snapshot
                }
            }
            if let snapshot = try snapshotIfAvailable(at: statusPayloadURL) {
                try? Self.write("/exit\r", to: masterFD)
                return snapshot
            }

            if !sentUsageCommand, Date().timeIntervalSince(startedAt) >= 1.0 {
                try Self.write("/usage\r", to: masterFD)
                sentUsageCommand = true
                sentUsageAt = Date()
            }

            if sentUsageCommand, !dismissedUsageDialog {
                let usageScreenHasReset = output.contains("Current session") && output.contains("Resets")
                let waitedLongEnough = sentUsageAt.map { Date().timeIntervalSince($0) >= 5.0 } ?? false
                if usageScreenHasReset || waitedLongEnough {
                    try Self.write("\u{1B}", to: masterFD)
                    dismissedUsageDialog = true
                }
            }

            if !launched.isRunning, sentUsageCommand {
                break
            }

            usleep(100_000)
        }

        if !launched.isRunning {
            throw C5hError.processLaunchFailed("Claude exited before reporting rate_limits.five_hour")
        }
        throw C5hError.processTimedOutWithTranscript(Self.printableTranscript(output))
    }

    private func snapshotIfAvailable(in output: String) throws -> UsageSnapshot? {
        for payload in ClaudeUsageStatus.sentinelPayloads(in: output).reversed() {
            guard let status = try? ClaudeUsageStatus.parsePayload(payload) else {
                continue
            }
            let capturedAt = Date()
            return UsageSnapshot(
                providerID: .claude,
                capturedAt: capturedAt,
                rawJSON: payload,
                normalizedJSON: UsageNormalizer.encode(
                    status.normalizedUsage(providerID: .claude, capturedAt: capturedAt)
                )
            )
        }
        return nil
    }

    private func snapshotIfAvailable(at url: URL) throws -> UsageSnapshot? {
        guard let payload = try? String(contentsOf: url, encoding: .utf8),
              !payload.isEmpty else {
            return nil
        }
        guard let status = try? ClaudeUsageStatus.parsePayload(payload) else {
            return nil
        }
        let capturedAt = Date()
        return UsageSnapshot(
            providerID: .claude,
            capturedAt: capturedAt,
            rawJSON: payload,
            normalizedJSON: UsageNormalizer.encode(
                status.normalizedUsage(providerID: .claude, capturedAt: capturedAt)
            )
        )
    }

    private func claudeArguments(settingsJSON: String) throws -> [String] {
        ["--setting-sources", "local", "--settings", settingsJSON]
    }

    private func settingsJSON() throws -> String {
        let data = try JSONEncoder().encode(ClaudeSettings(statusLine: ClaudeStatusLine(command: Self.statusLineCommand)))
        guard let string = String(data: data, encoding: .utf8) else {
            throw C5hError.processLaunchFailed("Could not encode Claude statusLine settings")
        }
        return string
    }

    private static let statusLineCommand = """
    /usr/bin/env node -e 'let d="";process.stdin.setEncoding("utf8");process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{try{const j=JSON.parse(d||"{}");if(j.rate_limits){const p=JSON.stringify({rate_limits:j.rate_limits});if(process.env.C5H_USAGE_STATUS_PATH){try{require("fs").writeFileSync(process.env.C5H_USAGE_STATUS_PATH,p)}catch(e){}}console.log("C5H_RATE_LIMITS:"+p)}}catch(e){}});'
    """

    private static func readAvailable(from fd: Int32) throws -> String? {
        var bytes = [UInt8](repeating: 0, count: 4096)
        let count = Darwin.read(fd, &bytes, bytes.count)
        if count > 0 {
            return String(decoding: bytes.prefix(count), as: UTF8.self)
        }
        if count == 0 {
            return ""
        }
        if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR {
            return nil
        }
        throw C5hError.processLaunchFailed(errnoMessage("read failed"))
    }

    private static func write(_ string: String, to fd: Int32) throws {
        let data = Data(string.utf8)
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(fd, base.advanced(by: offset), buffer.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw C5hError.processLaunchFailed(errnoMessage("write failed"))
                }
                offset += written
            }
        }
    }

    private static func append(_ chunk: String, to output: inout String, limit: Int) {
        output.append(chunk)
        guard limit > 0, output.count > limit else { return }
        output.removeFirst(output.count - limit)
    }

    private static func printableTranscript(_ output: String) -> String {
        output
            .replacingOccurrences(of: "\u{1B}", with: "<ESC>")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func errnoMessage(_ prefix: String) -> String {
        "\(prefix): \(String(cString: strerror(errno)))"
    }

    private static func statusPayloadURL() throws -> URL {
        let fallback = FileManager.default.temporaryDirectory
            .appendingPathComponent("C5h", isDirectory: true)
        let base = safeWorkingDirectory() ?? fallback
        let dir = base.appendingPathComponent("usage-probes", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    }

    /// Working directory for the usage collector subprocess.
    ///
    /// Avoid `$HOME`: launching `claude` there causes it to enumerate the home
    /// directory on startup, which trips TCC prompts for `~/Library/Containers/*`
    /// ("access data from other apps") and file-provider mounts like `~/OneDrive`.
    /// The app's Application Support directory is owned by C5h and TCC-safe.
    private static func safeWorkingDirectory() -> URL? {
        let fm = FileManager.default
        guard let support = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let dir = support.appendingPathComponent("C5h", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

private struct ClaudeSettings: Encodable {
    var statusLine: ClaudeStatusLine
}

private struct ClaudeStatusLine: Encodable {
    var type = "command"
    var command: String
}
