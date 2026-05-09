import Foundation
import GRDB
import C5hCore

struct CommandRunRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "command_runs"

    var id: String
    var providerId: String
    var runType: String
    var command: String
    var argumentsJson: String
    var cwd: String?
    var startedAt: String
    var endedAt: String?
    var exitCode: Int?
    var status: String
    var stdoutPath: String?
    var stderrPath: String?
    var parsedEventsJson: String?
    var error: String?
    var toolVersion: String?

    enum CodingKeys: String, CodingKey {
        case id
        case providerId = "provider_id"
        case runType = "run_type"
        case command
        case argumentsJson = "arguments_json"
        case cwd
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case exitCode = "exit_code"
        case status
        case stdoutPath = "stdout_path"
        case stderrPath = "stderr_path"
        case parsedEventsJson = "parsed_events_json"
        case error
        case toolVersion = "tool_version"
    }

    init(from run: CommandRun) {
        self.id = run.id.uuidString
        self.providerId = run.providerID.rawValue
        self.runType = run.runType.rawValue
        self.command = run.command
        self.argumentsJson = run.argumentsJSON
        self.cwd = run.workingDirectory
        self.startedAt = DateTimeService.formatUTC(run.startedAt)
        self.endedAt = run.endedAt.map(DateTimeService.formatUTC)
        self.exitCode = run.exitCode.map { Int($0) }
        self.status = run.status.rawValue
        self.stdoutPath = run.stdoutPath
        self.stderrPath = run.stderrPath
        self.parsedEventsJson = run.parsedEventsJSON
        self.error = run.errorMessage
        self.toolVersion = run.toolVersion
    }

    func toCommandRun() throws -> CommandRun {
        guard
            let uuid = UUID(uuidString: id),
            let pid = ProviderID(rawValue: providerId),
            let rtype = CommandRunType(rawValue: runType),
            let started = DateTimeService.parseUTC(startedAt),
            let st = CommandRunStatus(rawValue: status)
        else {
            throw C5hError.databaseError("Invalid CommandRunRecord: \(id)")
        }
        return CommandRun(
            id: uuid,
            providerID: pid,
            runType: rtype,
            command: command,
            argumentsJSON: argumentsJson,
            workingDirectory: cwd,
            startedAt: started,
            endedAt: endedAt.flatMap(DateTimeService.parseUTC),
            exitCode: exitCode.map { Int32($0) },
            status: st,
            stdoutPath: stdoutPath,
            stderrPath: stderrPath,
            parsedEventsJSON: parsedEventsJson,
            errorMessage: error,
            toolVersion: toolVersion
        )
    }
}
