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
    var editingDraftPresented: Bool = false
    var editingExisting: PlannedWindow?
    var startNowPresented: Bool = false
    var startNowDefaultProvider: ProviderID = .claude
    var lastError: String?

    private let plannedRepository: any PlannedWindowRepository
    private let actualRepository: any ActualWindowRepository
    private let scheduledRepository: any ScheduledPromptRepository
    private let appSettings: (any AppSettingsRepository)?

    init(
        date: Date,
        plannedRepository: any PlannedWindowRepository,
        actualRepository: any ActualWindowRepository,
        scheduledRepository: any ScheduledPromptRepository,
        appSettings: (any AppSettingsRepository)? = nil
    ) {
        self.date = date
        self.plannedRepository = plannedRepository
        self.actualRepository = actualRepository
        self.scheduledRepository = scheduledRepository
        self.appSettings = appSettings
    }

    func reload() async {
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

    func presentNewDraft() {
        editingExisting = nil
        editingDraftPresented = true
    }

    func presentStartNow(provider: ProviderID) {
        startNowDefaultProvider = provider
        startNowPresented = true
    }

    func presentEdit(for window: PlannedWindow) {
        editingExisting = window
        editingDraftPresented = true
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
