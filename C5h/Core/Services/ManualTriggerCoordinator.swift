import Foundation
import C5hCore
import C5hStore

@MainActor
final class ManualTriggerCoordinator {
    let registry: ProviderRegistry
    let actualWindowRepository: any ActualWindowRepository
    let usageSnapshotRepository: any UsageSnapshotRepository

    init(
        registry: ProviderRegistry,
        actualWindowRepository: any ActualWindowRepository,
        usageSnapshotRepository: any UsageSnapshotRepository
    ) {
        self.registry = registry
        self.actualWindowRepository = actualWindowRepository
        self.usageSnapshotRepository = usageSnapshotRepository
    }

    /// Triggers a prompt for the given provider, resolves the provider's true
    /// rolling 5h window via upstream usage data, persists it as
    /// `c5hTriggered`/`exact` linked to the run, and fires the runner in a
    /// detached Task so the UI can update within 1s.
    ///
    /// Returns `nil` (and writes no `ActualWindow`) when usage resolution fails
    /// — better to show nothing than a fictitious `[now, +5h]` block.
    @discardableResult
    func startNow(
        providerID: ProviderID,
        prompt: String,
        projectPath: String?
    ) async throws -> ActualWindow? {
        let adapter = try registry.adapter(for: providerID)
        let runID = UUID()
        let resolver = makeResolver()
        let resolved = await resolver.resolveTriggeredWindow(
            providerID: providerID,
            commandRunID: runID
        )

        Task.detached(priority: .background) {
            do {
                _ = try await adapter.runPromptCommand(
                    TriggerPromptInput(prompt: prompt, projectPath: projectPath, mode: .newSession),
                    runID: runID
                )
            } catch {
                NSLog("Manual trigger run failed: \(error)")
            }
        }
        return resolved
    }

    private func makeResolver() -> ActiveWindowResolver {
        let actualRepo = actualWindowRepository
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
        return ActiveWindowResolver(
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
    }
}
