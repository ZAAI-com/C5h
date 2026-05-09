import Foundation
import GRDB
import C5hCore

struct ScheduledPromptRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "scheduled_prompts"

    var id: String
    var providerId: String
    var plannedWindowId: String?
    var prompt: String
    var projectPath: String?
    var runAt: String
    var status: String
    var attempts: Int
    var lastError: String?
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case providerId = "provider_id"
        case plannedWindowId = "planned_window_id"
        case prompt
        case projectPath = "project_path"
        case runAt = "run_at"
        case status
        case attempts
        case lastError = "last_error"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from prompt: ScheduledPrompt) {
        self.id = prompt.id.uuidString
        self.providerId = prompt.providerID.rawValue
        self.plannedWindowId = prompt.plannedWindowID?.uuidString
        self.prompt = prompt.prompt
        self.projectPath = prompt.projectPath
        self.runAt = DateTimeService.formatUTC(prompt.runAt)
        self.status = prompt.status.rawValue
        self.attempts = prompt.attempts
        self.lastError = prompt.lastError
        self.createdAt = DateTimeService.formatUTC(prompt.createdAt)
        self.updatedAt = DateTimeService.formatUTC(prompt.updatedAt)
    }

    func toScheduledPrompt() throws -> ScheduledPrompt {
        guard
            let uuid = UUID(uuidString: id),
            let pid = ProviderID(rawValue: providerId),
            let runDate = DateTimeService.parseUTC(runAt),
            let st = ScheduledPromptStatus(rawValue: status)
        else {
            throw C5hError.databaseError("Invalid ScheduledPromptRecord: \(id)")
        }
        return ScheduledPrompt(
            id: uuid,
            providerID: pid,
            plannedWindowID: plannedWindowId.flatMap(UUID.init),
            prompt: prompt,
            projectPath: projectPath,
            runAt: runDate,
            status: st,
            attempts: attempts,
            lastError: lastError,
            createdAt: DateTimeService.parseUTC(createdAt) ?? .now,
            updatedAt: DateTimeService.parseUTC(updatedAt) ?? .now
        )
    }
}
