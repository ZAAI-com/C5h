import Foundation
import Observation
import C5hCore
import C5hStore

@Observable
@MainActor
final class DayCalendarViewModel {
    var date: Date
    var planned: [PlannedWindow] = []
    var actual: [ActualWindow5h] = []
    var usageHistories: [ProviderID: UsageHistorySeries] = [:]
    var resetEvents: [ProviderID: [UsageResetEvent]] = [:]
    /// Weekly display segments overlapping the displayed day, clipped where a
    /// later same-provider window started (see `ActualWindow7dDisplayResolver`).
    var weeklySegmentsByProvider: [ProviderID: [ActualWindow7dDisplaySegment]] = [:]
    /// Providers without a 5h limit. Their weekly block is the column's only
    /// window, so a tap on it selects it instead of quick-planning a 5h block.
    private(set) var weeklyOnlyProviders: Set<ProviderID> = []
    var selection: CalendarSelection?
    var lastError: String?
    /// Dropped starts whose save is still in flight, keyed by planned-window id.
    private var pendingMoves: [UUID: Date] = [:]
    /// Bumped per `loadLocalWindows` call so a superseded load drops its result.
    private var loadGeneration = 0
    /// Non-blocking notice from the last quick-plan (currently the chain-risk
    /// advisory). Cleared on the next plan action.
    var lastAdvisory: String?
    /// Same-provider windows from the slot immediately *before* the displayed
    /// day, held only for chain-risk validation. A window ending at 23:00 is
    /// exactly what makes a 00:30 plan risky, and the day-bounded render query
    /// cannot see it. Deliberately kept out of `planned`/`actual` so it never
    /// renders.
    private(set) var chainHistoryActual: [ActualWindow5h] = []
    private(set) var chainHistoryPlanned: [PlannedWindow] = []

    private let plannedRepository: any PlannedWindowRepository
    private let actual5hRepository: any ActualWindow5hRepository
    private let actual7dRepository: (any ActualWindow7dRepository)?
    private let scheduledRepository: any ScheduledPromptRepository
    private let usageSnapshotRepository: (any UsageSnapshotRepository)?
    private let providerRegistry: ProviderRegistry?
    private let appSettings: (any AppSettingsRepository)?
    private var usageRefreshTask: Task<Void, Never>?

    init(
        date: Date,
        plannedRepository: any PlannedWindowRepository,
        actual5hRepository: any ActualWindow5hRepository,
        actual7dRepository: (any ActualWindow7dRepository)? = nil,
        scheduledRepository: any ScheduledPromptRepository,
        usageSnapshotRepository: (any UsageSnapshotRepository)? = nil,
        providerRegistry: ProviderRegistry? = nil,
        appSettings: (any AppSettingsRepository)? = nil
    ) {
        self.date = date
        self.plannedRepository = plannedRepository
        self.actual5hRepository = actual5hRepository
        self.actual7dRepository = actual7dRepository
        self.scheduledRepository = scheduledRepository
        self.usageSnapshotRepository = usageSnapshotRepository
        self.providerRegistry = providerRegistry
        self.appSettings = appSettings
    }

    func reload() async {
        await loadLocalWindows()
        refreshUsageWindowsInBackground()
    }

    /// `preservingError` keeps the current `lastError` on a successful load, so
    /// a reload that reconciles after a failed save does not erase its message.
    private func loadLocalWindows(preservingError: Bool = false) async {
        loadGeneration += 1
        let generation = loadGeneration
        let interval = CalendarPositioning.dayInterval(for: date)
        // One provider slot before the day, for chain-risk lookback only.
        let lookback = DateInterval(
            start: interval.start.addingTimeInterval(
                -PlannedWindowValidator.defaultProviderSlotLength
            ),
            end: interval.start
        )
        do {
            async let planned = plannedRepository.fetchWindows(for: interval)
            async let actual = actual5hRepository.fetchWindows(for: interval)
            async let priorPlanned = plannedRepository.fetchWindows(for: lookback)
            async let priorActual = actual5hRepository.fetchWindows(for: lookback)
            var fetchedPlanned = try await planned.filter { !$0.status.isTerminal }
            let fetchedActual = try await actual
            let fetchedPriorPlanned = try await priorPlanned.filter { !$0.status.isTerminal }
            let fetchedPriorActual = try await priorActual
            // A newer load started while this one was fetching: its data is at
            // least as fresh, so applying this result could only briefly
            // restore a stale position (for example, a fetch from before a move
            // was saved landing after the save finished).
            guard generation == loadGeneration else { return }
            // Moves still being saved keep their dropped position, so a
            // background reload never puts the block back mid-save.
            for index in fetchedPlanned.indices {
                if let pendingStart = pendingMoves[fetchedPlanned[index].id] {
                    fetchedPlanned[index].startAt = pendingStart
                }
            }
            self.chainHistoryPlanned = fetchedPriorPlanned
            self.chainHistoryActual = fetchedPriorActual
            // Assign only when changed so a coarse change signal (which can fire
            // for a different day) doesn't re-render and restart block animations.
            if self.planned != fetchedPlanned { self.planned = fetchedPlanned }
            if self.actual != fetchedActual { self.actual = fetchedActual }
            refreshPlannedSelection()
            if !preservingError { self.lastError = nil }
        } catch {
            guard generation == loadGeneration else { return }
            self.lastError = errorMessage(error)
        }
        await loadUsageHistories()
        // The Today and Tomorrow screens render every weekly window that
        // overlaps their displayed day. Skip unrelated days and clear state
        // when this view model navigates away from either screen.
        if Self.isTodayOrTomorrow(date) {
            await loadWeeklyContext()
        } else {
            setWeeklySegments([:])
        }
    }

    /// Swaps a `.planned` selection for the current value of the same window so
    /// the inspector follows a move (and its revert on failure).
    private func refreshPlannedSelection() {
        guard case let .planned(selected)? = selection,
              let current = planned.first(where: { $0.id == selected.id }),
              current != selected else { return }
        selection = .planned(current)
    }

    private func loadWeeklyContext() async {
        guard let actual7dRepo = actual7dRepository,
              let usageRepo = usageSnapshotRepository else { return }
        let day = CalendarPositioning.dayInterval(for: date)
        // Reach back one full weekly duration so a window that started before
        // the day is still clipped by a successor that also started earlier.
        let lookback = DateInterval(
            start: day.start.addingTimeInterval(-TimeInterval(ClaudeUsageStatus.sevenDayDurationSeconds)),
            end: day.end
        )
        guard let fetched = try? await actual7dRepo.fetchWindows(for: lookback) else { return }
        var segments: [ProviderID: [ActualWindow7dDisplaySegment]] = [:]
        var weeklyOnly: Set<ProviderID> = []
        for providerID in ProviderID.allCases {
            if await usageRepo.isWeeklyOnly(providerID: providerID) { weeklyOnly.insert(providerID) }
            guard await usageRepo.showsWeeklyWindowBlocks(providerID: providerID) else { continue }
            let overlapping = ActualWindow7dDisplayResolver
                .segments(for: fetched.filter { $0.providerID == providerID })
                .filter {
                    CalendarPositioning.windowOverlaps(
                        start: $0.startAt,
                        durationSeconds: $0.durationSeconds,
                        day: date
                    )
                }
            if !overlapping.isEmpty { segments[providerID] = overlapping }
        }
        if weeklyOnlyProviders != weeklyOnly { weeklyOnlyProviders = weeklyOnly }
        setWeeklySegments(segments)
    }

    /// Single assignment funnel for `weeklySegmentsByProvider`. Assigns the
    /// dictionary only when changed (preserving the animation-restart guard),
    /// then reconciles a `.weekly` selection with the refreshed state: a window
    /// still present under the same id is swapped for its refreshed value so
    /// the inspector shows current data and tap-to-toggle equality still
    /// matches, and any selection the reload filtered out (out of the day,
    /// removed, or no longer drawn for its provider) is cleared. A window that was not
    /// already selected is never selected. `.planned` and `.actual` selections
    /// are untouched.
    private func setWeeklySegments(_ segments: [ProviderID: [ActualWindow7dDisplaySegment]]) {
        if weeklySegmentsByProvider != segments {
            weeklySegmentsByProvider = segments
        }
        guard case let .weekly(selected)? = selection else { return }
        if let refreshed = segments[selected.providerID]?.first(where: { $0.id == selected.id })?.window {
            if refreshed != selected {
                selection = .weekly(refreshed)
            }
        } else {
            selection = nil
        }
    }

    private static func isTodayOrTomorrow(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date) || Calendar.current.isDateInTomorrow(date)
    }

    private func loadUsageHistories() async {
        guard let usageRepo = usageSnapshotRepository else { return }
        let lookback = DateInterval(
            start: date.addingTimeInterval(-7 * 24 * 60 * 60),
            end: date.addingTimeInterval(24 * 60 * 60)
        )
        var built: [ProviderID: UsageHistorySeries] = [:]
        for providerID in ProviderID.allCases {
            do {
                let snapshots = try await usageRepo.fetchInRange(
                    providerID: providerID,
                    interval: lookback
                )
                built[providerID] = UsageHistorySeries(
                    providerID: providerID,
                    snapshots: snapshots
                )
            } catch {
                NSLog("DayCalendarViewModel: usage history load failed for \(providerID.rawValue): \(error)")
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

    /// The 5h reset event whose new window ends at `end` (±60s), used to mark the
    /// reset-derived window in the calendar. Matches `newResetEnd` to the
    /// window's end so only the post-reset window carries the marker.
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

    /// Best-effort: fetch fresh usage from each provider so stale
    /// `[wrong-start, +5h]` ActualWindow5h rows (from older trigger code that
    /// didn't reconcile against upstream `resetsAt`) get corrected before the
    /// calendar reads them. Failures are silent: the calendar still shows
    /// whatever's already in the repo.
    private func refreshUsageWindowsInBackground() {
        guard usageRefreshTask == nil else { return }
        usageRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshUsageWindows()
            guard !Task.isCancelled else { return }
            await self.loadLocalWindows()
            self.usageRefreshTask = nil
        }
    }

    private func refreshUsageWindows() async {
        guard let usageRepo = usageSnapshotRepository,
              let registry = providerRegistry,
              let actual7dRepo = actual7dRepository else { return }
        let actual5hRepo = actual5hRepository
        // When settings are available, honor the per-provider "check when idle"
        // gate; without them, only providers with read-only probes may fall
        // back to refreshing (an ungated Claude probe on an idle account would
        // open a fresh 5h window).
        let gate = appSettings.map {
            UsageCheckGate.make(
                appSettings: $0,
                actual5hRepository: actual5hRepo,
                plannedWindowRepository: plannedRepository,
                usageSnapshotRepository: usageRepo,
                localActivityDetector: .standard
            )
        }
        let fetcher = UsageFetcher(
            persistSnapshot: { snapshot in try await usageRepo.create(snapshot) },
            upsertActualWindow5h: { window, tolerance in
                try await actual5hRepo.upsertByEndAt(window, tolerance: tolerance)
            },
            upsertActualWindow7d: { window, tolerance in
                try await actual7dRepo.upsertByEndAt(window, tolerance: tolerance)
            }
        )
        let now = Date()
        for providerID in ProviderID.allCases {
            // Honor the per-provider refresh interval first: skip providers whose
            // cached usage is still fresh so reopening the calendar doesn't
            // re-spawn every CLI. Mirrors DashboardViewModel.refreshUsageWindowIfDue.
            let interval = await intervalSeconds(for: providerID)
            if let age = await cachedUsageAge(providerID: providerID, now: now),
               age < interval {
                continue
            }
            if let gate {
                if await gate.shouldCheck(providerID: providerID, now: now) == false {
                    continue
                }
            } else if providerID.usageProbeConsumesQuota {
                continue
            }
            do {
                let adapter = try registry.adapter(for: providerID)
                _ = try await fetcher.fetchAndPersist(adapter: adapter)
            } catch {
                if (error as? C5hError)?.isUsageRefreshAlreadyRunning == true {
                    continue
                }
                NSLog("DayCalendarViewModel: usage refresh failed for \(providerID.rawValue): \(error)")
            }
        }
    }

    /// Age of a provider's freshest cached usage snapshot, or nil when nothing has
    /// been fetched yet (treated as stale so a first fetch runs).
    private func cachedUsageAge(providerID: ProviderID, now: Date) async -> TimeInterval? {
        guard let usageRepo = usageSnapshotRepository,
              let snapshot = try? await usageRepo.fetchLatest(providerID: providerID) else {
            return nil
        }
        return now.timeIntervalSince(snapshot.capturedAt)
    }

    /// Per-provider refresh interval from settings, falling back to the default
    /// when settings are unavailable or unset.
    private func intervalSeconds(for providerID: ProviderID) async -> TimeInterval {
        guard let appSettings else {
            return TimeInterval(AppSettingsKeys.defaultUsageRefreshIntervalSeconds)
        }
        let stored = (try? await appSettings.get(
            AppSettingsKeys.usageRefreshIntervalSeconds(for: providerID),
            as: Int.self
        )) ?? nil
        return TimeInterval(stored ?? AppSettingsKeys.defaultUsageRefreshIntervalSeconds)
    }

    /// Weekly blocks for the Today and Tomorrow screens: every weekly window
    /// overlapping the displayed day, clipped at its successor's start.
    func weeklySegments(for providerID: ProviderID) -> [ActualWindow7dDisplaySegment] {
        guard Self.isTodayOrTomorrow(date) else { return [] }
        return weeklySegmentsByProvider[providerID] ?? []
    }

    /// The displayed segment behind a selected weekly window, surfaced in the
    /// inspector so it can tell when a later window superseded it.
    func weeklySegment(for selection: CalendarSelection) -> ActualWindow7dDisplaySegment? {
        guard case let .weekly(window) = selection else { return nil }
        return weeklySegmentsByProvider[window.providerID]?.first { $0.id == window.id }
    }

    func windows(for providerID: ProviderID) -> (planned: [PlannedWindow], actual: [ActualWindow5hDisplaySegment]) {
        let providerActual = actual.filter { $0.providerID == providerID }
        return (
            planned.filter { $0.providerID == providerID },
            ActualWindow5hDisplayResolver.segments(
                for: providerActual,
                resetEvents: resetEvents[providerID] ?? [],
                histories: usageHistories
            )
        )
    }

    func goToPreviousDay() {
        date = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
    }

    func goToNextDay() {
        date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
    }

    func delete(id: UUID) async throws {
        do {
            try await scheduledRepository.cancelPendingAndDetachPrompts(plannedWindowID: id)
            try await plannedRepository.delete(id: id)
            lastError = nil
            await loadLocalWindows()
        } catch {
            lastError = errorMessage(error)
            throw error
        }
    }

    /// Applies the dropped position immediately, then saves it in the
    /// background. The synchronous part runs in the same update as the drop, so
    /// the block, its time labels, and the inspector never show the old start.
    /// A window whose previous move is still being saved ignores further moves;
    /// other windows can move meanwhile.
    func move(window: PlannedWindow, to startAt: Date) {
        guard window.startAt != startAt, pendingMoves[window.id] == nil else { return }
        var moved = window
        moved.startAt = startAt
        pendingMoves[window.id] = startAt
        if let index = planned.firstIndex(where: { $0.id == window.id }) {
            planned[index].startAt = startAt
        }
        refreshPlannedSelection()
        Task { await persistMove(original: window, moved: moved) }
    }

    private func persistMove(original window: PlannedWindow, moved: PlannedWindow) async {
        do {
            let original = try await plannedRepository.fetch(id: window.id) ?? window
            try await plannedRepository.update(moved)
            do {
                try await scheduledRepository.reschedulePendingPrompts(
                    plannedWindowID: moved.id,
                    providerID: moved.providerID,
                    projectPath: moved.projectPath,
                    runAt: moved.startAt
                )
            } catch {
                do {
                    try await plannedRepository.update(original)
                    try await scheduledRepository.reschedulePendingPrompts(
                        plannedWindowID: original.id,
                        providerID: original.providerID,
                        projectPath: original.projectPath,
                        runAt: original.startAt
                    )
                } catch let rollbackError {
                    NSLog("DayCalendarViewModel: rollback after planned-window move failed: \(rollbackError)")
                }
                throw error
            }
            pendingMoves[window.id] = nil
            lastError = nil
            await loadLocalWindows()
        } catch {
            // Reconcile with whatever was actually persisted, keeping the error
            // visible through the reload.
            pendingMoves[window.id] = nil
            lastError = errorMessage(error)
            await loadLocalWindows(preservingError: true)
        }
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
        // Advisory, not a veto: the plan is created either way. The chained
        // boundary can also decay, and a short gap is sometimes intentional.
        // Lookback windows are included so a plan early in the day still sees
        // the previous evening's window.
        lastAdvisory = PlannedWindowValidator.chainRisk(
            candidate: window,
            against: planned + chainHistoryPlanned,
            actualWindows: actual + chainHistoryActual
        ).map(Self.chainRiskMessage)
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
                do {
                    try await plannedRepository.delete(id: window.id)
                } catch let deleteError {
                    NSLog("DayCalendarViewModel: rollback delete of orphan PlannedWindow \(window.id) failed: \(deleteError)")
                }
                throw error
            }
            self.lastError = nil
            await loadLocalWindows()
        } catch {
            self.lastError = errorMessage(error)
        }
    }

    /// Explains the projected shortfall and the nearest safe starts, using the
    /// suggested starts the validator already computed (back-to-back with the
    /// previous window, or at the chained slot's end for a full-length window).
    private static func chainRiskMessage(_ risk: PlannedWindowChainRisk) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let minutes = max(1, risk.shortfallSeconds / 60)
        let starts = risk.suggestedStarts
            .map { formatter.string(from: $0) }
            .joined(separator: " or ")
        let projected = formatter.string(from: risk.projectedEffectiveEnd)
        return "Planned inside the previous window's chained slot: it may end around "
            + "\(projected), \(minutes) min short. Try \(starts)."
    }

    private func defaultWakePrompt(for provider: ProviderID) async -> String {
        guard let appSettings else { return AppSettingsKeys.defaultWakePromptFallback }
        let key = AppSettingsKeys.defaultWakePrompt(for: provider)
        let stored = (try? await appSettings.get(key, as: String.self)) ?? nil
        let trimmed = stored?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty { return trimmed }
        return AppSettingsKeys.defaultWakePromptFallback
    }

    private func errorMessage(_ error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }
}
