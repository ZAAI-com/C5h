import Foundation
import Darwin
import C5hCore
import C5hStore

struct ClaudeProviderAdapter: ProviderAdapter {
    let id: ProviderID = .claude
    let displayName: String = ProviderID.claude.displayName
    private let backing: CLIBackedProviderAdapter

    init(
        runner: any CommandRunning,
        resolver: any CLIPathResolving,
        appSettings: any AppSettingsRepository
    ) {
        self.backing = CLIBackedProviderAdapter(
            id: .claude,
            displayName: ProviderID.claude.displayName,
            executableName: ProviderID.claude.executableName,
            runner: runner,
            resolver: resolver,
            appSettings: appSettings
        )
    }

    func detectStatus() async -> ProviderStatus { await backing.detectStatus() }
    func runTestCommand() async throws -> CommandRun { try await backing.runTestCommand() }

    func collectUsage() async throws -> UsageSnapshot {
        let configured = try? await backing.appSettings.get(backing.settingsKey, as: String.self)
        guard let cliURL = await backing.resolver.resolveCLI(
            named: backing.executableName,
            configuredPath: configured
        ) else {
            throw C5hError.cliNotFound(backing.executableName)
        }

        return try await ClaudeUsageCollector(executableURL: cliURL).collect()
    }

    func triggerPrompt(_ input: TriggerPromptInput) async throws -> CommandRun {
        try await backing.triggerPrompt(input)
    }
}

private struct ClaudeUsageCollector: Sendable {
    var executableURL: URL
    var environment: [String: String]
    var timeoutSeconds: TimeInterval

    init(
        executableURL: URL,
        environment: [String: String] = EnvironmentResolver.defaultEnvironment(),
        timeoutSeconds: TimeInterval = 15
    ) {
        self.executableURL = executableURL
        self.environment = environment
        self.timeoutSeconds = timeoutSeconds
    }

    func collect() async throws -> UsageSnapshot {
        try await Task.detached(priority: .utility) {
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

        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "--setting-sources", "local",
            "--settings", try settingsJSON()
        ]
        process.environment = environment
        if let home = environment["HOME"] {
            process.currentDirectoryURL = URL(fileURLWithPath: home)
        }
        process.standardInput = inputHandle
        process.standardOutput = outputHandle
        process.standardError = errorHandle

        try process.run()

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
            if process.isRunning {
                try? Self.write("/exit\r", to: masterFD)
                usleep(150_000)
                if process.isRunning {
                    process.terminate()
                }
            }
        }

        while Date() < deadline {
            if let chunk = try Self.readAvailable(from: masterFD) {
                output.append(chunk)
                if let snapshot = try snapshotIfAvailable(in: output) {
                    try? Self.write("/exit\r", to: masterFD)
                    return snapshot
                }
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

            if !process.isRunning, sentUsageCommand {
                break
            }

            usleep(100_000)
        }

        if !process.isRunning {
            throw C5hError.processLaunchFailed("Claude exited before reporting rate_limits.five_hour")
        }
        throw C5hError.processTimedOut
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

    private func settingsJSON() throws -> String {
        let data = try JSONEncoder().encode(ClaudeSettings(statusLine: ClaudeStatusLine(command: Self.statusLineCommand)))
        guard let string = String(data: data, encoding: .utf8) else {
            throw C5hError.processLaunchFailed("Could not encode Claude statusLine settings")
        }
        return string
    }

    private static let statusLineCommand = """
    /usr/bin/env node -e 'let d="";process.stdin.setEncoding("utf8");process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{try{const j=JSON.parse(d||"{}");if(j.rate_limits){console.log("C5H_RATE_LIMITS:"+JSON.stringify({rate_limits:j.rate_limits}))}}catch(e){}});'
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

    private static func errnoMessage(_ prefix: String) -> String {
        "\(prefix): \(String(cString: strerror(errno)))"
    }
}

private struct ClaudeSettings: Encodable {
    var statusLine: ClaudeStatusLine
}

private struct ClaudeStatusLine: Encodable {
    var type = "command"
    var command: String
}
