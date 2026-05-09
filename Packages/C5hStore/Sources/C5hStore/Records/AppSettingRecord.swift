import Foundation
import GRDB

struct AppSettingRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "app_settings"

    var key: String
    var valueJson: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case key
        case valueJson = "value_json"
        case updatedAt = "updated_at"
    }
}
