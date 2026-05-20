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

    func runVersionCommand() async -> ProviderStatus {
        let configured = try? await appSettings.get(settingsKey, as: String.self)
        guard let cliURL = await resolver.resolveCLI(named: executableName, configuredPath: configured) else {
            return ProviderStatus(
                providerID: id,
                isInstalled: false,
                errorMessage: "Could not find '\(executableName)' on PATH or in known prefixes."
            )
        }
        do {
            let run = try await runner.run(VersionCommand(providerID: id, executableURL: cliURL).spec())
            let version = try await firstLineOfStdout(run: run)
            return ProviderStatus(
                providerID: id,
                isInstalled: run.status == .succeeded,
                cliPath: cliURL.path,
                version: version,
                isAuthenticated: nil,
                lastCheckedAt: .now,
                errorMessage: run.status == .succeeded ? nil : await firstLineOfStderr(run: run) ?? run.errorMessage
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

    func runAuthStatusCommand() async -> ProviderStatus {
        let configured = try? await appSettings.get(settingsKey, as: String.self)
        guard let cliURL = await resolver.resolveCLI(named: executableName, configuredPath: configured) else {
            return ProviderStatus(
                providerID: id,
                isInstalled: false,
                errorMessage: "Could not find '\(executableName)' on PATH or in known prefixes."
            )
        }
        do {
            let run = try await runner.run(AuthStatusCommand(providerID: id, executableURL: cliURL).spec())
            let stdout = try await stdout(run: run)
            let authenticated = AuthStatusCommand.isAuthenticated(
                providerID: id,
                stdout: stdout,
                exitCode: run.exitCode
            )
            return ProviderStatus(
                providerID: id,
                isInstalled: true,
                cliPath: cliURL.path,
                isAuthenticated: authenticated,
                lastCheckedAt: .now,
                errorMessage: authenticated ? nil : await firstLineOfStderr(run: run) ?? run.errorMessage
            )
        } catch {
            return ProviderStatus(
                providerID: id,
                isInstalled: true,
                cliPath: cliURL.path,
                isAuthenticated: false,
                errorMessage: String(describing: error)
            )
        }
    }

    func runUsageCommand() async throws -> UsageSnapshot {
        // Real implementation arrives in M12. For now, a placeholder snapshot
        // keeps higher layers compilable.
        UsageSnapshot(
            providerID: id,
            capturedAt: .now,
            rawJSON: "{}",
            normalizedJSON: "{}"
        )
    }

    func runPromptCommand(_ input: TriggerPromptInput, runID: UUID) async throws -> CommandRun {
        // Concrete adapters override this. Default falls back to a CLI run with
        // generic args so the path is still observable from Logs in early
        // milestones.
        let configured = try? await appSettings.get(settingsKey, as: String.self)
        guard let cliURL = await resolver.resolveCLI(named: executableName, configuredPath: configured) else {
            throw C5hError.cliNotFound(executableName)
        }
        return try await runner.run(
            PromptCommand(providerID: id, executableURL: cliURL, input: input).spec(),
            runID: runID
        )
    }

    var settingsKey: String { "providers.\(id.rawValue).cliPath" }

    private func firstLineOfStdout(run: CommandRun) async throws -> String? {
        let output = try await stdout(run: run)
        return output
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespaces)
    }

    private func firstLineOfStderr(run: CommandRun) async -> String? {
        guard let path = run.stderrPath,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }
        return String(data: data, encoding: .utf8)?
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespaces)
    }

    private func stdout(run: CommandRun) async throws -> String {
        guard let path = run.stdoutPath else { return "" }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return String(data: data, encoding: .utf8) ?? ""
    }
}
