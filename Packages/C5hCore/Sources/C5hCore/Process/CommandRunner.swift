import Foundation
import Darwin

public protocol CommandRunning: Sendable {
    func run(_ spec: CommandSpec, runID: UUID) async throws -> CommandRun
}

public extension CommandRunning {
    func run(_ spec: CommandSpec) async throws -> CommandRun {
        try await run(spec, runID: UUID())
    }
}

public actor CommandRunner: CommandRunning {
    public typealias OnEvent = @Sendable (CommandRun) async throws -> Void

    fileprivate struct ProcessOutcome: Sendable {
        enum Kind: Sendable {
            case completed(Int32)
            case timedOut
            case cancelled
            case launchFailed(String)
        }
        let kind: Kind
    }

    private let logWriter: any FileLogWriting
    private let onStart: OnEvent
    private let onComplete: OnEvent

    public init(
        logWriter: any FileLogWriting,
        onStart: @escaping OnEvent,
        onComplete: @escaping OnEvent
    ) {
        self.logWriter = logWriter
        self.onStart = onStart
        self.onComplete = onComplete
    }

    public func run(_ spec: CommandSpec, runID: UUID = UUID()) async throws -> CommandRun {
        let id = runID
        let startedAt = Date()
        let logPaths = try logWriter.makeLogPaths(for: id, at: startedAt)

        var run = CommandRun(
            id: id,
            providerID: spec.providerID,
            runType: spec.runType,
            command: spec.executableURL.path,
            argumentsJSON: spec.argumentsJSON(),
            workingDirectory: spec.workingDirectory?.path,
            startedAt: startedAt,
            status: .running,
            stdoutPath: logPaths.stdoutURL.path,
            stderrPath: logPaths.stderrURL.path,
            toolVersion: spec.toolVersion,
            ownerPID: getpid()
        )
        try await onStart(run)

        let outcome: ProcessOutcome
        do {
            outcome = try await execute(spec: spec, logPaths: logPaths)
        } catch {
            run.status = .failed
            run.endedAt = Date()
            run.errorMessage = String(describing: error)
            try await onComplete(run)
            throw error
        }

        run.endedAt = Date()
        switch outcome.kind {
        case .completed(let exitCode):
            run.exitCode = exitCode
            run.status = exitCode == 0 ? .succeeded : .failed
        case .timedOut:
            run.status = .timedOut
            run.errorMessage = "Timed out after \(Int(spec.timeoutSeconds))s"
        case .cancelled:
            run.status = .cancelled
            run.errorMessage = "Cancelled"
        case .launchFailed(let message):
            run.status = .failed
            run.errorMessage = message
        }
        try await onComplete(run)
        return run
    }

    private func execute(spec: CommandSpec, logPaths: LogFilePaths) async throws -> ProcessOutcome {
        let stdoutLog = FileHandle(forWritingAtPath: logPaths.stdoutURL.path)
        let stderrLog = FileHandle(forWritingAtPath: logPaths.stderrURL.path)

        let launched: LaunchedProcess
        do {
            launched = try DisclaimingSpawn.launch(
                executableURL: spec.executableURL,
                arguments: spec.arguments,
                environment: spec.environment,
                workingDirectory: spec.workingDirectory,
                stdin: .devNull,
                stdout: .pipe,
                stderr: .pipe
            )
        } catch {
            try? stdoutLog?.close()
            try? stderrLog?.close()
            return ProcessOutcome(kind: .launchFailed(String(describing: error)))
        }

        launched.stdoutHandle?.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            try? stdoutLog?.write(contentsOf: data)
        }
        launched.stderrHandle?.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            try? stderrLog?.write(contentsOf: data)
        }

        let outcome = await withTaskCancellationHandler {
            await withTaskGroup(of: ProcessOutcome.Kind.self) { group in
                group.addTask {
                    let code = await launched.wait()
                    return .completed(code)
                }
                group.addTask {
                    let nanos = UInt64(spec.timeoutSeconds * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: nanos)
                    if Task.isCancelled { return .cancelled }
                    if launched.isRunning {
                        launched.terminate()
                        return .timedOut
                    }
                    return .completed(launched.waitBlocking())
                }
                let first = await group.next() ?? .launchFailed("no outcome")
                group.cancelAll()
                return first
            }
        } onCancel: {
            launched.terminate()
        }

        launched.stdoutHandle?.readabilityHandler = nil
        launched.stderrHandle?.readabilityHandler = nil
        if launched.isRunning {
            launched.terminate()
            _ = launched.waitBlocking()
        }
        // Drain any bytes that landed in the pipe buffer after the
        // readabilityHandler was cleared. Without this, fast-exiting
        // processes can leave a few bytes unread under parallel test
        // execution where GCD's readability queue is contended.
        if let h = launched.stdoutHandle { Self.drain(handle: h, into: stdoutLog) }
        if let h = launched.stderrHandle { Self.drain(handle: h, into: stderrLog) }
        try? stdoutLog?.close()
        try? stderrLog?.close()

        if Task.isCancelled {
            return ProcessOutcome(kind: .cancelled)
        }
        return ProcessOutcome(kind: outcome)
    }

    private static func drain(handle: FileHandle, into log: FileHandle?) {
        // Non-blocking read so a still-running grandchild (e.g. an orphan
        // `sleep` inherited from a terminated shell) holding the pipe open
        // doesn't stall us — we only want what's already buffered.
        let fd = handle.fileDescriptor
        let flags = fcntl(fd, F_GETFL, 0)
        if flags >= 0 { _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK) }
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let n = buffer.withUnsafeMutableBufferPointer { buf -> Int in
                Darwin.read(fd, buf.baseAddress, buf.count)
            }
            if n > 0 {
                try? log?.write(contentsOf: Data(bytes: buffer, count: n))
            } else if n == 0 {
                break
            } else {
                if errno == EINTR { continue }
                break
            }
        }
    }
}
