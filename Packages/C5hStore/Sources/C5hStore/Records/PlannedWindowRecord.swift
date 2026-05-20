import Foundation
import GRDB
import C5hCore

struct PlannedWindowRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "planned_windows"

    var id: String
    var providerId: String
    var startAt: String
    var durationSeconds: Int
    var promptTemplateId: String?
    var projectPath: String?
    var status: String
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case providerId = "provider_id"
        case startAt = "start_at"
        case durationSeconds = "duration_seconds"
        case promptTemplateId = "prompt_template_id"
        case projectPath = "project_path"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from window: PlannedWindow) {
        self.id = window.id.uuidString
        self.providerId = window.providerID.rawValue
        self.startAt = DateTimeService.formatUTC(window.startAt)
        self.durationSeconds = window.durationSeconds
        self.promptTemplateId = window.promptTemplateID?.uuidString
        self.projectPath = window.projectPath
        self.status = window.status.rawValue
        self.createdAt = DateTimeService.formatUTC(window.createdAt)
        self.updatedAt = DateTimeService.formatUTC(window.updatedAt)
    }

    func toPlannedWindow() throws -> PlannedWindow {
        guard
            let uuid = UUID(uuidString: id),
            let pid = ProviderID(rawValue: providerId),
            let start = DateTimeService.parseUTC(startAt),
            let st = PlannedWindowStatus(rawValue: status)
        else {
            throw C5hError.databaseError("Invalid PlannedWindowRecord: \(id)")
        }
        return PlannedWindow(
            id: uuid,
            providerID: pid,
            startAt: start,
            durationSeconds: durationSeconds,
            promptTemplateID: promptTemplateId.flatMap { UUID(uuidString: $0) },
            projectPath: projectPath,
            status: st,
            createdAt: DateTimeService.parseUTC(createdAt) ?? start,
            updatedAt: DateTimeService.parseUTC(updatedAt) ?? .distantPast
        )
    }
}
