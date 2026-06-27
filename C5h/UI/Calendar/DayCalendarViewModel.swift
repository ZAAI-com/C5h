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
            self.planned = try await planned
            self.actual = try await actual
            self.lastError = nil
        } catch {
            self.lastError = errorMessage(error)
        }
        await loadUsageHistories()
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
        self.usageHistories = built
        self.resetEvents = built.mapValues { UsageResetDetector.detect(in: $0) }
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
    /// calendar reads them. Failures are silent — the calendar still shows
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
        let fetcher = UsageFetcher(
            persistSnapshot: { snapshot in try await usageRepo.create(snapshot) },
            upsertActualWindow5h: { window, tolerance in
                try await actual5hRepo.upsertByEndAt(window, tolerance: tolerance)
            },
            upsertActualWindow7d: { window, tolerance in
                try await actual7dRepo.upsertByEndAt(window, tolerance: tolerance)
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
            await loadLocalWindows()
        } catch {
            self.lastError = errorMessage(error)
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
