import Foundation

public struct CommandRun: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var providerID: ProviderID
    public var runType: CommandRunType
    public var command: String
    public var argumentsJSON: String
    public var workingDirectory: String?
    public var startedAt: Date
    public var endedAt: Date?
    public var exitCode: Int32?
    public var status: CommandRunStatus
    public var stdoutPath: String?
    public var stderrPath: String?
    public var parsedEventsJSON: String?
    public var errorMessage: String?
    public var toolVersion: String?
    public var ownerPID: Int32?

    public init(
        id: UUID = UUID(),
        providerID: ProviderID,
        runType: CommandRunType,
        command: String,
        argumentsJSON: String,
        workingDirectory: String? = nil,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        exitCode: Int32? = nil,
        status: CommandRunStatus = .pending,
        stdoutPath: String? = nil,
        stderrPath: String? = nil,
        parsedEventsJSON: String? = nil,
        errorMessage: String? = nil,
        toolVersion: String? = nil,
        ownerPID: Int32? = nil
    ) {
        self.id = id
        self.providerID = providerID
        self.runType = runType
        self.command = command
        self.argumentsJSON = argumentsJSON
        self.workingDirectory = workingDirectory
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.exitCode = exitCode
        self.status = status
        self.stdoutPath = stdoutPath
        self.stderrPath = stderrPath
        self.parsedEventsJSON = parsedEventsJSON
        self.errorMessage = errorMessage
        self.toolVersion = toolVersion
        self.ownerPID = ownerPID
    }

    public var durationSeconds: Double? {
        guard let endedAt else { return nil }
        return endedAt.timeIntervalSince(startedAt)
    }
}

public enum CommandRunType: String, Codable, Sendable, CaseIterable {
    case detectStatus
    case authStatus
    case collectUsage
    case triggerPrompt
    case testCommand
}

public enum CommandRunStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case running
    case succeeded
    case failed
    case timedOut
    case cancelled
}
