import Foundation

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
    public var providerID: ProviderID
    public var executableURL: URL
    public var environment: [String: String]
    public var timeoutSeconds: TimeInterval

    public init(
        providerID: ProviderID,
        executableURL: URL,
        environment: [String: String] = EnvironmentResolver.defaultEnvironment(),
        timeoutSeconds: TimeInterval = 15
    ) {
        self.providerID = providerID
        self.executableURL = executableURL
        self.environment = environment
        self.timeoutSeconds = timeoutSeconds
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

    public func collect() async throws -> UsageSnapshot {
        switch providerID {
        case .claude:
            try await ClaudeUsageCollector(
                executableURL: executableURL,
                environment: environment,
                timeoutSeconds: timeoutSeconds
            ).collect()
        case .codex:
            try await CodexUsageCollector(
                executableURL: executableURL,
                environment: environment,
                timeoutSeconds: timeoutSeconds
            ).collect()
        }
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
            ["exec", input.prompt]
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
            ProviderCommandPreview.format(providerID.executableName, arguments: ["exec", prompt])
        }
    }
}

private enum ProviderCommandPreview {
    static func format(_ executable: String, arguments: [String]) -> String {
        ([executable] + arguments.map(shellQuote)).joined(separator: " ")
    }

    private static func shellQuote(_ value: String) -> String {
        guard !value.isEmpty else { return "''" }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./:=<>"))
        if value.unicodeScalars.allSatisfy({ allowed.contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
