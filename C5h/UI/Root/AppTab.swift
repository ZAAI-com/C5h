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

    var navbarReloadHelp: String? {
        switch self {
        case .dashboard: "Reload dashboard"
        case .today: "Reload today"
        case .tomorrow: "Reload tomorrow"
        case .calendar: "Reload calendar"
        case .logs: "Reload logs"
        case .providers: "Refresh provider version and authentication status"
        case .settings: nil
        }
    }

    /// Tabs shown in the in-window navigation surface.
    /// `.settings` is reachable from both the sidebar (this list) and the macOS Settings scene (⌘,).
    static let navTabs: [AppTab] = [.dashboard, .today, .tomorrow, .calendar, .logs, .providers, .settings]

    struct SidebarSection: Identifiable {
        let title: String
        let tabs: [AppTab]
        var id: String { title }
    }

    static let navSections: [SidebarSection] = [
        SidebarSection(title: "Overview", tabs: [.dashboard]),
        SidebarSection(title: "Calendar", tabs: [.today, .tomorrow, .calendar]),
        SidebarSection(title: "Activity", tabs: [.logs, .providers]),
        SidebarSection(title: "App",      tabs: [.settings])
    ]
}
