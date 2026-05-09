import Foundation

public struct PlannedWindowDraft: Sendable {
    public var existingID: UUID?
    public var providerID: ProviderID
    public var startAt: Date
    public var durationSeconds: Int
    public var projectPath: String?
    public var promptTemplateID: UUID?
    public var status: PlannedWindowStatus
    public var schedulePrompt: Bool
    public var promptBody: String

    public init(
        existingID: UUID? = nil,
        providerID: ProviderID,
        startAt: Date,
        durationSeconds: Int = 5 * 3600,
        projectPath: String? = nil,
        promptTemplateID: UUID? = nil,
        status: PlannedWindowStatus = .scheduled,
        schedulePrompt: Bool = false,
        promptBody: String = ""
    ) {
        self.existingID = existingID
        self.providerID = providerID
        self.startAt = startAt
        self.durationSeconds = durationSeconds
        self.projectPath = projectPath
        self.promptTemplateID = promptTemplateID
        self.status = status
        self.schedulePrompt = schedulePrompt
        self.promptBody = promptBody
    }

    public func toPlannedWindow() -> PlannedWindow {
        PlannedWindow(
            id: existingID ?? UUID(),
            providerID: providerID,
            startAt: startAt,
            durationSeconds: durationSeconds,
            promptTemplateID: promptTemplateID,
            projectPath: projectPath,
            status: status,
            createdAt: .now,
            updatedAt: .now
        )
    }

    public func toScheduledPrompt(plannedWindow: PlannedWindow) -> ScheduledPrompt? {
        guard schedulePrompt, !promptBody.isEmpty else { return nil }
        return ScheduledPrompt(
            providerID: providerID,
            plannedWindowID: plannedWindow.id,
            prompt: promptBody,
            projectPath: projectPath,
            runAt: startAt,
            status: .scheduled
        )
    }
}
