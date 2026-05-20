import Foundation
import GRDB
import C5hCore

struct PromptTemplateRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "prompt_templates"

    var id: String
    var name: String
    var providerId: String?
    var body: String
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case providerId = "provider_id"
        case body
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from template: PromptTemplate) {
        self.id = template.id.uuidString
        self.name = template.name
        self.providerId = template.providerID?.rawValue
        self.body = template.body
        self.createdAt = DateTimeService.formatUTC(template.createdAt)
        self.updatedAt = DateTimeService.formatUTC(template.updatedAt)
    }

    func toPromptTemplate() throws -> PromptTemplate {
        guard let uuid = UUID(uuidString: id) else {
            throw C5hError.databaseError("Invalid PromptTemplateRecord: \(id)")
        }
        return PromptTemplate(
            id: uuid,
            name: name,
            providerID: providerId.flatMap(ProviderID.init),
            body: body,
            createdAt: DateTimeService.parseUTC(createdAt) ?? .distantPast,
            updatedAt: DateTimeService.parseUTC(updatedAt) ?? .distantPast
        )
    }
}
