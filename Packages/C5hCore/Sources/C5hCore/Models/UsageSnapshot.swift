import Foundation

public struct UsageSnapshot: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var providerID: ProviderID
    public var capturedAt: Date
    public var rawJSON: String
    public var normalizedJSON: String

    public init(
        id: UUID = UUID(),
        providerID: ProviderID,
        capturedAt: Date = .now,
        rawJSON: String,
        normalizedJSON: String
    ) {
        self.id = id
        self.providerID = providerID
        self.capturedAt = capturedAt
        self.rawJSON = rawJSON
        self.normalizedJSON = normalizedJSON
    }
}
