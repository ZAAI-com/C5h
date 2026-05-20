import Foundation

public struct Provider: Identifiable, Codable, Sendable, Hashable {
    public var id: ProviderID
    public var displayName: String
    public var cliPath: String?
    public var isEnabled: Bool
    public var brandColorHex: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: ProviderID,
        displayName: String,
        cliPath: String? = nil,
        isEnabled: Bool = true,
        brandColorHex: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.displayName = displayName
        self.cliPath = cliPath
        self.isEnabled = isEnabled
        self.brandColorHex = brandColorHex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
