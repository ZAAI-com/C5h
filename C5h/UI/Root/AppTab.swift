import Foundation

enum AppTab: String, CaseIterable, Identifiable, Hashable, Sendable {
    case dashboard
    case today
    case tomorrow
    case calendar
    case logs
    case providers
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .today: "Today"
        case .tomorrow: "Tomorrow"
        case .calendar: "Calendar"
        case .logs: "Logs"
        case .providers: "Providers"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "chart.xyaxis.line"
        case .today: "calendar.day.timeline.left"
        case .tomorrow: "calendar.badge.clock"
        case .calendar: "calendar"
        case .logs: "terminal"
        case .providers: "shippingbox"
        case .settings: "gearshape"
        }
    }

    /// Tabs shown in the in-window navigation surface.
    /// `.settings` is intentionally excluded — Settings opens via the macOS Settings scene (Cmd-,).
    static let navTabs: [AppTab] = [.dashboard, .today, .tomorrow, .calendar, .logs, .providers]

    struct SidebarSection: Identifiable {
        let title: String
        let tabs: [AppTab]
        var id: String { title }
    }

    static let navSections: [SidebarSection] = [
        SidebarSection(title: "Overview", tabs: [.dashboard]),
        SidebarSection(title: "Calendar", tabs: [.today, .tomorrow, .calendar]),
        SidebarSection(title: "Activity", tabs: [.logs, .providers])
    ]
}
