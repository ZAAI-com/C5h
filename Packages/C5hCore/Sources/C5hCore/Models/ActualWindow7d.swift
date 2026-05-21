import Foundation

public struct ActualWindow7d: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var providerID: ProviderID
    public var startAt: Date
    public var durationSeconds: Int
    public var timeZoneIdentifier: String
    public var usedPercentage: Double
    public var source: ActualWindowSource
    public var confidence: WindowConfidence
    public var usageSnapshotID: UUID?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        providerID: ProviderID,
        startAt: Date,
        durationSeconds: Int = 7 * 24 * 60 * 60,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        usedPercentage: Double,
        source: ActualWindowSource,
        confidence: WindowConfidence,
        usageSnapshotID: UUID? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.providerID = providerID
        self.startAt = startAt
        self.durationSeconds = durationSeconds
        self.timeZoneIdentifier = timeZoneIdentifier
        self.usedPercentage = usedPercentage
        self.source = source
        self.confidence = confidence
        self.usageSnapshotID = usageSnapshotID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var endAt: Date {
        startAt.addingTimeInterval(TimeInterval(durationSeconds))
    }
}
