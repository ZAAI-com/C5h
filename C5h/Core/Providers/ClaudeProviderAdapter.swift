import Foundation
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

        return try await ClaudeUsageCollector(executableURL: cliURL).collect()
    }

    func runPromptCommand(_ input: TriggerPromptInput, runID: UUID) async throws -> CommandRun {
        try await backing.runPromptCommand(input, runID: runID)
    }
}
