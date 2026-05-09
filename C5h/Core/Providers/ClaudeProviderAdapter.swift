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

    func detectStatus() async -> ProviderStatus { await backing.detectStatus() }
    func runTestCommand() async throws -> CommandRun { try await backing.runTestCommand() }
    func collectUsage() async throws -> UsageSnapshot { try await backing.collectUsage() }

    func triggerPrompt(_ input: TriggerPromptInput) async throws -> CommandRun {
        try await backing.triggerPrompt(input)
    }
}
