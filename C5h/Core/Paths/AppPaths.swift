import Foundation

struct AppPaths: Sendable {
    let appSupportDirectory: URL
    let databaseURL: URL
    let logsDirectory: URL
    let commandRunsDirectory: URL

    static func live() throws -> AppPaths {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("C5h", isDirectory: true)

        let logs = base.appendingPathComponent("logs", isDirectory: true)
        let commandRuns = logs.appendingPathComponent("command-runs", isDirectory: true)

        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: commandRuns, withIntermediateDirectories: true)

        return AppPaths(
            appSupportDirectory: base,
            databaseURL: base.appendingPathComponent("c5h.sqlite"),
            logsDirectory: logs,
            commandRunsDirectory: commandRuns
        )
    }
}
