#if DEBUG
import Foundation
import C5hCore
import C5hStore

enum LogsFixtureLoader {
    static func loadIfNeeded(
        repository: any CommandRunRepository,
        appPaths: AppPaths
    ) async {
        do {
            let existing = try await repository.fetchRecent(limit: 1, filter: CommandRunFilter())
            guard existing.isEmpty else { return }
        } catch {
            return
        }

        let cal = Calendar.current
        let now = Date()
        let runs: [(CommandRun, String, String?)] = [
            makeRun(
                provider: .claude, commandName: .promptCommand, status: .succeeded,
                exit: 0, startedMinutesAgo: 30, durationSeconds: 18,
                command: "/opt/homebrew/bin/claude",
                args: ["-p", "Continue refactoring the auth module"],
                cwd: "/Users/dev/projects/widget", toolVersion: "claude 1.4.0",
                stdout: """
                Welcome to Claude Code!
                I'm reading the project context now…
                Found 14 source files. Working on AuthModule.swift…
                Refactor complete. 3 files changed.
                """,
                stderr: nil,
                base: cal.date(byAdding: .minute, value: -30, to: now) ?? now
            ),
            makeRun(
                provider: .codex, commandName: .promptCommand, status: .succeeded,
                exit: 0, startedMinutesAgo: 18, durationSeconds: 22,
                command: "/usr/local/bin/codex",
                args: ["chat", "-p", "Implement pagination on /users endpoint"],
                cwd: "/Users/dev/projects/api", toolVersion: "codex 0.9.2",
                stdout: """
                {"kind":"start","provider":"codex"}
                {"kind":"plan","steps":["Add pagination params","Update query","Test"]}
                {"kind":"done","files_changed":2}
                """,
                stderr: nil,
                base: cal.date(byAdding: .minute, value: -18, to: now) ?? now
            ),
            makeRun(
                provider: .claude, commandName: .versionCommand, status: .failed,
                exit: 1, startedMinutesAgo: 12, durationSeconds: 4,
                command: "/opt/homebrew/bin/claude",
                args: ["--version"],
                cwd: nil, toolVersion: nil,
                stdout: nil,
                stderr: "Error: command not authorized. Run `claude login` first.",
                base: cal.date(byAdding: .minute, value: -12, to: now) ?? now
            ),
            makeRun(
                provider: .codex, commandName: .versionCommand, status: .succeeded,
                exit: 0, startedMinutesAgo: 6, durationSeconds: 1,
                command: "/usr/local/bin/codex",
                args: ["--version"],
                cwd: nil, toolVersion: "codex 0.9.2",
                stdout: "codex 0.9.2 (build a1b2c3)\n",
                stderr: nil,
                base: cal.date(byAdding: .minute, value: -6, to: now) ?? now
            ),
            makeRun(
                provider: .claude, commandName: .promptCommand, status: .timedOut,
                exit: nil, startedMinutesAgo: 60 * 26, durationSeconds: 600,
                command: "/opt/homebrew/bin/claude",
                args: ["-p", "Run the full test suite and fix any failures"],
                cwd: "/Users/dev/projects/widget", toolVersion: "claude 1.4.0",
                stdout: "Running tests…\n[stalled]",
                stderr: "Timed out after 600 seconds.",
                base: cal.date(byAdding: .hour, value: -26, to: now) ?? now
            ),
            makeRun(
                provider: .claude, commandName: .usageCommand, status: .succeeded,
                exit: 0, startedMinutesAgo: 60 * 8, durationSeconds: 2,
                command: "/opt/homebrew/bin/claude",
                args: ["--setting-sources", "local", "--settings", "{statusLine:{...}}"],
                cwd: nil, toolVersion: "claude 1.4.0",
                stdout: "{\"messages\":42,\"window_started_at\":\"…\"}",
                stderr: nil,
                base: cal.date(byAdding: .hour, value: -8, to: now) ?? now
            ),
            makeRun(
                provider: .codex, commandName: .authStatusCommand, status: .succeeded,
                exit: 0, startedMinutesAgo: 60 * 24 * 2, durationSeconds: 1,
                command: "/usr/local/bin/codex",
                args: ["login", "status"],
                cwd: nil, toolVersion: "codex 0.9.1",
                stdout: "Logged in using ChatGPT\n",
                stderr: nil,
                base: cal.date(byAdding: .day, value: -2, to: now) ?? now
            ),
            makeRun(
                provider: .codex, commandName: .promptCommand, status: .cancelled,
                exit: nil, startedMinutesAgo: 60 * 24 * 3, durationSeconds: 8,
                command: "/usr/local/bin/codex",
                args: ["chat", "-p", "Refactor logging"],
                cwd: "/Users/dev/projects/api", toolVersion: "codex 0.9.1",
                stdout: "{\"kind\":\"start\"}\n",
                stderr: "User cancelled.",
                base: cal.date(byAdding: .day, value: -3, to: now) ?? now
            )
        ]

        let fm = FileManager.default
        for (run, stdout, stderr) in runs {
            do {
                let monthDir = appPaths.commandRunsDirectory.appendingPathComponent(
                    monthFolder(for: run.startedAt),
                    isDirectory: true
                )
                try fm.createDirectory(at: monthDir, withIntermediateDirectories: true)
                let stdoutURL = monthDir.appendingPathComponent("\(run.id.uuidString).stdout.log")
                let stderrURL = monthDir.appendingPathComponent("\(run.id.uuidString).stderr.log")
                try (stdout + "\n").write(to: stdoutURL, atomically: true, encoding: .utf8)
                if let stderr {
                    try stderr.write(to: stderrURL, atomically: true, encoding: .utf8)
                }

                var augmented = run
                augmented.stdoutPath = stdoutURL.path
                if stderr != nil {
                    augmented.stderrPath = stderrURL.path
                }
                try await repository.create(augmented)
            } catch {
                NSLog("LogsFixtureLoader failed for \(run.id): \(error)")
            }
        }
    }

    private static func makeRun(
        provider: ProviderID,
        commandName: CommandName,
        status: CommandRunStatus,
        exit: Int32?,
        startedMinutesAgo _: Int,
        durationSeconds: Int,
        command: String,
        args: [String],
        cwd: String?,
        toolVersion: String?,
        stdout: String?,
        stderr: String?,
        base: Date
    ) -> (CommandRun, String, String?) {
        let argsJSON = (try? String(data: JSONEncoder().encode(args), encoding: .utf8)) ?? "[]"
        let ended = base.addingTimeInterval(TimeInterval(durationSeconds))
        let run = CommandRun(
            providerID: provider,
            commandName: commandName,
            command: command,
            argumentsJSON: argsJSON,
            workingDirectory: cwd,
            startedAt: base,
            endedAt: ended,
            exitCode: exit,
            status: status,
            stdoutPath: nil,
            stderrPath: nil,
            parsedEventsJSON: nil,
            errorMessage: stderr,
            toolVersion: toolVersion
        )
        return (run, stdout ?? "", stderr)
    }

    private static func monthFolder(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }
}
#endif
