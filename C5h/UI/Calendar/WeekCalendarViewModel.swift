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
    private let usageSnapshotRepo: (any UsageSnapshotRepository)?

    init(
        weekStart: Date,
        plannedRepository: any PlannedWindowRepository,
        actual5hRepository: any ActualWindow5hRepository,
        usageSnapshotRepository: (any UsageSnapshotRepository)? = nil
    ) {
        self.weekStart = Self.startOfWeek(for: weekStart)
        self.plannedRepo = plannedRepository
        self.actual5hRepo = actual5hRepository
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
            let fetchedPlanned = try await p.filter { !$0.status.isTerminal }
            let fetchedActual = try await a
            // Assign only when changed so a coarse change signal (which can fire
            // for a different week) doesn't re-render and restart block animations.
            if self.planned != fetchedPlanned { self.planned = fetchedPlanned }
            if self.actual != fetchedActual { self.actual = fetchedActual }
            self.lastError = nil
            pruneSelectionIfNeeded()
        } catch {
            self.lastError = String(describing: error)
        }
        await loadUsageHistories()
    }

    private func pruneSelectionIfNeeded() {
        guard let selection else { return }
        if !selectionOverlapsCurrentWeek(selection) {
            self.selection = nil
            return
        }
        switch selection {
        case .planned(let window):
            if !planned.contains(where: { $0.id == window.id }) {
                self.selection = nil
            }
        case .actual(let window):
            if !actual.contains(where: { $0.id == window.id }) {
                self.selection = nil
            }
        case .weekly:
            self.selection = nil
        }
    }

    private func selectionOverlapsCurrentWeek(_ selection: CalendarSelection) -> Bool {
        let weekEnd = Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        switch selection {
        case .planned(let window):
            return window.startAt < weekEnd && window.endAt > weekStart
        case .actual(let window):
            return window.startAt < weekEnd && window.endAt > weekStart
        case .weekly:
            return false
        }
    }

    func firstVisibleActual(
        visibleProviders: Set<ProviderID>,
        showActual: Bool
    ) -> ActualWindow5h? {
        guard showActual else { return nil }
        for day in days {
            for segment in actualDisplaySegments {
                guard visibleProviders.contains(segment.window.providerID) else { continue }
                guard CalendarPositioning.windowOverlaps(
                    start: segment.startAt,
                    durationSeconds: segment.durationSeconds,
                    day: day
                ) else { continue }
                return segment.window
            }
        }
        return nil
    }

    func firstVisiblePlanned(
        visibleProviders: Set<ProviderID>,
        showPlanned: Bool
    ) -> PlannedWindow? {
        guard showPlanned else { return nil }
        for day in days {
            for window in planned {
                guard visibleProviders.contains(window.providerID) else { continue }
                guard CalendarPositioning.windowOverlaps(
                    start: window.startAt,
                    durationSeconds: window.durationSeconds,
                    day: day
                ) else { continue }
                return window
            }
        }
        return nil
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
        // Assign only when changed so change signals from unrelated tables don't
        // force chart re-renders.
        if self.usageHistories != built { self.usageHistories = built }
        let detected = built.mapValues { UsageResetDetector.detect(in: $0) }
        if self.resetEvents != detected { self.resetEvents = detected }
    }

    func history(for providerID: ProviderID) -> UsageHistorySeries? {
        usageHistories[providerID]
    }

    var actualDisplaySegments: [ActualWindow5hDisplaySegment] {
        ActualWindow5hDisplayResolver.segments(
            for: actual,
            resetEvents: resetEvents.values.flatMap { $0 },
            histories: usageHistories
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
        selection = nil
    }

    func goToNextWeek() {
        weekStart = Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        selection = nil
    }

    func delete(id: UUID) async throws {
        do {
            try await plannedRepo.deleteWithPendingPromptCleanup(id: id)
            lastError = nil
            await reload()
        } catch {
            lastError = String(describing: error)
            throw error
        }
    }
}
