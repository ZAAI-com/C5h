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
    var lastError: String?

    private let plannedRepository: any PlannedWindowRepository
    private let actualRepository: any ActualWindowRepository
    private let scheduledRepository: any ScheduledPromptRepository

    init(
        date: Date,
        plannedRepository: any PlannedWindowRepository,
        actualRepository: any ActualWindowRepository,
        scheduledRepository: any ScheduledPromptRepository
    ) {
        self.date = date
        self.plannedRepository = plannedRepository
        self.actualRepository = actualRepository
        self.scheduledRepository = scheduledRepository
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

    func presentEdit(for window: PlannedWindow) {
        editingExisting = window
        editingDraftPresented = true
    }

    func save(draft: PlannedWindowDraft) async throws {
        let window = draft.toPlannedWindow()
        if draft.existingID != nil {
            try await plannedRepository.update(window)
        } else {
            try await plannedRepository.create(window)
        }
        if let prompt = draft.toScheduledPrompt(plannedWindow: window) {
            try await scheduledRepository.create(prompt)
        }
        await reload()
    }

    func delete(id: UUID) async throws {
        try await plannedRepository.delete(id: id)
        await reload()
    }
}
