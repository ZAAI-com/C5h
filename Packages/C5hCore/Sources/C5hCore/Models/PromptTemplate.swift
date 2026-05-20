import Foundation

public struct PromptTemplate: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var name: String
    public var providerID: ProviderID?
    public var body: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        providerID: ProviderID? = nil,
        body: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.providerID = providerID
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
