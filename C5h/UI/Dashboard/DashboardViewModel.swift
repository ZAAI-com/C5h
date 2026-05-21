import Foundation
import Observation
import C5hCore
import C5hStore

@Observable
@MainActor
final class DashboardViewModel {
    var activeWindows: [ActualWindow5h] = []
    var weeklyWindows: [ActualWindow7d] = []
    var activeWindowUsagePercentages: [UUID: Double] = [:]
    var upcomingPrompts: [ScheduledPrompt] = []
    var recentRuns: [CommandRun] = []
    var dailyUsageHistory: [DailyProviderUsage] = []
    var sparklineCounts: [ProviderID: [Int]] = [:]
    var lastError: String?
    var isLoading: Bool = false

    private let actual5hRepo: any ActualWindow5hRepository
    private let actual7dRepo: any ActualWindow7dRepository
    private let scheduledRepo: any ScheduledPromptRepository
    private let commandRepo: any CommandRunRepository
    private let usageRepo: any UsageSnapshotRepository
    private let registry: ProviderRegistry
    private let fetcher: UsageFetcher

    init(
        actual5hRepository: any ActualWindow5hRepository,
        actual7dRepository: any ActualWindow7dRepository,
        scheduledRepository: any ScheduledPromptRepository,
        commandRunRepository: any CommandRunRepository,
        usageSnapshotRepository: any UsageSnapshotRepository,
        registry: ProviderRegistry
    ) {
        self.actual5hRepo = actual5hRepository
        self.actual7dRepo = actual7dRepository
        self.scheduledRepo = scheduledRepository
        self.commandRepo = commandRunRepository
        self.usageRepo = usageSnapshotRepository
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

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let now = Date()
            for providerID in ProviderID.allCases {
                await refreshUsageWindow(providerID: providerID, now: now)
            }
            let interval = DateInterval(start: now.addingTimeInterval(-7 * 86_400), end: now.addingTimeInterval(86_400))
            let actuals = try await actual5hRepo.fetchWindows(for: interval)
            self.activeWindows = actuals.filter { $0.startAt <= now && $0.endAt >= now }
            self.weeklyWindows = try await loadLatestWeeklyWindows(now: now)
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
