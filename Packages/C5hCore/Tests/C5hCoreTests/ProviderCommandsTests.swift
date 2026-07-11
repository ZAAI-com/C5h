import Foundation
import Testing
@testable import C5hCore

@Suite("ProviderCommands")
struct ProviderCommandsTests {
    private let claudeURL = URL(fileURLWithPath: "/opt/homebrew/bin/claude")
    private let codexURL = URL(fileURLWithPath: "/usr/local/bin/codex")

    @Test("Version builds provider version specs")
    func versionCommand() {
        let claude = Version(providerID: .claude, executableURL: claudeURL).spec()
        #expect(claude.providerID == .claude)
        #expect(claude.commandName == .version)
        #expect(claude.executableURL == claudeURL)
        #expect(claude.arguments == ["--version"])
        #expect(claude.timeoutSeconds == 10)
        #expect(Version.displayCommand(providerID: .claude) == "claude --version")

        let codex = Version(providerID: .codex, executableURL: codexURL).spec()
        #expect(codex.providerID == .codex)
        #expect(codex.commandName == .version)
        #expect(codex.arguments == ["--version"])
        #expect(Version.displayCommand(providerID: .codex) == "codex --version")
    }

    @Test("AuthStatus builds provider auth specs and parses auth state")
    func authStatusCommand() {
        let claude = AuthStatus(providerID: .claude, executableURL: claudeURL).spec()
        #expect(claude.commandName == .authStatus)
        #expect(claude.arguments == ["auth", "status", "--json"])
        #expect(claude.timeoutSeconds == 10)
        #expect(AuthStatus.displayCommand(providerID: .claude) == "claude auth status --json")
        #expect(AuthStatus.isAuthenticated(
            providerID: .claude,
            stdout: #"{"loggedIn":true}"#,
            exitCode: 0
        ))
        #expect(!AuthStatus.isAuthenticated(
            providerID: .claude,
            stdout: #"{"loggedIn":false}"#,
            exitCode: 0
        ))

        let codex = AuthStatus(providerID: .codex, executableURL: codexURL).spec()
        #expect(codex.commandName == .authStatus)
        #expect(codex.arguments == ["login", "status"])
        #expect(AuthStatus.displayCommand(providerID: .codex) == "codex login status")
        #expect(AuthStatus.isAuthenticated(
            providerID: .codex,
            stdout: "Logged in using ChatGPT",
            exitCode: 0
        ))
        #expect(!AuthStatus.isAuthenticated(
            providerID: .codex,
            stdout: "Not logged in",
            exitCode: 0
        ))
        // codex 0.132 prints the status to stderr with empty stdout.
        #expect(AuthStatus.isAuthenticated(
            providerID: .codex,
            stdout: "",
            stderr: "Logged in using ChatGPT",
            exitCode: 0
        ))
        #expect(!AuthStatus.isAuthenticated(
            providerID: .codex,
            stdout: "",
            stderr: "Not logged in",
            exitCode: 0
        ))
    }

    @Test("Usage builds Claude usage launch arguments")
    func usageCommand() throws {
        let usage = Usage(providerID: .claude, executableURL: claudeURL)
        #expect(usage.timeoutSeconds == 30)
        #expect(try usage.claudeArguments(settingsJSON: "{}") == [
            "--setting-sources", "local",
            "--settings", "{}"
        ])
        #expect(
            Usage.displayCommand(providerID: .claude)
                == "claude --setting-sources local --settings '<C5h statusLine usage hook>'"
        )

        let codexUsage = Usage(providerID: .codex, executableURL: codexURL)
        #expect(Usage.displayCommand(providerID: .codex) == "codex app-server -> account/rateLimits/read")
        do {
            _ = try codexUsage.claudeArguments(settingsJSON: "{}")
            Issue.record("Codex usage command should be unavailable")
        } catch {
            #expect(String(describing: error).contains("Codex usage reset detection is unavailable"))
        }
    }

    @Test("Usage lock contention skips before creating a command run")
    func usageCommandLockContentionSkipsBeforeCommandRun() async throws {
        let dir = try TempDirectory.make()
        defer { try? TempDirectory.cleanup(dir) }
        let lockConfig = UsageProbeLockConfiguration(directory: dir)
        let acquiredLock = try UsageProbeLock.acquire(providerID: .claude, configuration: lockConfig)
        let lock = try #require(acquiredLock)
        let recorder = RunRecorder()
        let usage = Usage(
            providerID: .claude,
            executableURL: URL(fileURLWithPath: "/bin/echo"),
            timeoutSeconds: 0.1,
            lockConfiguration: lockConfig
        )

        do {
            _ = try await usage.collect(onStart: { run in await recorder.recordStart(run) })
            Issue.record("Second usage command should skip while provider lock is held")
        } catch C5hError.usageRefreshAlreadyRunning(let providerID) {
            #expect(providerID == .claude)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let calls = await recorder.calls
        #expect(calls.isEmpty)
        _ = lock
    }

    @Test("Claude usage timeout writes bounded PTY transcript to stderr log")
    func claudeUsageTimeoutWritesTranscript() async throws {
        let dir = try TempDirectory.make()
        defer { try? TempDirectory.cleanup(dir) }
        let script = dir.appendingPathComponent("hanging-claude")
        FileManager.default.createFile(
            atPath: script.path,
            contents: "#!/bin/sh\nprintf 'fake claude banner\\n'\nprintf 'args:%s\\n' \"$*\"\nsleep 5\n".data(using: .utf8)
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let store = CommandRunStore()
        let usage = Usage(
            providerID: .claude,
            executableURL: script,
            // 2s (not 0.5s): the collector drains the PTY every 0.1s until the
            // deadline, so a very short timeout captures too few reads and the
            // transcript can come back empty under concurrent test load. The
            // fake script sleeps 5s, so the probe still times out well before it.
            timeoutSeconds: 2,
            lockConfiguration: UsageProbeLockConfiguration(directory: dir.appendingPathComponent("locks"))
        )

        do {
            _ = try await usage.collect(
                logWriter: DiskLogWriter(baseDirectory: dir.appendingPathComponent("logs")),
                onComplete: { run in await store.record(run) }
            )
            Issue.record("Hanging Claude usage command should time out")
        } catch C5hError.processTimedOut {
            // expected
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let completedOptional = await store.completed
        let completed = try #require(completedOptional)
        #expect(completed.status == .timedOut)
        #expect(completed.errorMessage == "processTimedOut")
        let stderrPath = try #require(completed.stderrPath)
        let stderr = try String(contentsOf: URL(fileURLWithPath: stderrPath), encoding: .utf8)
        #expect(stderr.contains("processTimedOut"))
        #expect(stderr.contains("fake claude banner"))
        #expect(stderr.contains("args:--setting-sources local --settings"))
    }

    @Test("Claude usage collector reads statusLine payload file")
    func claudeUsageCollectorReadsStatusPayloadFile() async throws {
        let dir = try TempDirectory.make()
        defer { try? TempDirectory.cleanup(dir) }
        let script = dir.appendingPathComponent("file-backed-claude")
        FileManager.default.createFile(
            atPath: script.path,
            contents: """
            #!/bin/sh
            printf 'fake claude banner\\n'
            if [ -n "$C5H_USAGE_STATUS_PATH" ]; then
              printf '%s' '{"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":1778373600},"seven_day":{"used_percentage":57,"resets_at":1778893200}}}' > "$C5H_USAGE_STATUS_PATH"
            fi
            sleep 5
            """.data(using: .utf8)
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let store = CommandRunStore()
        let usage = Usage(
            providerID: .claude,
            executableURL: script,
            timeoutSeconds: 2,
            lockConfiguration: UsageProbeLockConfiguration(directory: dir.appendingPathComponent("locks"))
        )

        let snapshot = try await usage.collect(
            logWriter: DiskLogWriter(baseDirectory: dir.appendingPathComponent("logs")),
            onComplete: { run in await store.record(run) }
        )

        let completed = try #require(await store.completed)
        #expect(completed.status == .succeeded)
        #expect(snapshot.rawJSON.contains(#""used_percentage":42"#))
        #expect(snapshot.normalizedJSON.contains(#""usedPercentage":42"#))
    }

    @Test("Prompt builds provider prompt specs")
    func promptCommand() {
        let input = TriggerPromptInput(prompt: "do work", projectPath: "/tmp/project")

        let claude = Prompt(providerID: .claude, executableURL: claudeURL, input: input).spec()
        #expect(claude.commandName == .prompt)
        #expect(claude.arguments == ["-p", "do work"])
        #expect(claude.workingDirectory?.path == "/tmp/project")
        #expect(claude.timeoutSeconds == 60 * 60 * 6)
        #expect(Prompt.displayCommand(providerID: .claude, prompt: "do work") == "claude -p 'do work'")

        let codex = Prompt(providerID: .codex, executableURL: codexURL, input: input).spec()
        #expect(codex.commandName == .prompt)
        #expect(codex.arguments == ["exec", "--skip-git-repo-check", "do work"])
        #expect(codex.workingDirectory?.path == "/tmp/project")
        #expect(codex.timeoutSeconds == 60 * 60 * 6)
        #expect(Prompt.displayCommand(providerID: .codex, prompt: "do work") == "codex exec --skip-git-repo-check 'do work'")
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

actor CommandRunStore {
    var completed: CommandRun?

    func record(_ run: CommandRun) {
        completed = run
    }
}
