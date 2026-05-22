import Foundation
import C5hCore
import C5hStore

struct CodexProviderAdapter: ProviderAdapter {
    let id: ProviderID = .codex
    let displayName: String = ProviderID.codex.displayName
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
            id: .codex,
            displayName: ProviderID.codex.displayName,
            executableName: ProviderID.codex.executableName,
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
        return try await UsageCommand(providerID: .codex, executableURL: cliURL).collect(
            logWriter: writer,
            onStart: { run in try await repo.create(run) },
            onComplete: { run in try await repo.update(run) }
        )
    }

    func runPromptCommand(_ input: TriggerPromptInput, runID: UUID) async throws -> CommandRun {
        let configured = try? await backing.appSettings.get(backing.settingsKey, as: String.self)
        guard let cliURL = await backing.resolver.resolveCLI(
            named: backing.executableName,
            configuredPath: configured
        ) else {
            throw C5hError.cliNotFound(backing.executableName)
        }
        return try await backing.runner.run(
            PromptCommand(providerID: .codex, executableURL: cliURL, input: input).spec(),
            runID: runID
        )
    }
}
