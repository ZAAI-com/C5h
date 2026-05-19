import Foundation
import C5hCore

#if DEBUG
/// In debug builds the helper executable lives in the SwiftPM build folder
/// rather than the app bundle, so `SMAppService.agent` can't find it. This
/// runner spawns the helper as a managed subprocess of the main app to
/// exercise the same scheduler loop end-to-end during development.
@MainActor
final class HelperDevModeRunner {
    private(set) var process: LaunchedProcess?
    private(set) var lastError: String?

    var isRunning: Bool {
        process?.isRunning ?? false
    }

    func start() {
        if isRunning { return }
        let url = Self.helperBinaryURL()
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            lastError = "Helper binary missing at \(url.path) — run `swift build --package-path Packages/C5hHelper` first."
            return
        }

        let stdoutURL = URL(fileURLWithPath: "/tmp/c5hhelper.dev.out")
        let stderrURL = URL(fileURLWithPath: "/tmp/c5hhelper.dev.err")
        do {
            let stdoutHandle = try Self.truncatedLogHandle(at: stdoutURL)
            let stderrHandle = try Self.truncatedLogHandle(at: stderrURL)
            defer {
                try? stdoutHandle.close()
                try? stderrHandle.close()
            }

            process = try DisclaimingSpawn.launch(
                executableURL: url,
                arguments: [],
                environment: EnvironmentResolver.defaultEnvironment(),
                stdout: .fileHandle(stdoutHandle),
                stderr: .fileHandle(stderrHandle)
            )
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
    }

    func stop() {
        guard let process else { return }
        process.terminate()
        Task.detached(priority: .utility) {
            _ = process.waitBlocking()
        }
        self.process = nil
    }

    private static func truncatedLogHandle(at url: URL) throws -> FileHandle {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 0)
        return handle
    }

    private static func helperBinaryURL() -> URL {
        let cwd = FileManager.default.currentDirectoryPath
        let candidates = [
            URL(fileURLWithPath: cwd)
                .appendingPathComponent("Packages/C5hHelper/.build/debug/C5hHelper"),
            URL(fileURLWithPath: cwd)
                .appendingPathComponent("Packages/C5hHelper/.build/arm64-apple-macosx/debug/C5hHelper"),
            URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Manuel-Sun/Engineering/Conductor/workspaces/C5h/albuquerque-v1/Packages/C5hHelper/.build/debug/C5hHelper")
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c.path) {
            return c
        }
        return candidates[0]
    }
}
#endif
