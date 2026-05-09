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
    var lastError: String?

    private let plannedRepository: any PlannedWindowRepository
    private let actualRepository: any ActualWindowRepository

    init(
        date: Date,
        plannedRepository: any PlannedWindowRepository,
        actualRepository: any ActualWindowRepository
    ) {
        self.date = date
        self.plannedRepository = plannedRepository
        self.actualRepository = actualRepository
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
}
