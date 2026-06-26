import Foundation
import Observation
import C5hCore
import C5hStore

@Observable
@MainActor
final class DashboardViewModel {
    var activeWindows: [ActualWindow5h] = []
    var weeklyWindows: [ActualWindow7d] = []
    var sevenDayResets: [ProviderID: UsageResetEvent] = [:]
    var activeWindowUsagePercentages: [UUID: Double] = [:]
    var upcomingPrompts: [ScheduledPrompt] = []
    var recentRuns: [CommandRun] = []
    var dailyUsageHistory: [DailyProviderUsage] = []
    var sparklineCounts: [ProviderID: [Int]] = [:]
    var lastError: String?
    var isLoading: Bool = false
    var isRefreshingUsage: Bool = false

    private let actual5hRepo: any ActualWindow5hRepository
    private let actual7dRepo: any ActualWindow7dRepository
    private let scheduledRepo: any ScheduledPromptRepository
    private let commandRepo: any CommandRunRepository
    private let usageRepo: any UsageSnapshotRepository
    private let appSettings: any AppSettingsRepository
    private let registry: ProviderRegistry
    private let fetcher: UsageFetcher

    init(
        actual5hRepository: any ActualWindow5hRepository,
        actual7dRepository: any ActualWindow7dRepository,
        scheduledRepository: any ScheduledPromptRepository,
        commandRunRepository: any CommandRunRepository,
        usageSnapshotRepository: any UsageSnapshotRepository,
        appSettingsRepository: any AppSettingsRepository,
        registry: ProviderRegistry
    ) {
        self.actual5hRepo = actual5hRepository
        self.actual7dRepo = actual7dRepository
        self.scheduledRepo = scheduledRepository
        self.commandRepo = commandRunRepository
        self.usageRepo = usageSnapshotRepository
        self.appSettings = appSettingsRepository
        self.registry = registry
        self.fetcher = UsageFetcher(
            persistSnapshot: { snapshot in
                try await usageSnapshotRepository.create(snapshot)
            },
            upsertActualWindow5h: { window, tolerance in
                try await actual5hRepository.upsertByEndAt(window, tolerance: tolerance)
            },
            upsertActualWindow7d: { window, tolerance in
                try await actual7dRepository.upsertByEndAt(window, tolerance: tolerance)
            }
        )
    }

    /// Loads everything the cards display from already-persisted data. No CLI
    /// calls, so this returns in well under a second and is the only thing the
    /// view awaits before rendering.
    func loadFromStore() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let now = Date()
            let interval = DateInterval(start: now.addingTimeInterval(-7 * 86_400), end: now.addingTimeInterval(86_400))
            let actuals = try await actual5hRepo.fetchWindows(for: interval)
            self.activeWindows = actuals.filter { $0.startAt <= now && $0.endAt >= now }
            self.weeklyWindows = try await loadLatestWeeklyWindows(now: now)
            await loadSevenDayResets(now: now)
            await refreshUsagePercentages()
            self.recentRuns = try await commandRepo.fetchRecent(
                limit: 5,
                filter: CommandRunFilter()
            )
            await loadUsageHistory(now: now)
            self.lastError = nil
        } catch {
            self.lastError = String(describing: error)
        }
    }

    /// Refreshes usage by re-running the provider CLIs, but only if the cached
    /// usage is older than the configured throttle interval. Runs the providers
    /// concurrently and re-reads the DB-derived windows so fresh data surfaces.
    /// Safe to call on every dashboard appearance: the throttle prevents
    /// re-spawning CLIs on rapid tab switches.
    func refreshUsageIfStale() async {
        guard !isRefreshingUsage else { return }
        isRefreshingUsage = true
        defer { isRefreshingUsage = false }

        let now = Date()
        let throttle = await throttleInterval()
        if let age = await cachedUsageAge(now: now), age < throttle {
            return
        }

        await withTaskGroup(of: Void.self) { group in
            for providerID in ProviderID.allCases {
                group.addTask { [weak self] in
                    await self?.refreshUsageWindow(providerID: providerID, now: now)
                }
            }
        }
        await reloadDerivedUsage(now: now)
    }

    /// Re-reads the DB-derived usage views after a provider refresh persists new
    /// snapshots. Mirrors the usage-related portion of `loadFromStore()`.
    private func reloadDerivedUsage(now: Date) async {
        do {
            let interval = DateInterval(start: now.addingTimeInterval(-7 * 86_400), end: now.addingTimeInterval(86_400))
            let actuals = try await actual5hRepo.fetchWindows(for: interval)
            self.activeWindows = actuals.filter { $0.startAt <= now && $0.endAt >= now }
            self.weeklyWindows = try await loadLatestWeeklyWindows(now: now)
            await loadSevenDayResets(now: now)
            await refreshUsagePercentages()
            await loadUsageHistory(now: now)
            self.lastError = nil
        } catch {
            self.lastError = String(describing: error)
        }
    }

    /// Age of the freshest cached usage snapshot across providers, or nil when
    /// nothing has been fetched yet (treated as stale so a first fetch runs).
    private func cachedUsageAge(now: Date) async -> TimeInterval? {
        var newest: Date?
        for providerID in ProviderID.allCases {
            if let snapshot = try? await usageRepo.fetchLatest(providerID: providerID) {
                if newest == nil || snapshot.capturedAt > newest! {
                    newest = snapshot.capturedAt
                }
            }
        }
        guard let newest else { return nil }
        return now.timeIntervalSince(newest)
    }

    private func throttleInterval() async -> TimeInterval {
        let stored = (try? await appSettings.get(
            AppSettingsKeys.usageRefreshThrottleSeconds,
            as: Int.self
        )) ?? nil
        let seconds = stored ?? AppSettingsKeys.defaultUsageRefreshThrottleSeconds
        return TimeInterval(seconds)
    }

    private func loadUsageHistory(now: Date, days: Int = 7) async {
        let cal = Calendar.current
        let endOfToday = cal.startOfDay(for: now).addingTimeInterval(86_400)
        let weekStart = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: now)) ?? now
        let interval = DateInterval(start: weekStart, end: endOfToday)
        do {
            let actuals = try await actual5hRepo.fetchWindows(for: interval)
            var bucket: [Date: [ProviderID: Int]] = [:]
            for d in 0..<days {
                if let date = cal.date(byAdding: .day, value: d, to: weekStart) {
                    bucket[cal.startOfDay(for: date)] = [:]
                }
            }
            for window in actuals {
                let day = cal.startOfDay(for: window.startAt)
                bucket[day, default: [:]][window.providerID, default: 0] += 1
            }
            let sortedDays = bucket.keys.sorted()
            var history: [DailyProviderUsage] = []
            for day in sortedDays {
                for provider in ProviderID.allCases {
                    let count = bucket[day]?[provider] ?? 0
                    history.append(DailyProviderUsage(date: day, providerID: provider, count: count))
                }
            }
            self.dailyUsageHistory = history

            var sparkline: [ProviderID: [Int]] = [:]
            for provider in ProviderID.allCases {
                sparkline[provider] = sortedDays.map { bucket[$0]?[provider] ?? 0 }
            }
            self.sparklineCounts = sparkline
        } catch {
            self.dailyUsageHistory = []
            self.sparklineCounts = [:]
        }
    }

    private func refreshUsageWindow(providerID: ProviderID, now: Date) async {
        do {
            let adapter = try registry.adapter(for: providerID)
            _ = try await fetcher.fetchAndPersist(adapter: adapter, now: now)
        } catch {
            NSLog("\(providerID.displayName) usage refresh failed: \(error)")
        }
    }

    /// Detects a recent weekly (7d) reset for each active weekly window by
    /// scanning the last ~8 days of usage snapshots. Keeps the most recent
    /// `.sevenDay` event whose observation falls inside the active weekly window,
    /// so the card only flags a reset relevant to the window being shown.
    private func loadSevenDayResets(now: Date) async {
        var result: [ProviderID: UsageResetEvent] = [:]
        let lookback = DateInterval(
            start: now.addingTimeInterval(-8 * 86_400),
            end: now.addingTimeInterval(86_400)
        )
        for window in weeklyWindows {
            let providerID = window.providerID
            guard let snapshots = try? await usageRepo.fetchInRange(
                providerID: providerID,
                interval: lookback
            ) else { continue }
            let series = UsageHistorySeries(providerID: providerID, snapshots: snapshots)
            let events = UsageResetDetector.detect(in: series).filter {
                $0.kind == .sevenDay
                    && $0.detectedAt >= window.startAt
                    && $0.detectedAt <= window.endAt
            }
            if let latest = events.max(by: { $0.detectedAt < $1.detectedAt }) {
                result[providerID] = latest
            }
        }
        self.sevenDayResets = result
    }

    func recentSevenDayReset(for providerID: ProviderID) -> Bool {
        sevenDayResets[providerID] != nil
    }

    private func loadLatestWeeklyWindows(now: Date) async throws -> [ActualWindow7d] {
        var windows: [ActualWindow7d] = []
        for providerID in ProviderID.allCases {
            if let window = try await actual7dRepo.fetchLatest(providerID: providerID),
               window.endAt >= now {
                windows.append(window)
            }
        }
        return windows
    }

    private func refreshUsagePercentages() async {
        var next: [UUID: Double] = [:]
        var cache: [ProviderID: NormalizedUsage?] = [:]
        for window in activeWindows {
            let normalized: NormalizedUsage?
            if let cached = cache[window.providerID] {
                normalized = cached
            } else {
                normalized = try? await loadLatestNormalized(providerID: window.providerID)
                cache[window.providerID] = normalized
            }
            if let pct = normalized?.usedPercentage {
                next[window.id] = pct
            }
        }
        self.activeWindowUsagePercentages = next
    }

    private func loadLatestNormalized(providerID: ProviderID) async throws -> NormalizedUsage? {
        guard let snapshot = try await usageRepo.fetchLatest(providerID: providerID) else {
            return nil
        }
        guard let data = snapshot.normalizedJSON.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(NormalizedUsage.self, from: data)
    }

}
