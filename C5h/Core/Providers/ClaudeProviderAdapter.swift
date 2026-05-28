import Foundation
import C5hCore
import C5hStore

struct ClaudeProviderAdapter: ProviderAdapter {
    let id: ProviderID = .claude
    let displayName: String = ProviderID.claude.displayName
    private let backing: CLIBackedProviderAdapter
    private let cmdRepo: any CommandRunRepository
    private let logWriter: any FileLogWriting

    init(
        runner: any CommandRunning,
        resolver: any CLIPathResolving,
        appSettings: any AppSettingsRepository,
        cmdRepo: any CommandRunRepository,
        logWriter: any FileLogWriting
    ) {
        self.backing = CLIBackedProviderAdapter(
            id: .claude,
            displayName: ProviderID.claude.displayName,
            executableName: ProviderID.claude.executableName,
            runner: runner,
            resolver: resolver,
            appSettings: appSettings
        )
        self.cmdRepo = cmdRepo
        self.logWriter = logWriter
    }

    func runVersionCommand() async -> ProviderStatus { await backing.runVersionCommand() }
    func runAuthStatusCommand() async -> ProviderStatus { await backing.runAuthStatusCommand() }

    func runUsageCommand() async throws -> UsageSnapshot {
        let configured = try? await backing.appSettings.get(backing.settingsKey, as: String.self)
        guard let cliURL = await backing.resolver.resolveCLI(
            named: backing.executableName,
            configuredPath: configured
        ) else {
            throw C5hError.cliNotFound(backing.executableName)
        }

        let repo = cmdRepo
        let writer = logWriter
        return try await UsageCommand(providerID: .claude, executableURL: cliURL).collect(
            logWriter: writer,
            onStart: { run in try await repo.create(run) },
            onComplete: { run in try await repo.update(run) }
        )
    }

    func runPromptCommand(_ input: TriggerPromptInput, runID: UUID) async throws -> CommandRun {
        try await backing.runPromptCommand(input, runID: runID)
    }
}
