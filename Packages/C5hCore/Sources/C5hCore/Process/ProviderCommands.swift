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
}
