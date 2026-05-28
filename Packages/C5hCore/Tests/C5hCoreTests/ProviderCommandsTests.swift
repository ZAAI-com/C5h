import Foundation
import Testing
@testable import C5hCore

@Suite("ProviderCommands")
struct ProviderCommandsTests {
    private let claudeURL = URL(fileURLWithPath: "/opt/homebrew/bin/claude")
    private let codexURL = URL(fileURLWithPath: "/usr/local/bin/codex")

    @Test("VersionCommand builds provider version specs")
    func versionCommand() {
        let claude = VersionCommand(providerID: .claude, executableURL: claudeURL).spec()
        #expect(claude.providerID == .claude)
        #expect(claude.commandName == .versionCommand)
        #expect(claude.executableURL == claudeURL)
        #expect(claude.arguments == ["--version"])
        #expect(claude.timeoutSeconds == 10)
        #expect(VersionCommand.displayCommand(providerID: .claude) == "claude --version")

        let codex = VersionCommand(providerID: .codex, executableURL: codexURL).spec()
        #expect(codex.providerID == .codex)
        #expect(codex.commandName == .versionCommand)
        #expect(codex.arguments == ["--version"])
        #expect(VersionCommand.displayCommand(providerID: .codex) == "codex --version")
    }

    @Test("AuthStatusCommand builds provider auth specs and parses auth state")
    func authStatusCommand() {
        let claude = AuthStatusCommand(providerID: .claude, executableURL: claudeURL).spec()
        #expect(claude.commandName == .authStatusCommand)
        #expect(claude.arguments == ["auth", "status", "--json"])
        #expect(claude.timeoutSeconds == 10)
        #expect(AuthStatusCommand.displayCommand(providerID: .claude) == "claude auth status --json")
        #expect(AuthStatusCommand.isAuthenticated(
            providerID: .claude,
            stdout: #"{"loggedIn":true}"#,
            exitCode: 0
        ))
        #expect(!AuthStatusCommand.isAuthenticated(
            providerID: .claude,
            stdout: #"{"loggedIn":false}"#,
            exitCode: 0
        ))

        let codex = AuthStatusCommand(providerID: .codex, executableURL: codexURL).spec()
        #expect(codex.commandName == .authStatusCommand)
        #expect(codex.arguments == ["login", "status"])
        #expect(AuthStatusCommand.displayCommand(providerID: .codex) == "codex login status")
        #expect(AuthStatusCommand.isAuthenticated(
            providerID: .codex,
            stdout: "Logged in using ChatGPT",
            exitCode: 0
        ))
        #expect(!AuthStatusCommand.isAuthenticated(
            providerID: .codex,
            stdout: "Not logged in",
            exitCode: 0
        ))
        // codex 0.132 prints the status to stderr with empty stdout.
        #expect(AuthStatusCommand.isAuthenticated(
            providerID: .codex,
            stdout: "",
            stderr: "Logged in using ChatGPT",
            exitCode: 0
        ))
        #expect(!AuthStatusCommand.isAuthenticated(
            providerID: .codex,
            stdout: "",
            stderr: "Not logged in",
            exitCode: 0
        ))
    }

    @Test("UsageCommand builds Claude usage launch arguments")
    func usageCommand() throws {
        let usage = UsageCommand(providerID: .claude, executableURL: claudeURL)
        #expect(try usage.claudeArguments(settingsJSON: "{}") == [
            "--setting-sources", "local",
            "--settings", "{}"
        ])
        #expect(UsageCommand.displayCommand(providerID: .claude) == "claude --settings '<C5h statusLine usage hook>'")

        let codexUsage = UsageCommand(providerID: .codex, executableURL: codexURL)
        #expect(UsageCommand.displayCommand(providerID: .codex) == "codex app-server -> account/rateLimits/read")
        do {
            _ = try codexUsage.claudeArguments(settingsJSON: "{}")
            Issue.record("Codex usage command should be unavailable")
        } catch {
            #expect(String(describing: error).contains("Codex usage reset detection is unavailable"))
        }
    }

    @Test("PromptCommand builds provider prompt specs")
    func promptCommand() {
        let input = TriggerPromptInput(prompt: "do work", projectPath: "/tmp/project")

        let claude = PromptCommand(providerID: .claude, executableURL: claudeURL, input: input).spec()
        #expect(claude.commandName == .promptCommand)
        #expect(claude.arguments == ["-p", "do work"])
        #expect(claude.workingDirectory?.path == "/tmp/project")
        #expect(claude.timeoutSeconds == 60 * 60 * 6)
        #expect(PromptCommand.displayCommand(providerID: .claude, prompt: "do work") == "claude -p 'do work'")

        let codex = PromptCommand(providerID: .codex, executableURL: codexURL, input: input).spec()
        #expect(codex.commandName == .promptCommand)
        #expect(codex.arguments == ["exec", "--skip-git-repo-check", "do work"])
        #expect(codex.workingDirectory?.path == "/tmp/project")
        #expect(codex.timeoutSeconds == 60 * 60 * 6)
        #expect(PromptCommand.displayCommand(providerID: .codex, prompt: "do work") == "codex exec --skip-git-repo-check 'do work'")
    }

    @Test("ProviderHealthState requires successful auth before ready")
    func healthStateRequiresAuth() {
        #expect(ProviderHealthState(from: ProviderStatus(
            providerID: .claude,
            isInstalled: true,
            isAuthenticated: true
        )) == .ready)
        #expect(ProviderHealthState(from: ProviderStatus(
            providerID: .claude,
            isInstalled: true,
            isAuthenticated: false
        )) == .authMissing)
        #expect(ProviderHealthState(from: ProviderStatus(
            providerID: .claude,
            isInstalled: true,
            isAuthenticated: nil
        )) == .unknown)
    }
}
