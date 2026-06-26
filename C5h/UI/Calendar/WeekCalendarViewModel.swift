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
    var usageHistories: [ProviderID: UsageHistorySeries] = [:]
    var resetEvents: [ProviderID: [UsageResetEvent]] = [:]
    var selection: CalendarSelection?
    var lastError: String?

    private let plannedRepo: any PlannedWindowRepository
    private let actual5hRepo: any ActualWindow5hRepository
    private let scheduledRepo: any ScheduledPromptRepository
    private let usageSnapshotRepo: (any UsageSnapshotRepository)?

    init(
        weekStart: Date,
        plannedRepository: any PlannedWindowRepository,
        actual5hRepository: any ActualWindow5hRepository,
        scheduledRepository: any ScheduledPromptRepository,
        usageSnapshotRepository: (any UsageSnapshotRepository)? = nil
    ) {
        self.weekStart = Self.startOfWeek(for: weekStart)
        self.plannedRepo = plannedRepository
        self.actual5hRepo = actual5hRepository
        self.scheduledRepo = scheduledRepository
        self.usageSnapshotRepo = usageSnapshotRepository
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
        await loadUsageHistories()
    }

    private func loadUsageHistories() async {
        guard let repo = usageSnapshotRepo else { return }
        let weekEnd = Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let lookback = DateInterval(
            start: weekStart.addingTimeInterval(-7 * 24 * 60 * 60),
            end: weekEnd.addingTimeInterval(7 * 24 * 60 * 60)
        )
        var built: [ProviderID: UsageHistorySeries] = [:]
        for providerID in ProviderID.allCases {
            do {
                let snapshots = try await repo.fetchInRange(
                    providerID: providerID,
                    interval: lookback
                )
                built[providerID] = UsageHistorySeries(
                    providerID: providerID,
                    snapshots: snapshots
                )
            } catch {
                NSLog("WeekCalendarViewModel: usage history load failed for \(providerID.rawValue): \(error)")
            }
        }
        self.usageHistories = built
        self.resetEvents = built.mapValues { UsageResetDetector.detect(in: $0) }
    }

    func history(for providerID: ProviderID) -> UsageHistorySeries? {
        usageHistories[providerID]
    }

    var actualDisplaySegments: [ActualWindow5hDisplaySegment] {
        ActualWindow5hDisplayResolver.segments(
            for: actual,
            resetEvents: resetEvents.values.flatMap { $0 }
        )
    }

    /// The 5h reset event whose new window ends at `end` (±60s), used to mark the
    /// reset-derived window in the calendar.
    func fiveHourResetEvent(forWindowEndingAt end: Date, providerID: ProviderID) -> UsageResetEvent? {
        (resetEvents[providerID] ?? []).first { event in
            event.kind == .fiveHour && abs(event.newResetEnd.timeIntervalSince(end)) <= 60
        }
    }

    /// The reset event behind a selected actual window, surfaced in the inspector.
    func resetEvent(for selection: CalendarSelection) -> UsageResetEvent? {
        guard case let .actual(window) = selection else { return nil }
        return fiveHourResetEvent(forWindowEndingAt: window.endAt, providerID: window.providerID)
    }

    func goToPreviousWeek() {
        weekStart = Calendar.current.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
    }

    func goToNextWeek() {
        weekStart = Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
    }

    func delete(id: UUID) async throws {
        do {
            try await scheduledRepo.cancelPendingAndDetachPrompts(plannedWindowID: id)
            try await plannedRepo.delete(id: id)
            lastError = nil
            await reload()
        } catch {
            lastError = String(describing: error)
            throw error
        }
    }
}
