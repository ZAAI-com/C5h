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
    var selection: CalendarSelection?
    var lastError: String?
    /// Advisory (non-blocking) message about the last planned/moved window,
    /// e.g. a chain-risk warning that the block may effectively be shorter
    /// than planned. Recomputed on every reload and cleared when its window
    /// leaves the visible day or is deleted.
    var lastWarning: String?
    /// The planned window `lastWarning` describes, so reloads can recompute or
    /// clear the advisory instead of letting it go stale.
    private var warningWindowID: UUID?

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

    private func loadLocalWindows() async {
        let interval = CalendarPositioning.dayInterval(for: date)
        do {
            async let planned = plannedRepository.fetchWindows(for: interval)
            async let actual = actual5hRepository.fetchWindows(for: interval)
            let fetchedPlanned = try await planned.filter { !$0.status.isTerminal }
            let fetchedActual = try await actual
            // Assign only when changed so a coarse change signal (which can fire
            // for a different day) doesn't re-render and restart block animations.
            if self.planned != fetchedPlanned { self.planned = fetchedPlanned }
            if self.actual != fetchedActual { self.actual = fetchedActual }
            self.lastError = nil
            await refreshChainRiskAdvisory()
        } catch {
            self.lastError = errorMessage(error)
        }
        await loadUsageHistories()
    }

    /// Keeps the chain-risk advisory in sync with the data it describes:
    /// recomputed from current windows on every reload, cleared once its
    /// window is no longer on the visible day.
    private func refreshChainRiskAdvisory() async {
        guard let id = warningWindowID else { return }
        guard let window = planned.first(where: { $0.id == id }) else {
            warningWindowID = nil
            lastWarning = nil
            return
        }
        lastWarning = await chainRiskWarning(for: window)
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
            // The advisory may describe the window just deleted.
            warningWindowID = nil
            lastWarning = nil
            await loadLocalWindows()
        } catch {
            lastError = errorMessage(error)
            throw error
        }
    }

    func move(window: PlannedWindow, to startAt: Date) async {
        guard window.startAt != startAt else { return }
        var moved = window
        moved.startAt = startAt
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
            lastError = nil
            warningWindowID = moved.id
            await loadLocalWindows()
        } catch {
            lastError = errorMessage(error)
            await loadLocalWindows()
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
            self.warningWindowID = window.id
            await loadLocalWindows()
        } catch {
            self.lastError = errorMessage(error)
        }
    }

    /// Best-effort chain-risk advisory for a just-planned or just-moved window:
    /// warns when its start lands inside the previous window's chained slot, so
    /// the effective block may end earlier than planned (the "planned 05:00 but
    /// the block started 03:10" trap). Returns nil when context can't be
    /// loaded: the plan itself already succeeded and must not fail here.
    private func chainRiskWarning(for window: PlannedWindow) async -> String? {
        let lookback = DateInterval(
            start: window.startAt.addingTimeInterval(-TimeInterval(window.durationSeconds)),
            end: window.startAt.addingTimeInterval(1)
        )
        guard let actual = try? await actual5hRepository.fetchWindows(for: lookback),
              let planned = try? await plannedRepository.fetchWindows(for: lookback) else {
            return nil
        }
        guard let risk = PlannedWindowValidator.chainRisk(
            candidate: window,
            against: planned,
            actualWindows: actual
        ) else {
            return nil
        }
        let gap = formatDuration(window.startAt.timeIntervalSince(risk.previousWindowEnd))
        let shortfall = formatDuration(window.endAt.timeIntervalSince(risk.projectedEffectiveEnd))
        return "Starts \(gap) after the previous 5h window ended at "
            + "\(BlockFormatters.formatTime(risk.previousWindowEnd)). If the provider chains "
            + "the block, it may effectively end at \(BlockFormatters.formatTime(risk.projectedEffectiveEnd)) "
            + "instead of \(BlockFormatters.formatTime(window.endAt)) (\(shortfall) short). "
            + "Consider starting at \(BlockFormatters.formatTime(risk.previousWindowEnd)) "
            + "or \(BlockFormatters.formatTime(risk.projectedEffectiveEnd))."
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = Int((interval / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        switch (hours, minutes) {
        case (0, _): return "\(minutes)m"
        case (_, 0): return "\(hours)h"
        default: return "\(hours)h \(minutes)m"
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

    private func errorMessage(_ error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }
}
