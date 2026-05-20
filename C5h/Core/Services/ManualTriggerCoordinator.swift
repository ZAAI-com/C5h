import Foundation
import C5hCore
import C5hStore

@MainActor
final class ManualTriggerCoordinator {
    let registry: ProviderRegistry
    let actualWindowRepository: any ActualWindowRepository

    init(
        registry: ProviderRegistry,
        actualWindowRepository: any ActualWindowRepository
    ) {
        self.registry = registry
        self.actualWindowRepository = actualWindowRepository
    }

    /// Triggers a prompt for the given provider, immediately persists an
    /// ActualWindow that is linked to the not-yet-completed CommandRun, and
    /// fires the runner in a detached Task so the UI can update within 1s.
    func startNow(
        providerID: ProviderID,
        prompt: String,
        projectPath: String?
    ) async throws -> ActualWindow {
        let adapter = try registry.adapter(for: providerID)
        let runID = UUID()
        let actual = ActualWindow(
            providerID: providerID,
            startAt: .now,
            durationSeconds: 5 * 3600,
            source: .c5hTriggered,
            confidence: .exact,
            commandRunID: runID
        )
        try await actualWindowRepository.create(actual)

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
        return actual
    }
}
