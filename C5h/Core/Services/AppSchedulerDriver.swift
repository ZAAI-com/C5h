import Foundation
import C5hCore
import C5hStore

struct AppSchedulerDriver: SchedulerDriver {
    let scheduledRepository: any ScheduledPromptRepository
    let actual5hRepository: any ActualWindow5hRepository
    let actual7dRepository: any ActualWindow7dRepository
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
    ) async throws -> ActualWindow5h? {
        let actual5hRepo = actual5hRepository
        let actual7dRepo = actual7dRepository
        let usageRepo = usageSnapshotRepository
        let registry = registry
        let fetcher = UsageFetcher(
            persistSnapshot: { snapshot in
                try await usageRepo.create(snapshot)
            },
            upsertActualWindow5h: { window, tolerance in
                try await actual5hRepo.upsertByEndAt(window, tolerance: tolerance)
            },
            upsertActualWindow7d: { window, tolerance in
                try await actual7dRepo.upsertByEndAt(window, tolerance: tolerance)
            }
        )
        let resolver = ActiveWindowResolver(
            fetcher: fetcher,
            snapshotFetch: { providerID in
                let adapter = try await MainActor.run { try registry.adapter(for: providerID) }
                return try await adapter.runUsageCommand()
            },
            activeWindowFetch: { providerID, now in
                // Search around `now` rather than a 1-second slice so we don't
                // miss the active window when boundaries land outside the slot.
                let lookback: TimeInterval = 24 * 60 * 60
                let interval = DateInterval(
                    start: now.addingTimeInterval(-lookback),
                    end: now.addingTimeInterval(lookback)
                )
                let windows = try await actual5hRepo.fetchWindows(for: interval)
                return windows
                    .filter { $0.providerID == providerID }
                    .first { window in
                        let end = window.startAt.addingTimeInterval(TimeInterval(window.durationSeconds))
                        return window.startAt <= now && now < end
                    }
            },
            updateActualWindow: { window in
                try await actual5hRepo.update(window)
            }
        )
        return await resolver.resolveTriggeredWindow(
            providerID: providerID,
            commandRunID: commandRun.id,
            now: commandRun.startedAt
        )
    }
}
