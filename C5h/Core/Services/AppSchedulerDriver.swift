import Foundation
import C5hCore
import C5hStore

struct AppSchedulerDriver: SchedulerDriver {
    let scheduledRepository: any ScheduledPromptRepository
    let actualRepository: any ActualWindowRepository
    let usageSnapshotRepository: any UsageSnapshotRepository
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

    func trigger(prompt: ScheduledPrompt) async throws -> CommandRun {
        let adapter = try await MainActor.run { try registry.adapter(for: prompt.providerID) }
        return try await adapter.runPromptCommand(
            TriggerPromptInput(
                prompt: prompt.prompt,
                projectPath: prompt.projectPath,
                mode: .newSession
            )
        )
    }

    func resolveActualWindow(
        for providerID: ProviderID,
        commandRun: CommandRun
    ) async throws -> ActualWindow? {
        let actualRepo = actualRepository
        let usageRepo = usageSnapshotRepository
        let registry = registry
        let fetcher = UsageFetcher(
            persistSnapshot: { snapshot in
                try await usageRepo.create(snapshot)
            },
            upsertActualWindow: { window, tolerance in
                try await actualRepo.upsertByEndAt(window, tolerance: tolerance)
            }
        )
        let resolver = ActiveWindowResolver(
            fetcher: fetcher,
            snapshotFetch: { providerID in
                let adapter = try await MainActor.run { try registry.adapter(for: providerID) }
                return try await adapter.runUsageCommand()
            },
            activeWindowFetch: { providerID, now in
                let interval = DateInterval(start: now, duration: 1)
                let windows = try await actualRepo.fetchWindows(for: interval)
                return windows.first { $0.providerID == providerID }
            },
            updateActualWindow: { window in
                try await actualRepo.update(window)
            }
        )
        return await resolver.resolveTriggeredWindow(
            providerID: providerID,
            commandRunID: commandRun.id
        )
    }
}
