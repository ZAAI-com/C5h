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

    @Test("succeed exits 0 and stdout file contains 'ok'")
    func succeed() async throws {
        let dir = try TempDirectory.make()
        defer { try? TempDirectory.cleanup(dir) }
        let url = try Self.fakeCLIURL()
        let (runner, recorder) = Self.makeRunner(directory: dir)
        let result = try await runner.run(CommandSpec(
            providerID: .claude,
            runType: .testCommand,
            executableURL: url,
            arguments: ["succeed"],
            timeoutSeconds: 5
        ))

        #expect(result.status == .succeeded)
        #expect(result.exitCode == 0)
        let stdoutPath = try #require(result.stdoutPath)
        let stdout = try String(contentsOf: URL(fileURLWithPath: stdoutPath), encoding: .utf8)
        #expect(stdout.contains("fake-cli ok"))

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
            runType: .testCommand,
            executableURL: url,
            arguments: ["fail", "7"],
            timeoutSeconds: 5
        ))

        #expect(result.status == .failed)
        #expect(result.exitCode == 7)
    }

    @Test("timeout marks status timedOut")
    func timeout() async throws {
        let dir = try TempDirectory.make()
        defer { try? TempDirectory.cleanup(dir) }
        let url = try Self.fakeCLIURL()
        let (runner, _) = Self.makeRunner(directory: dir)

        let result = try await runner.run(CommandSpec(
            providerID: .claude,
            runType: .testCommand,
            executableURL: url,
            arguments: ["sleep", "10"],
            timeoutSeconds: 0.5
        ))

        #expect(result.status == .timedOut)
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
