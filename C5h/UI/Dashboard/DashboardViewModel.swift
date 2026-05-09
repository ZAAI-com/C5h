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
            await refreshClaudeUsageWindow(now: now)
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
            self.lastError = nil
        } catch {
            self.lastError = String(describing: error)
        }
    }

    private func refreshClaudeUsageWindow(now: Date) async {
        do {
            let adapter = try registry.adapter(for: .claude)
            let snapshot = try await adapter.collectUsage()
            try await usageRepo.create(snapshot)
            let status = try ClaudeUsageStatus.parsePayload(snapshot.rawJSON)
            let window = status.actualWindow(providerID: .claude, createdAt: snapshot.capturedAt)

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
            NSLog("Claude usage refresh failed: \(error)")
        }
    }

    private func overlaps(_ existing: ActualWindow, _ detected: ActualWindow) -> Bool {
        existing.providerID == detected.providerID
            && existing.startAt < detected.endAt
            && existing.endAt > detected.startAt
    }
}
