import Foundation

public struct PlannedWindow: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var providerID: ProviderID
    public var startAt: Date
    public var durationSeconds: Int
    public var promptTemplateID: UUID?
    public var projectPath: String?
    public var status: PlannedWindowStatus
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        providerID: ProviderID,
        startAt: Date,
        durationSeconds: Int = 5 * 60 * 60,
        promptTemplateID: UUID? = nil,
        projectPath: String? = nil,
        status: PlannedWindowStatus = .draft,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.providerID = providerID
        self.startAt = startAt
        self.durationSeconds = durationSeconds
        self.promptTemplateID = promptTemplateID
        self.projectPath = projectPath
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var endAt: Date {
        startAt.addingTimeInterval(TimeInterval(durationSeconds))
    }
}

public enum PlannedWindowStatus: String, Codable, Sendable, CaseIterable {
    case draft
    case scheduled
    case triggered
    case missed
    case cancelled
}
