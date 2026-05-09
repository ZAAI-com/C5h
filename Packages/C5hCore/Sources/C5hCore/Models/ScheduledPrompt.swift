import Foundation

public struct ScheduledPrompt: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var providerID: ProviderID
    public var plannedWindowID: UUID?
    public var prompt: String
    public var projectPath: String?
    public var runAt: Date
    public var status: ScheduledPromptStatus
    public var attempts: Int
    public var lastError: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        providerID: ProviderID,
        plannedWindowID: UUID? = nil,
        prompt: String,
        projectPath: String? = nil,
        runAt: Date,
        status: ScheduledPromptStatus = .scheduled,
        attempts: Int = 0,
        lastError: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.providerID = providerID
        self.plannedWindowID = plannedWindowID
        self.prompt = prompt
        self.projectPath = projectPath
        self.runAt = runAt
        self.status = status
        self.attempts = attempts
        self.lastError = lastError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum ScheduledPromptStatus: String, Codable, Sendable, CaseIterable {
    case scheduled
    case due
    case running
    case succeeded
    case failed
    case missed
    case cancelled
}
