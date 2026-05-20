import Foundation
import Observation
import C5hCore
import C5hStore

@Observable
@MainActor
final class LogsViewModel {
    var runs: [CommandRun] = []
    var selection: CommandRun.ID?

    var providerFilter: ProviderID?
    var statusFilter: CommandRunStatus?
    var commandNameFilter: CommandName?
    var dateRange: LogsDateRange = .last7Days
    var searchText: String = ""

    var isLoading: Bool = false
    var lastError: String?

    private let repository: any CommandRunRepository

    init(repository: any CommandRunRepository) {
        self.repository = repository
    }

    var selectedRun: CommandRun? {
        guard let selection else { return nil }
        return runs.first { $0.id == selection }
    }

    var filteredRuns: [CommandRun] {
        runs.filter { run in
            guard searchText.isEmpty
                || run.command.localizedCaseInsensitiveContains(searchText)
                || run.argumentsJSON.localizedCaseInsensitiveContains(searchText)
                || (run.workingDirectory?.localizedCaseInsensitiveContains(searchText) ?? false)
                || (run.errorMessage?.localizedCaseInsensitiveContains(searchText) ?? false)
            else {
                return false
            }
            return true
        }
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let filter = CommandRunFilter(
                providerID: providerFilter,
                status: statusFilter,
                commandName: commandNameFilter,
                since: dateRange.since
            )
            runs = try await repository.fetchRecent(limit: 500, filter: filter)
            if let sel = selection, !runs.contains(where: { $0.id == sel }) {
                selection = runs.first?.id
            } else if selection == nil {
                selection = runs.first?.id
            }
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
    }
}

enum LogsDateRange: String, CaseIterable, Identifiable, Sendable {
    case today
    case last7Days
    case last30Days
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: "Today"
        case .last7Days: "Last 7 days"
        case .last30Days: "Last 30 days"
        case .all: "All time"
        }
    }

    var since: Date? {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .today:
            return cal.startOfDay(for: now)
        case .last7Days:
            return cal.date(byAdding: .day, value: -7, to: now)
        case .last30Days:
            return cal.date(byAdding: .day, value: -30, to: now)
        case .all:
            return nil
        }
    }
}
