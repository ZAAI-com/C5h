import Foundation
import Darwin

public struct VersionCommand: Sendable {
    public var providerID: ProviderID
    public var executableURL: URL
    public var environment: [String: String]
    public var timeoutSeconds: TimeInterval

    public init(
        providerID: ProviderID,
        executableURL: URL,
        environment: [String: String] = EnvironmentResolver.defaultEnvironment(),
        timeoutSeconds: TimeInterval = 10
    ) {
        self.providerID = providerID
        self.executableURL = executableURL
        self.environment = environment
        self.timeoutSeconds = timeoutSeconds
    }

    public func spec() -> CommandSpec {
        CommandSpec(
            providerID: providerID,
            commandName: .versionCommand,
            executableURL: executableURL,
            arguments: ["--version"],
            environment: environment,
            timeoutSeconds: timeoutSeconds
        )
    }

    public var displayCommand: String {
        Self.displayCommand(providerID: providerID)
    }

    public static func displayCommand(providerID: ProviderID) -> String {
        ProviderCommandPreview.format(providerID.executableName, arguments: ["--version"])
    }
}

public struct AuthStatusCommand: Sendable {
    public var providerID: ProviderID
    public var executableURL: URL
    public var environment: [String: String]
    public var timeoutSeconds: TimeInterval

    public init(
        providerID: ProviderID,
        executableURL: URL,
        environment: [String: String] = EnvironmentResolver.defaultEnvironment(),
        timeoutSeconds: TimeInterval = 10
    ) {
        self.providerID = providerID
        self.executableURL = executableURL
        self.environment = environment
        self.timeoutSeconds = timeoutSeconds
    }

    public var arguments: [String] {
        switch providerID {
        case .claude:
            ["auth", "status", "--json"]
        case .codex:
            ["login", "status"]
        }
    }

    public func spec() -> CommandSpec {
        CommandSpec(
            providerID: providerID,
            commandName: .authStatusCommand,
            executableURL: executableURL,
            arguments: arguments,
            environment: environment,
            timeoutSeconds: timeoutSeconds
        )
    }

    public var displayCommand: String {
        Self.displayCommand(providerID: providerID)
    }

    public static func displayCommand(providerID: ProviderID) -> String {
        ProviderCommandPreview.format(providerID.executableName, arguments: arguments(providerID: providerID))
    }

    public static func arguments(providerID: ProviderID) -> [String] {
        switch providerID {
        case .claude:
            ["auth", "status", "--json"]
        case .codex:
            ["login", "status"]
        }
    }

    public static func isAuthenticated(
        providerID: ProviderID,
        stdout: String,
        stderr: String = "",
        exitCode: Int32?
    ) -> Bool {
        guard exitCode == 0 else { return false }
        switch providerID {
        case .claude:
            guard let data = stdout.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let loggedIn = object["loggedIn"] as? Bool else {
                return false
            }
            return loggedIn
        case .codex:
            // codex 0.132 writes "Logged in ..." to stderr with empty stdout,
            // so inspect both streams.
            let lowercased = (stdout + "\n" + stderr).lowercased()
            return lowercased.contains("logged in") && !lowercased.contains("not logged in")
        }
    }
}

public struct UsageCommand: Sendable {
    public typealias OnEvent = @Sendable (CommandRun) async throws -> Void

    public var providerID: ProviderID
    public var executableURL: URL
    public var environment: [String: String]
    public var timeoutSeconds: TimeInterval
    public var lockConfiguration: UsageProbeLockConfiguration

    public init(
        providerID: ProviderID,
        executableURL: URL,
        environment: [String: String] = EnvironmentResolver.defaultEnvironment(),
        timeoutSeconds: TimeInterval = 15,
        lockConfiguration: UsageProbeLockConfiguration = .production
    ) {
        self.providerID = providerID
        self.executableURL = executableURL
        self.environment = environment
        self.timeoutSeconds = timeoutSeconds
        self.lockConfiguration = lockConfiguration
    }

    public func claudeArguments(settingsJSON: String) throws -> [String] {
        guard providerID == .claude else {
            throw C5hError.providerNotConfigured("Codex usage reset detection is unavailable")
        }
        return ["--setting-sources", "local", "--settings", settingsJSON]
    }

    public var displayCommand: String {
        Self.displayCommand(providerID: providerID)
    }

    public static func displayCommand(providerID: ProviderID) -> String {
        switch providerID {
        case .claude:
            ProviderCommandPreview.format(
                providerID.executableName,
                arguments: ["--settings", "<C5h statusLine usage hook>"]
            )
        case .codex:
            "\(providerID.executableName) app-server -> \(CodexAppServerClient.methodRateLimits)"
        }
    }

    public func collect(
        logWriter: (any FileLogWriting)? = nil,
        onStart: OnEvent? = nil,
        onComplete: OnEvent? = nil
    ) async throws -> UsageSnapshot {
        let lock: UsageProbeLock?
        if lockConfiguration.isEnabled {
            guard let acquired = try UsageProbeLock.acquire(
                providerID: providerID,
                configuration: lockConfiguration
            ) else {
                throw C5hError.usageRefreshAlreadyRunning(providerID)
            }
            lock = acquired
        } else {
            lock = nil
        }
        defer { _ = lock }

        let runID = UUID()
        let startedAt = Date()
        let logPaths = try? logWriter?.makeLogPaths(for: runID, at: startedAt)

        var run = CommandRun(
            id: runID,
            providerID: providerID,
            commandName: .usageCommand,
            command: executableURL.path,
            argumentsJSON: Self.argumentsJSON(for: providerID),
            startedAt: startedAt,
            status: .running,
            stdoutPath: logPaths?.stdoutURL.path,
            stderrPath: logPaths?.stderrURL.path,
            ownerPID: getpid()
        )
        if let onStart { try await onStart(run) }

        do {
            let snapshot: UsageSnapshot
            switch providerID {
            case .claude:
                snapshot = try await ClaudeUsageCollector(
                    executableURL: executableURL,
                    environment: environment,
                    timeoutSeconds: timeoutSeconds
                ).collect()
            case .codex:
                snapshot = try await CodexUsageCollector(
                    executableURL: executableURL,
                    environment: environment,
                    timeoutSeconds: timeoutSeconds
                ).collect()
            }
            run.endedAt = Date()
            run.status = .succeeded
            run.exitCode = 0
            if let url = logPaths?.stdoutURL {
                try? snapshot.normalizedJSON.data(using: .utf8)?.write(to: url)
            }
            if let onComplete { try await onComplete(run) }
            return snapshot
        } catch {
            run.endedAt = Date()
            if Self.isProcessTimedOut(error) {
                run.status = .timedOut
            } else {
                run.status = .failed
            }
            run.errorMessage = Self.commandRunErrorMessage(for: error)
            if let url = logPaths?.stderrURL {
                try? Self.stderrLogText(for: error).data(using: .utf8)?.write(to: url)
            }
            if let onComplete { try await onComplete(run) }
            if Self.isProcessTimedOut(error) {
                throw C5hError.processTimedOut
            }
            throw error
        }
    }

    private static func argumentsJSON(for providerID: ProviderID) -> String {
        let args: [String]
        switch providerID {
        case .claude:
            args = ["--settings", "<C5h statusLine usage hook>"]
        case .codex:
            args = ["app-server", "->", CodexAppServerClient.methodRateLimits]
        }
        if let data = try? JSONEncoder().encode(args),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return "[]"
    }

    private static func isProcessTimedOut(_ error: Error) -> Bool {
        (error as? C5hError)?.isProcessTimedOut == true
    }

    private static func commandRunErrorMessage(for error: Error) -> String {
        if isProcessTimedOut(error) {
            return "processTimedOut"
        }
        return String(describing: error)
    }

    private static func stderrLogText(for error: Error) -> String {
        guard let transcript = (error as? C5hError)?.timeoutTranscript,
              !transcript.isEmpty else {
            return String(describing: error)
        }
        return """
        processTimedOut

        --- Claude usage collector output ---
        \(transcript)
        """
    }
}

public struct PromptCommand: Sendable {
    public var providerID: ProviderID
    public var executableURL: URL
    public var input: TriggerPromptInput
    public var environment: [String: String]
    public var timeoutSeconds: TimeInterval

    public init(
        providerID: ProviderID,
        executableURL: URL,
        input: TriggerPromptInput,
        environment: [String: String] = EnvironmentResolver.defaultEnvironment(),
        timeoutSeconds: TimeInterval = 60 * 60 * 6
    ) {
        self.providerID = providerID
        self.executableURL = executableURL
        self.input = input
        self.environment = environment
        self.timeoutSeconds = timeoutSeconds
    }

    public var arguments: [String] {
        switch providerID {
        case .claude:
            ["-p", input.prompt]
        case .codex:
            ["exec", "--skip-git-repo-check", input.prompt]
        }
    }

    public func spec() -> CommandSpec {
        CommandSpec(
            providerID: providerID,
            commandName: .promptCommand,
            executableURL: executableURL,
            arguments: arguments,
            workingDirectory: input.projectPath.map { URL(fileURLWithPath: $0) },
            environment: environment,
            timeoutSeconds: timeoutSeconds
        )
    }

    public var displayCommand: String {
        Self.displayCommand(providerID: providerID, prompt: input.prompt)
    }

    public static func displayCommand(providerID: ProviderID, prompt: String = "<prompt>") -> String {
        switch providerID {
        case .claude:
            ProviderCommandPreview.format(providerID.executableName, arguments: ["-p", prompt])
        case .codex:
            ProviderCommandPreview.format(providerID.executableName, arguments: ["exec", "--skip-git-repo-check", prompt])
        }
    }
}

private enum ProviderCommandPreview {
    static func format(_ executable: String, arguments: [String]) -> String {
        ([executable] + arguments.map(shellQuote)).joined(separator: " ")
    }

    private static func shellQuote(_ value: String) -> String {
        guard !value.isEmpty else { return "''" }
        // Exclude `<` and `>` — shells treat them as redirection, so leaving the
        // default placeholder `<prompt>` unquoted would turn the preview into a
        // shell-redirect command if copy-pasted.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./:=@,+"))
        if value.unicodeScalars.allSatisfy({ allowed.contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
