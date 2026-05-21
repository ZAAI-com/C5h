import Foundation
import GRDB
import C5hCore

struct ActualWindow7dRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "actual_windows_7d"

    var id: String
    var providerId: String
    var startAt: String
    var durationSeconds: Int
    var usedPercentage: Double
    var source: String
    var confidence: String
    var usageSnapshotId: String?
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case providerId = "provider_id"
        case startAt = "start_at"
        case durationSeconds = "duration_seconds"
        case usedPercentage = "used_percentage"
        case source
        case confidence
        case usageSnapshotId = "usage_snapshot_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from window: ActualWindow7d) {
        self.id = window.id.uuidString
        self.providerId = window.providerID.rawValue
        self.startAt = DateTimeService.formatUTC(window.startAt)
        self.durationSeconds = window.durationSeconds
        self.usedPercentage = window.usedPercentage
        self.source = window.source.rawValue
        self.confidence = window.confidence.rawValue
        self.usageSnapshotId = window.usageSnapshotID?.uuidString
        self.createdAt = DateTimeService.formatUTC(window.createdAt)
        self.updatedAt = DateTimeService.formatUTC(window.updatedAt)
    }

    func toActualWindow7d() throws -> ActualWindow7d {
        guard
            let uuid = UUID(uuidString: id),
            let pid = ProviderID(rawValue: providerId),
            let start = DateTimeService.parseUTC(startAt),
            let src = ActualWindowSource(rawValue: source),
            let conf = WindowConfidence(rawValue: confidence)
        else {
            throw C5hError.databaseError("Invalid ActualWindow7dRecord: \(id)")
        }
        return ActualWindow7d(
            id: uuid,
            providerID: pid,
            startAt: start,
            durationSeconds: durationSeconds,
            usedPercentage: usedPercentage,
            source: src,
            confidence: conf,
            usageSnapshotID: usageSnapshotId.flatMap { UUID(uuidString: $0) },
            createdAt: DateTimeService.parseUTC(createdAt) ?? start,
            updatedAt: DateTimeService.parseUTC(updatedAt) ?? .distantPast
        )
    }
}
