import Foundation

public struct ActualWindow5h: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var providerID: ProviderID
    public var startAt: Date
    public var durationSeconds: Int
    public var timeZoneIdentifier: String
    public var localDate: String
    public var source: ActualWindowSource
    public var confidence: WindowConfidence
    public var commandRunID: UUID?
    public var usageStartSnapshotID: UUID?
    public var usageEndSnapshotID: UUID?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        providerID: ProviderID,
        startAt: Date,
        durationSeconds: Int = 5 * 60 * 60,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        localDate: String? = nil,
        source: ActualWindowSource,
        confidence: WindowConfidence,
        commandRunID: UUID? = nil,
        usageStartSnapshotID: UUID? = nil,
        usageEndSnapshotID: UUID? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.providerID = providerID
        self.startAt = startAt
        self.durationSeconds = durationSeconds
        let tz = TimeZone(identifier: timeZoneIdentifier) ?? .current
        self.timeZoneIdentifier = tz.identifier
        self.localDate = localDate ?? DateTimeService.localDate(for: startAt, in: tz)
        self.source = source
        self.confidence = confidence
        self.commandRunID = commandRunID
        self.usageStartSnapshotID = usageStartSnapshotID
        self.usageEndSnapshotID = usageEndSnapshotID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var endAt: Date {
        startAt.addingTimeInterval(TimeInterval(durationSeconds))
    }

    /// Current non-manual 5h windows are anchored to provider-reported reset
    /// boundaries. This remains true when a detected window is later linked to a
    /// triggered command and promoted to `c5hTriggered`.
    public var hasProviderAnchoredUsageWindow: Bool {
        source != .manual
    }
}

public enum ActualWindowSource: String, Codable, Sendable, CaseIterable {
    case c5hTriggered
    case detectedFromUsage
    case manual
}

public enum WindowConfidence: String, Codable, Sendable, CaseIterable {
    case exact
    case estimated
}
