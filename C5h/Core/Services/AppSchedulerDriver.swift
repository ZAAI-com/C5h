import Foundation
import C5hCore
import C5hStore

struct AppSchedulerDriver: SchedulerDriver {
    let scheduledRepository: any ScheduledPromptRepository
    let actualRepository: any ActualWindowRepository
    let registry: ProviderRegistry

    func fetchDuePrompts(now: Date) async throws -> [ScheduledPrompt] {
        try await scheduledRepository.fetchDuePrompts(now: now)
    }

    func claimAsRunning(id: UUID) async throws -> Bool {
        try await scheduledRepository.tryClaimAsRunning(id: id)
    }

    func markSucceeded(id: UUID) async throws {
        try await scheduledRepository.markSucceeded(id: id)
    }

    func markFailed(id: UUID, error: String) async throws {
        try await scheduledRepository.markFailed(id: id, error: error)
    }

    func markMissed(id: UUID) async throws {
        try await scheduledRepository.markMissed(id: id)
    }

    func registerActualWindow(_ window: ActualWindow) async throws {
        try await actualRepository.create(window)
    }

    func trigger(prompt: ScheduledPrompt) async throws -> CommandRun {
        let adapter = try await MainActor.run { try registry.adapter(for: prompt.providerID) }
        return try await adapter.triggerPrompt(
            TriggerPromptInput(
                prompt: prompt.prompt,
                projectPath: prompt.projectPath,
                mode: .newSession
            )
        )
    }
}
