import Foundation
import GRDB
import C5hCore

struct UsageSnapshotRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "usage_snapshots"

    var id: String
    var providerId: String
    var capturedAt: String
    var rawJson: String
    var normalizedJson: String

    enum CodingKeys: String, CodingKey {
        case id
        case providerId = "provider_id"
        case capturedAt = "captured_at"
        case rawJson = "raw_json"
        case normalizedJson = "normalized_json"
    }

    init(from snapshot: UsageSnapshot) {
        self.id = snapshot.id.uuidString
        self.providerId = snapshot.providerID.rawValue
        self.capturedAt = DateTimeService.formatUTC(snapshot.capturedAt)
        self.rawJson = snapshot.rawJSON
        self.normalizedJson = snapshot.normalizedJSON
    }

    func toUsageSnapshot() throws -> UsageSnapshot {
        guard
            let uuid = UUID(uuidString: id),
            let pid = ProviderID(rawValue: providerId),
            let captured = DateTimeService.parseUTC(capturedAt)
        else {
            throw C5hError.databaseError("Invalid UsageSnapshotRecord: \(id)")
        }
        return UsageSnapshot(
            id: uuid,
            providerID: pid,
            capturedAt: captured,
            rawJSON: rawJson,
            normalizedJSON: normalizedJson
        )
    }
}
