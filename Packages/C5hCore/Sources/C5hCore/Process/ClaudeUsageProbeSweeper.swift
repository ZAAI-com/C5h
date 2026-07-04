import Foundation
import Darwin
import Dispatch

public struct ClaudeUsageProbeSweeper: Sendable {
    public struct ProcessCandidate: Sendable, Equatable {
        public var pid: Int32
        public var parentPID: Int32
        public var command: String

        public init(pid: Int32, parentPID: Int32, command: String) {
            self.pid = pid
            self.parentPID = parentPID
            self.command = command
        }
    }

    public var listProcesses: @Sendable () throws -> [ProcessCandidate]
    public var terminate: @Sendable (Int32) -> Bool

    public init(
        listProcesses: @escaping @Sendable () throws -> [ProcessCandidate] = Self.liveProcessList,
        terminate: @escaping @Sendable (Int32) -> Bool = Self.terminateProcess
    ) {
        self.listProcesses = listProcesses
        self.terminate = terminate
    }

    @discardableResult
    public func sweepOrphanedUsageProbes() throws -> Int {
        var count = 0
        for process in try listProcesses() where Self.isOrphanedC5hClaudeUsageProbe(process) {
            if terminate(process.pid) {
                count += 1
            }
        }
        return count
    }

    public static func isOrphanedC5hClaudeUsageProbe(_ process: ProcessCandidate) -> Bool {
        guard process.parentPID == 1 else { return false }
        let command = process.command
        guard command.contains("C5H_RATE_LIMITS"),
              command.contains("--settings") else {
            return false
        }
        guard let executable = command.split(maxSplits: 1, whereSeparator: \.isWhitespace).first else {
            return false
        }
        return executable == "claude" || executable.hasSuffix("/claude")
    }

    public static func liveProcessList() throws -> [ProcessCandidate] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid=,command="]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()

        let group = DispatchGroup()
        let stdoutCapture = PipeCapture(stdout.fileHandleForReading)
        let stderrCapture = PipeCapture(stderr.fileHandleForReading)
        stdoutCapture.drain(on: .global(qos: .utility), group: group)
        stderrCapture.drain(on: .global(qos: .utility), group: group)

        process.waitUntilExit()
        group.wait()
        guard process.terminationStatus == 0 else {
            let err = String(data: stderrCapture.data, encoding: .utf8) ?? ""
            throw C5hError.processLaunchFailed("ps failed: \(err)")
        }
        let raw = String(data: stdoutCapture.data, encoding: .utf8) ?? ""
        return raw.split(separator: "\n").compactMap(parseProcessLine)
    }

    private static func parseProcessLine(_ line: Substring) -> ProcessCandidate? {
        let parts = line.split(maxSplits: 2, whereSeparator: \.isWhitespace)
        guard parts.count == 3,
              let pid = Int32(String(parts[0])),
              let ppid = Int32(String(parts[1])) else {
            return nil
        }
        return ProcessCandidate(pid: pid, parentPID: ppid, command: String(parts[2]))
    }

    public static func terminateProcess(_ pid: Int32) -> Bool {
        Darwin.kill(pid, SIGTERM) == 0
    }
}

private final class PipeCapture: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    private var storage = Data()

    init(_ handle: FileHandle) {
        self.handle = handle
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func drain(on queue: DispatchQueue, group: DispatchGroup) {
        group.enter()
        queue.async {
            defer { group.leave() }
            let data = self.handle.readDataToEndOfFile()
            self.lock.lock()
            self.storage = data
            self.lock.unlock()
        }
    }
}
