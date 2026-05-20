import Foundation
import GRDB

struct HelperHeartbeatRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "helper_heartbeats"

    var id: String
    var helperVersion: String
    var startedAt: String
    var lastSeenAt: String
    var pid: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case helperVersion = "helper_version"
        case startedAt = "started_at"
        case lastSeenAt = "last_seen_at"
        case pid
    }
}
