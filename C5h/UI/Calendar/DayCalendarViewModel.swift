import Foundation
import Observation
import C5hCore
import C5hStore

@Observable
@MainActor
final class DayCalendarViewModel {
    var date: Date
    var planned: [PlannedWindow] = []
    var actual: [ActualWindow] = []
    var selection: CalendarSelection?
    var editingExisting: PlannedWindow?
    var lastError: String?

    private let plannedRepository: any PlannedWindowRepository
    private let actualRepository: any ActualWindowRepository
    private let scheduledRepository: any ScheduledPromptRepository
    private let usageSnapshotRepository: (any UsageSnapshotRepository)?
    private let providerRegistry: ProviderRegistry?
    private let appSettings: (any AppSettingsRepository)?

    init(
        date: Date,
        plannedRepository: any PlannedWindowRepository,
        actualRepository: any ActualWindowRepository,
        scheduledRepository: any ScheduledPromptRepository,
        usageSnapshotRepository: (any UsageSnapshotRepository)? = nil,
        providerRegistry: ProviderRegistry? = nil,
        appSettings: (any AppSettingsRepository)? = nil
    ) {
        self.date = date
        self.plannedRepository = plannedRepository
        self.actualRepository = actualRepository
        self.scheduledRepository = scheduledRepository
        self.usageSnapshotRepository = usageSnapshotRepository
        self.providerRegistry = providerRegistry
        self.appSettings = appSettings
    }

    func reload() async {
        await refreshUsageWindows()
        let interval = CalendarPositioning.dayInterval(for: date)
        do {
            async let planned = plannedRepository.fetchWindows(for: interval)
            async let actual = actualRepository.fetchWindows(for: interval)
            self.planned = try await planned
            self.actual = try await actual
            self.lastError = nil
        } catch {
            self.lastError = String(describing: error)
        }
    }

    /// Best-effort: fetch fresh usage from each provider so stale
    /// `[wrong-start, +5h]` ActualWindow rows (from older trigger code that
    /// didn't reconcile against upstream `resetsAt`) get corrected before the
    /// calendar reads them. Failures are silent — the calendar still shows
    /// whatever's already in the repo.
    private func refreshUsageWindows() async {
        guard let usageRepo = usageSnapshotRepository,
              let registry = providerRegistry else { return }
        let actualRepo = actualRepository
        let fetcher = UsageFetcher(
            persistSnapshot: { snapshot in try await usageRepo.create(snapshot) },
            upsertActualWindow: { window, tolerance in
                try await actualRepo.upsertByEndAt(window, tolerance: tolerance)
            }
        )
        for providerID in ProviderID.allCases {
            do {
                let adapter = try registry.adapter(for: providerID)
                _ = try await fetcher.fetchAndPersist(adapter: adapter)
            } catch {
                NSLog("DayCalendarViewModel: usage refresh failed for \(providerID.rawValue): \(error)")
            }
        }
    }

    func windows(for providerID: ProviderID) -> (planned: [PlannedWindow], actual: [ActualWindow]) {
        (planned.filter { $0.providerID == providerID },
         actual.filter { $0.providerID == providerID })
    }

    func goToPreviousDay() {
        date = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
    }

    func goToNextDay() {
        date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
    }

    func presentEdit(for window: PlannedWindow) {
        editingExisting = window
    }

    func save(draft: PlannedWindowDraft) async throws {
        let window = draft.toPlannedWindow()
        let original: PlannedWindow?
        if let id = draft.existingID {
            original = try await plannedRepository.fetch(id: id)
            try await plannedRepository.update(window)
        } else {
            original = nil
            try await plannedRepository.create(window)
        }
        if let prompt = draft.toScheduledPrompt(plannedWindow: window) {
            do {
                try await scheduledRepository.create(prompt)
            } catch {
                do {
                    if draft.existingID == nil {
                        try await plannedRepository.delete(id: window.id)
                    } else if let original {
                        try await plannedRepository.update(original)
                    }
                } catch let rollbackError {
                    NSLog("DayCalendarViewModel: rollback after scheduled-prompt create failed: \(rollbackError)")
                }
                throw error
            }
        }
        await reload()
    }

    func delete(id: UUID) async throws {
        try await plannedRepository.delete(id: id)
        await reload()
    }

    /// One-click hover-to-plan: creates a fixed 5h `PlannedWindow` for `provider`
    /// starting at `startAt`, with an attached `ScheduledPrompt` carrying the
    /// per-provider default wake prompt (so the window actually opens on time).
    func quickPlan(provider: ProviderID, startAt: Date) async {
        let duration = ClaudeUsageStatus.fiveHourDurationSeconds
        let window = PlannedWindow(
            providerID: provider,
            startAt: startAt,
            durationSeconds: duration,
            status: .scheduled
        )
        do {
            try await plannedRepository.create(window)
            let wakePrompt = await defaultWakePrompt(for: provider)
            let prompt = ScheduledPrompt(
                providerID: provider,
                plannedWindowID: window.id,
                prompt: wakePrompt,
                runAt: startAt
            )
            do {
                try await scheduledRepository.create(prompt)
            } catch {
                try? await plannedRepository.delete(id: window.id)
                throw error
            }
            self.lastError = nil
            await reload()
        } catch {
            self.lastError = String(describing: error)
        }
    }

    private func defaultWakePrompt(for provider: ProviderID) async -> String {
        guard let appSettings else { return AppSettingsKeys.defaultWakePromptFallback }
        let key = AppSettingsKeys.defaultWakePrompt(for: provider)
        let stored = (try? await appSettings.get(key, as: String.self)) ?? nil
        let trimmed = stored?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty { return trimmed }
        return AppSettingsKeys.defaultWakePromptFallback
    }
}
