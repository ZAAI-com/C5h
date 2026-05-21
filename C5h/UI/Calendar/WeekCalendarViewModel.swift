import Foundation
import Observation
import C5hCore
import C5hStore

@Observable
@MainActor
final class WeekCalendarViewModel {
    var weekStart: Date
    var planned: [PlannedWindow] = []
    var actual: [ActualWindow5h] = []
    var lastError: String?

    private let plannedRepo: any PlannedWindowRepository
    private let actual5hRepo: any ActualWindow5hRepository

    init(
        weekStart: Date,
        plannedRepository: any PlannedWindowRepository,
        actual5hRepository: any ActualWindow5hRepository
    ) {
        self.weekStart = Self.startOfWeek(for: weekStart)
        self.plannedRepo = plannedRepository
        self.actual5hRepo = actual5hRepository
    }

    static func startOfWeek(for date: Date) -> Date {
        let cal = Calendar(identifier: .iso8601)
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: comps) ?? cal.startOfDay(for: date)
    }

    var days: [Date] {
        (0..<7).compactMap {
            Calendar.current.date(byAdding: .day, value: $0, to: weekStart)
        }
    }

    func reload() async {
        let interval = DateInterval(
            start: weekStart,
            end: Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        )
        do {
            async let p = plannedRepo.fetchWindows(for: interval)
            async let a = actual5hRepo.fetchWindows(for: interval)
            self.planned = try await p
            self.actual = try await a
            self.lastError = nil
        } catch {
            self.lastError = String(describing: error)
        }
    }

    func windows(forDay day: Date, providerID: ProviderID) -> (planned: [PlannedWindow], actual: [ActualWindow5h]) {
        let dayInterval = CalendarPositioning.dayInterval(for: day)
        let p = planned.filter {
            $0.providerID == providerID && dayInterval.contains($0.startAt)
        }
        let a = actual.filter {
            $0.providerID == providerID && dayInterval.contains($0.startAt)
        }
        return (p, a)
    }

    func goToPreviousWeek() {
        weekStart = Calendar.current.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
    }

    func goToNextWeek() {
        weekStart = Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
    }
}
