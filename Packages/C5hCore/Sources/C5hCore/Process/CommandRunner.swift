import Foundation

public protocol CommandRunning: Sendable {
    func run(_ spec: CommandSpec) async throws -> CommandRun
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

    public func run(_ spec: CommandSpec) async throws -> CommandRun {
        let id = UUID()
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
            toolVersion: spec.toolVersion
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
        let process = Process()
        process.executableURL = spec.executableURL
        process.arguments = spec.arguments
        if let cwd = spec.workingDirectory {
            process.currentDirectoryURL = cwd
        }
        if !spec.environment.isEmpty {
            process.environment = spec.environment
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutHandle = FileHandle(forWritingAtPath: logPaths.stdoutURL.path)
        let stderrHandle = FileHandle(forWritingAtPath: logPaths.stderrURL.path)

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            try? stdoutHandle?.write(contentsOf: data)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            try? stderrHandle?.write(contentsOf: data)
        }

        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            try? stdoutHandle?.close()
            try? stderrHandle?.close()
            return ProcessOutcome(kind: .launchFailed(String(describing: error)))
        }

        let outcome = await withTaskGroup(of: ProcessOutcome.Kind.self) { group in
            group.addTask {
                await waitForExit(process: process)
            }
            group.addTask {
                let nanos = UInt64(spec.timeoutSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                if Task.isCancelled { return .cancelled }
                if process.isRunning {
                    process.terminate()
                    return .timedOut
                }
                return .completed(process.terminationStatus)
            }
            let first = await group.next() ?? .launchFailed("no outcome")
            group.cancelAll()
            return first
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        try? stdoutHandle?.close()
        try? stderrHandle?.close()

        if Task.isCancelled {
            return ProcessOutcome(kind: .cancelled)
        }
        return ProcessOutcome(kind: outcome)
    }
}

private func waitForExit(process: Process) async -> CommandRunner.ProcessOutcome.Kind {
    await withCheckedContinuation { (cont: CheckedContinuation<CommandRunner.ProcessOutcome.Kind, Never>) in
        process.terminationHandler = { p in
            cont.resume(returning: .completed(p.terminationStatus))
        }
    }
}
