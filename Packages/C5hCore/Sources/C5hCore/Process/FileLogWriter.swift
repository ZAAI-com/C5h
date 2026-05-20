import Foundation

public protocol FileLogWriting: Sendable {
    func makeLogPaths(for runID: UUID, at startedAt: Date) throws -> LogFilePaths
}

public struct LogFilePaths: Sendable {
    public let stdoutURL: URL
    public let stderrURL: URL
}

public struct DiskLogWriter: FileLogWriting {
    private let baseDirectory: URL

    public init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }

    public func makeLogPaths(for runID: UUID, at startedAt: Date) throws -> LogFilePaths {
        let monthFolder = Self.monthFolder(for: startedAt)
        let dir = baseDirectory.appendingPathComponent(monthFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stdout = dir.appendingPathComponent("\(runID.uuidString).stdout.log")
        let stderr = dir.appendingPathComponent("\(runID.uuidString).stderr.log")
        FileManager.default.createFile(atPath: stdout.path, contents: nil)
        FileManager.default.createFile(atPath: stderr.path, contents: nil)
        return LogFilePaths(stdoutURL: stdout, stderrURL: stderr)
    }

    static func monthFolder(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }
}
