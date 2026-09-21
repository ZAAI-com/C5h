import Foundation
import Observation
import C5hCore
import C5hStore

@Observable
@MainActor
final class LogsViewModel {
    var entries: [CommandRunEntry] = []
    var selection: CommandRunEntry.ID?

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

    var selectedEntry: CommandRunEntry? {
        guard let selection else { return nil }
        return entries.first { $0.id == selection }
    }

    var filteredEntries: [CommandRunEntry] {
        entries.filter { entry in
            switch entry {
            case .readable(let run):
                return searchText.isEmpty
                    || run.command.localizedCaseInsensitiveContains(searchText)
                    || run.argumentsJSON.localizedCaseInsensitiveContains(searchText)
                    || (run.workingDirectory?.localizedCaseInsensitiveContains(searchText) ?? false)
                    || (run.errorMessage?.localizedCaseInsensitiveContains(searchText) ?? false)
            case .unreadable:
                // Unreadable rows carry no searchable text; only surface them
                // when the user is not actively filtering by a search term.
                return searchText.isEmpty
            }
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
            entries = try await repository.fetchRecentEntries(limit: 500, filter: filter)
            if let sel = selection, !entries.contains(where: { $0.id == sel }) {
                selection = entries.first?.id
            } else if selection == nil {
                selection = entries.first?.id
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
