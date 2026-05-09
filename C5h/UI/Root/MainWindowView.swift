import SwiftUI

struct MainWindowView: View {
    @State private var selectedTab: AppTab = .today

    var body: some View {
        VStack(spacing: 0) {
            NavbarView(selectedTab: $selectedTab)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(C5hColors.background)
        }
        .frame(minWidth: 1100, minHeight: 720)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .dashboard:
            DashboardView()
        case .today:
            DayCalendarScreen(date: .now)
        case .tomorrow:
            DayCalendarScreen(
                date: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
            )
        case .calendar:
            WeekCalendarScreen()
        case .logs:
            LogsView()
        case .providers:
            ProvidersView()
        case .settings:
            SettingsView()
        }
    }
}

#Preview {
    MainWindowView()
        .frame(width: 1200, height: 800)
}
