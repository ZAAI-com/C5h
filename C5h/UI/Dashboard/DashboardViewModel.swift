import Foundation
import Observation
import C5hCore
import C5hStore

@Observable
@MainActor
final class DashboardViewModel {
    var activeWindows: [ActualWindow] = []
    var upcomingPrompts: [ScheduledPrompt] = []
    var recentRuns: [CommandRun] = []
    var providerStatuses: [ProviderID: ProviderStatus] = [:]
    var dailyUsageHistory: [DailyProviderUsage] = []
    var sparklineCounts: [ProviderID: [Int]] = [:]
    var lastError: String?
    var isLoading: Bool = false

    private let actualRepo: any ActualWindowRepository
    private let scheduledRepo: any ScheduledPromptRepository
    private let commandRepo: any CommandRunRepository
    private let usageRepo: any UsageSnapshotRepository
    private let registry: ProviderRegistry

    init(
        actualRepository: any ActualWindowRepository,
        scheduledRepository: any ScheduledPromptRepository,
        commandRunRepository: any CommandRunRepository,
        usageSnapshotRepository: any UsageSnapshotRepository,
        registry: ProviderRegistry
    ) {
        self.actualRepo = actualRepository
        self.scheduledRepo = scheduledRepository
        self.commandRepo = commandRunRepository
        self.usageRepo = usageSnapshotRepository
        self.registry = registry
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let now = Date()
            for providerID in ProviderID.allCases {
                await refreshUsageWindow(providerID: providerID, now: now)
            }
            let interval = DateInterval(start: now.addingTimeInterval(-86_400), end: now.addingTimeInterval(86_400))
            let actuals = try await actualRepo.fetchWindows(for: interval)
            self.activeWindows = actuals.filter { $0.startAt <= now && $0.endAt >= now }
            self.recentRuns = try await commandRepo.fetchRecent(
                limit: 5,
                filter: CommandRunFilter()
            )
            for id in ProviderID.allCases {
                let adapter = try registry.adapter(for: id)
                providerStatuses[id] = await adapter.detectStatus()
            }
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
            let actuals = try await actualRepo.fetchWindows(for: interval)
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
            let snapshot = try await adapter.collectUsage()
            try await usageRepo.create(snapshot)
            let window = try actualWindow(from: snapshot)

            guard window.startAt <= now, window.endAt >= now else {
                return
            }

            let duplicateSearch = DateInterval(
                start: window.startAt.addingTimeInterval(-TimeInterval(window.durationSeconds)),
                end: window.endAt.addingTimeInterval(1)
            )
            let existing = try await actualRepo.fetchWindows(for: duplicateSearch)
            guard !existing.contains(where: { overlaps($0, window) }) else {
                return
            }

            try await actualRepo.create(window)
        } catch {
            NSLog("\(providerID.displayName) usage refresh failed: \(error)")
        }
    }

    private func actualWindow(from snapshot: UsageSnapshot) throws -> ActualWindow {
        switch snapshot.providerID {
        case .claude:
            return try ClaudeUsageStatus.parsePayload(snapshot.rawJSON).actualWindow(
                providerID: .claude,
                createdAt: snapshot.capturedAt
            )
        case .codex:
            return try CodexUsageStatus.parsePayload(snapshot.rawJSON).actualWindow(
                providerID: .codex,
                createdAt: snapshot.capturedAt
            )
        }
    }

    private func overlaps(_ existing: ActualWindow, _ detected: ActualWindow) -> Bool {
        existing.providerID == detected.providerID
            && existing.startAt < detected.endAt
            && existing.endAt > detected.startAt
    }
}
