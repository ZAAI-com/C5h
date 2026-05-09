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
    private let registry: ProviderRegistry

    init(
        actualRepository: any ActualWindowRepository,
        scheduledRepository: any ScheduledPromptRepository,
        commandRunRepository: any CommandRunRepository,
        registry: ProviderRegistry
    ) {
        self.actualRepo = actualRepository
        self.scheduledRepo = scheduledRepository
        self.commandRepo = commandRunRepository
        self.registry = registry
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let interval = DateInterval(start: Date().addingTimeInterval(-86_400), end: Date().addingTimeInterval(86_400))
            let actuals = try await actualRepo.fetchWindows(for: interval)
            let now = Date()
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
}
