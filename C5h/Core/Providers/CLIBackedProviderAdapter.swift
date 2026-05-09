import Foundation
import C5hCore
import C5hStore

/// Shared scaffolding used by both the Claude and Codex adapters.
struct CLIBackedProviderAdapter: ProviderAdapter {
    let id: ProviderID
    let displayName: String
    let executableName: String
    let runner: any CommandRunning
    let resolver: any CLIPathResolving
    let appSettings: any AppSettingsRepository

    func detectStatus() async -> ProviderStatus {
        let configured = try? await appSettings.get(settingsKey, as: String.self)
        guard let cliURL = await resolver.resolveCLI(named: executableName, configuredPath: configured) else {
            return ProviderStatus(
                providerID: id,
                isInstalled: false,
                errorMessage: "Could not find '\(executableName)' on PATH or in known prefixes."
            )
        }
        do {
            let run = try await runner.run(CommandSpec(
                providerID: id,
                runType: .detectStatus,
                executableURL: cliURL,
                arguments: ["--version"],
                environment: EnvironmentResolver.defaultEnvironment(),
                timeoutSeconds: 10
            ))
            let version = try await firstLineOfStdout(run: run)
            return ProviderStatus(
                providerID: id,
                isInstalled: run.status == .succeeded,
                cliPath: cliURL.path,
                version: version,
                isAuthenticated: nil,
                lastCheckedAt: .now,
                errorMessage: run.status == .succeeded ? nil : run.errorMessage
            )
        } catch {
            return ProviderStatus(
                providerID: id,
                isInstalled: true,
                cliPath: cliURL.path,
                errorMessage: String(describing: error)
            )
        }
    }

    func runTestCommand() async throws -> CommandRun {
        let configured = try? await appSettings.get(settingsKey, as: String.self)
        guard let cliURL = await resolver.resolveCLI(named: executableName, configuredPath: configured) else {
            throw C5hError.cliNotFound(executableName)
        }
        return try await runner.run(CommandSpec(
            providerID: id,
            runType: .testCommand,
            executableURL: cliURL,
            arguments: ["--version"],
            environment: EnvironmentResolver.defaultEnvironment(),
            timeoutSeconds: 10
        ))
    }

    func collectUsage() async throws -> UsageSnapshot {
        // Real implementation arrives in M12. For now, a placeholder snapshot
        // keeps higher layers compilable.
        UsageSnapshot(
            providerID: id,
            capturedAt: .now,
            rawJSON: "{}",
            normalizedJSON: "{}"
        )
    }

    func triggerPrompt(_ input: TriggerPromptInput) async throws -> CommandRun {
        // Concrete adapters override this. Default falls back to a CLI run with
        // generic args so the path is still observable from Logs in early
        // milestones.
        let configured = try? await appSettings.get(settingsKey, as: String.self)
        guard let cliURL = await resolver.resolveCLI(named: executableName, configuredPath: configured) else {
            throw C5hError.cliNotFound(executableName)
        }
        return try await runner.run(CommandSpec(
            providerID: id,
            runType: .triggerPrompt,
            executableURL: cliURL,
            arguments: defaultPromptArguments(input),
            workingDirectory: input.projectPath.map { URL(fileURLWithPath: $0) },
            environment: EnvironmentResolver.defaultEnvironment(),
            timeoutSeconds: 60 * 60 * 6
        ))
    }

    var settingsKey: String { "providers.\(id.rawValue).cliPath" }

    func defaultPromptArguments(_ input: TriggerPromptInput) -> [String] {
        ["-p", input.prompt]
    }

    private func firstLineOfStdout(run: CommandRun) async throws -> String? {
        guard let path = run.stdoutPath else { return nil }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return String(data: data, encoding: .utf8)?
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespaces)
    }
}
