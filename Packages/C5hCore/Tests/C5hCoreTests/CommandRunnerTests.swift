import Foundation
import Testing
@testable import C5hCore

@Suite("CommandRunner")
struct CommandRunnerTests {
    private static func fakeCLIURL() throws -> URL {
        guard let url = Bundle.module.url(forResource: "fake-cli", withExtension: "sh") else {
            Issue.record("fake-cli.sh resource not found in test bundle")
            throw C5hError.cliNotFound("fake-cli.sh")
        }
        return url
    }

    private static func makeRunner(directory: URL) -> (CommandRunner, RunRecorder) {
        let writer = DiskLogWriter(baseDirectory: directory)
        let recorder = RunRecorder()
        let runner = CommandRunner(
            logWriter: writer,
            onStart: { run in await recorder.recordStart(run) },
            onComplete: { run in await recorder.recordComplete(run) }
        )
        return (runner, recorder)
    }

    private static func stdout(_ run: CommandRun) throws -> String {
        let path = try #require(run.stdoutPath)
        return try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
    }

    private static func stderr(_ run: CommandRun) throws -> String {
        let path = try #require(run.stderrPath)
        return try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
    }

    @Test("succeed exits 0 and stdout file contains 'ok'")
    func succeed() async throws {
        let dir = try TempDirectory.make()
        defer { try? TempDirectory.cleanup(dir) }
        let url = try Self.fakeCLIURL()
        let (runner, recorder) = Self.makeRunner(directory: dir)
        let result = try await runner.run(CommandSpec(
            providerID: .claude,
            commandName: .version,
            executableURL: url,
            arguments: ["succeed"],
            timeoutSeconds: 5
        ))

        #expect(result.status == .succeeded)
        #expect(result.exitCode == 0)
        #expect(try Self.stdout(result).contains("fake-cli ok"))

        let calls = await recorder.calls
        #expect(calls == ["start", "complete"])
    }

    @Test("fail records exit code and failed status")
    func fail() async throws {
        let dir = try TempDirectory.make()
        defer { try? TempDirectory.cleanup(dir) }
        let url = try Self.fakeCLIURL()
        let (runner, _) = Self.makeRunner(directory: dir)

        let result = try await runner.run(CommandSpec(
            providerID: .codex,
            commandName: .version,
            executableURL: url,
            arguments: ["fail", "7"],
            timeoutSeconds: 5
        ))

        #expect(result.status == .failed)
        #expect(result.exitCode == 7)
    }

    @Test("stderr is captured")
    func stderrCapture() async throws {
        let dir = try TempDirectory.make()
        defer { try? TempDirectory.cleanup(dir) }
        let url = try Self.fakeCLIURL()
        let (runner, _) = Self.makeRunner(directory: dir)

        let result = try await runner.run(CommandSpec(
            providerID: .codex,
            commandName: .version,
            executableURL: url,
            arguments: ["echo-stderr", "problem details"],
            timeoutSeconds: 5
        ))

        #expect(result.status == .succeeded)
        #expect(try Self.stderr(result).contains("problem details"))
    }

    @Test("environment is passed to child process")
    func environment() async throws {
        let dir = try TempDirectory.make()
        defer { try? TempDirectory.cleanup(dir) }
        let url = try Self.fakeCLIURL()
        let (runner, _) = Self.makeRunner(directory: dir)
        var environment = EnvironmentResolver.defaultEnvironment()
        environment["C5H_TEST_ENV"] = "from-test"

        let result = try await runner.run(CommandSpec(
            providerID: .claude,
            commandName: .version,
            executableURL: url,
            arguments: ["echo-env", "C5H_TEST_ENV"],
            environment: environment,
            timeoutSeconds: 5
        ))

        #expect(result.status == .succeeded)
        #expect(try Self.stdout(result).trimmingCharacters(in: .whitespacesAndNewlines) == "from-test")
    }

    @Test("working directory is passed to child process")
    func workingDirectory() async throws {
        let dir = try TempDirectory.make()
        defer { try? TempDirectory.cleanup(dir) }
        let workdir = try TempDirectory.make()
        defer { try? TempDirectory.cleanup(workdir) }
        let url = try Self.fakeCLIURL()
        let (runner, _) = Self.makeRunner(directory: dir)

        let result = try await runner.run(CommandSpec(
            providerID: .claude,
            commandName: .version,
            executableURL: url,
            arguments: ["pwd"],
            workingDirectory: workdir,
            timeoutSeconds: 5
        ))

        #expect(result.status == .succeeded)
        let actual = URL(fileURLWithPath: try Self.stdout(result).trimmingCharacters(in: .whitespacesAndNewlines))
            .resolvingSymlinksInPath()
            .path
        let expected = workdir.resolvingSymlinksInPath().path
        #expect(actual == expected)
    }

    @Test("large stdout is drained")
    func largeOutput() async throws {
        let dir = try TempDirectory.make()
        defer { try? TempDirectory.cleanup(dir) }
        let url = try Self.fakeCLIURL()
        let (runner, _) = Self.makeRunner(directory: dir)

        let result = try await runner.run(CommandSpec(
            providerID: .claude,
            commandName: .version,
            executableURL: url,
            arguments: ["spam", "262144"],
            timeoutSeconds: 5
        ))

        #expect(result.status == .succeeded)
        #expect(try Self.stdout(result).utf8.count > 200_000)
    }

    @Test("timeout marks status timedOut")
    func timeout() async throws {
        let dir = try TempDirectory.make()
        defer { try? TempDirectory.cleanup(dir) }
        let url = try Self.fakeCLIURL()
        let (runner, _) = Self.makeRunner(directory: dir)

        let result = try await runner.run(CommandSpec(
            providerID: .claude,
            commandName: .version,
            executableURL: url,
            arguments: ["sleep", "10"],
            timeoutSeconds: 0.5
        ))

        #expect(result.status == .timedOut)
    }

    @Test("cancellation marks status cancelled")
    func cancellation() async throws {
        let dir = try TempDirectory.make()
        defer { try? TempDirectory.cleanup(dir) }
        let url = try Self.fakeCLIURL()
        let (runner, recorder) = Self.makeRunner(directory: dir)

        let task = Task {
            try await runner.run(CommandSpec(
                providerID: .claude,
                commandName: .version,
                executableURL: url,
                arguments: ["sleep", "10"],
                timeoutSeconds: 30
            ))
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        let result = try await task.value
        #expect(result.status == .cancelled)
        #expect(result.errorMessage == "Cancelled")

        let calls = await recorder.calls
        #expect(calls == ["start", "complete"])
    }
}

actor RunRecorder {
    var calls: [String] = []
    func recordStart(_ run: CommandRun) async { calls.append("start") }
    func recordComplete(_ run: CommandRun) async { calls.append("complete") }
}

enum TempDirectory {
    static func make() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "c5h-runner-test-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func cleanup(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}
