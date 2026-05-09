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
    func collectUsage() async throws -> UsageSnapshot { try await backing.collectUsage() }

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
