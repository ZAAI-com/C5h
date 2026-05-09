import Foundation
import GRDB
import C5hCore

struct ProviderRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "providers"

    var id: String
    var displayName: String
    var cliPath: String?
    var enabled: Int
    var brandColor: String
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case cliPath = "cli_path"
        case enabled
        case brandColor = "brand_color"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from provider: Provider) {
        self.id = provider.id.rawValue
        self.displayName = provider.displayName
        self.cliPath = provider.cliPath
        self.enabled = provider.isEnabled ? 1 : 0
        self.brandColor = provider.brandColorHex
        self.createdAt = DateTimeService.formatUTC(provider.createdAt)
        self.updatedAt = DateTimeService.formatUTC(provider.updatedAt)
    }

    func toProvider() throws -> Provider {
        guard let pid = ProviderID(rawValue: id) else {
            throw C5hError.databaseError("Unknown provider id in DB: \(id)")
        }
        return Provider(
            id: pid,
            displayName: displayName,
            cliPath: cliPath,
            isEnabled: enabled != 0,
            brandColorHex: brandColor,
            createdAt: DateTimeService.parseUTC(createdAt) ?? .now,
            updatedAt: DateTimeService.parseUTC(updatedAt) ?? .now
        )
    }
}
