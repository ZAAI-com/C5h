import Foundation
import C5hCore

#if DEBUG
/// In debug builds the helper executable lives in the SwiftPM build folder
/// rather than the app bundle, so `SMAppService.agent` can't find it. This
/// runner spawns the helper as a managed subprocess of the main app to
/// exercise the same scheduler loop end-to-end during development.
@MainActor
final class HelperDevModeRunner {
    private(set) var process: Process?
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
        let p = Process()
        p.executableURL = url
        p.environment = EnvironmentResolver.defaultEnvironment()
        p.standardOutput = FileHandle(forWritingAtPath: "/tmp/c5hhelper.dev.out") ?? FileHandle.standardOutput
        p.standardError = FileHandle(forWritingAtPath: "/tmp/c5hhelper.dev.err") ?? FileHandle.standardError
        do {
            try p.run()
            process = p
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
    }

    func stop() {
        process?.terminate()
        process = nil
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
