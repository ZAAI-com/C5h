import Foundation
import GRDB
import C5hCore

struct ActualWindowRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "actual_windows"

    var id: String
    var providerId: String
    var startAt: String
    var durationSeconds: Int
    var source: String
    var confidence: String
    var commandRunId: String?
    var usageStartSnapshotId: String?
    var usageEndSnapshotId: String?
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case providerId = "provider_id"
        case startAt = "start_at"
        case durationSeconds = "duration_seconds"
        case source
        case confidence
        case commandRunId = "command_run_id"
        case usageStartSnapshotId = "usage_start_snapshot_id"
        case usageEndSnapshotId = "usage_end_snapshot_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from window: ActualWindow) {
        self.id = window.id.uuidString
        self.providerId = window.providerID.rawValue
        self.startAt = DateTimeService.formatUTC(window.startAt)
        self.durationSeconds = window.durationSeconds
        self.source = window.source.rawValue
        self.confidence = window.confidence.rawValue
        self.commandRunId = window.commandRunID?.uuidString
        self.usageStartSnapshotId = window.usageStartSnapshotID?.uuidString
        self.usageEndSnapshotId = window.usageEndSnapshotID?.uuidString
        self.createdAt = DateTimeService.formatUTC(window.createdAt)
        self.updatedAt = DateTimeService.formatUTC(window.updatedAt)
    }

    func toActualWindow() throws -> ActualWindow {
        guard
            let uuid = UUID(uuidString: id),
            let pid = ProviderID(rawValue: providerId),
            let start = DateTimeService.parseUTC(startAt),
            let src = ActualWindowSource(rawValue: source),
            let conf = WindowConfidence(rawValue: confidence)
        else {
            throw C5hError.databaseError("Invalid ActualWindowRecord: \(id)")
        }
        return ActualWindow(
            id: uuid,
            providerID: pid,
            startAt: start,
            durationSeconds: durationSeconds,
            source: src,
            confidence: conf,
            commandRunID: commandRunId.flatMap { UUID(uuidString: $0) },
            usageStartSnapshotID: usageStartSnapshotId.flatMap { UUID(uuidString: $0) },
            usageEndSnapshotID: usageEndSnapshotId.flatMap { UUID(uuidString: $0) },
            createdAt: DateTimeService.parseUTC(createdAt) ?? start,
            updatedAt: DateTimeService.parseUTC(updatedAt) ?? .distantPast
        )
    }
}
