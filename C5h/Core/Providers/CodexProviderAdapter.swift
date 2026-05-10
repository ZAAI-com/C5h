import Foundation
import C5hCore
import C5hStore

struct CodexProviderAdapter: ProviderAdapter {
    let id: ProviderID = .codex
    let displayName: String = ProviderID.codex.displayName
    private let backing: CLIBackedProviderAdapter

    init(
        runner: any CommandRunning,
        resolver: any CLIPathResolving,
        appSettings: any AppSettingsRepository
    ) {
        self.backing = CLIBackedProviderAdapter(
            id: .codex,
            displayName: ProviderID.codex.displayName,
            executableName: ProviderID.codex.executableName,
            runner: runner,
            resolver: resolver,
            appSettings: appSettings
        )
    }

    func detectStatus() async -> ProviderStatus { await backing.detectStatus() }
    func runTestCommand() async throws -> CommandRun { try await backing.runTestCommand() }

    func collectUsage() async throws -> UsageSnapshot {
        try await CodexUsageCollector().collect()
    }

    func triggerPrompt(_ input: TriggerPromptInput) async throws -> CommandRun {
        let configured = try? await backing.appSettings.get(backing.settingsKey, as: String.self)
        guard let cliURL = await backing.resolver.resolveCLI(
            named: backing.executableName,
            configuredPath: configured
        ) else {
            throw C5hError.cliNotFound(backing.executableName)
        }
        let args = ["chat", "-p", input.prompt]
        return try await backing.runner.run(CommandSpec(
            providerID: .codex,
            runType: .triggerPrompt,
            executableURL: cliURL,
            arguments: args,
            workingDirectory: input.projectPath.map { URL(fileURLWithPath: $0) },
            environment: EnvironmentResolver.defaultEnvironment(),
            timeoutSeconds: 60 * 60 * 6
        ))
    }
}

private struct CodexUsageCollector: Sendable {
    var sessionsDirectory: URL

    init(sessionsDirectory: URL = Self.defaultSessionsDirectory()) {
        self.sessionsDirectory = sessionsDirectory
    }

    func collect() async throws -> UsageSnapshot {
        try await Task.detached(priority: .utility) {
            try collectBlocking()
        }.value
    }

    private func collectBlocking() throws -> UsageSnapshot {
        let files = try Self.sessionFiles(in: sessionsDirectory)
        let status = try CodexUsageStatus.latestStatus(inSessionFiles: files)
        let capturedAt = Date()
        return UsageSnapshot(
            providerID: .codex,
            capturedAt: capturedAt,
            rawJSON: status.encodedPayload(),
            normalizedJSON: UsageNormalizer.encode(
                status.normalizedUsage(providerID: .codex, capturedAt: capturedAt)
            )
        )
    }

    private static func defaultSessionsDirectory() -> URL {
        if let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"],
           !codexHome.isEmpty {
            return URL(fileURLWithPath: codexHome).appendingPathComponent("sessions", isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    private static func sessionFiles(in root: URL) throws -> [URL] {
        let fileManager = FileManager.default
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw C5hError.providerNotConfigured("Codex sessions directory at \(root.path)")
        }
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw C5hError.providerNotConfigured("Codex sessions directory at \(root.path)")
        }

        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true {
                files.append(url)
            }
        }
        return files
    }
}
