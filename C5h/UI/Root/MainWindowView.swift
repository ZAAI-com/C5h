import SwiftUI

struct MainWindowView: View {
    @State private var selectedTab: AppTab = .today
    @State private var showOnboarding: Bool = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @Environment(AppEnvironment.self) private var appEnv

    var body: some View {
        Group {
            if showOnboarding {
                OnboardingView(appSettings: appEnv.appSettingsRepository) {
                    withAnimation(C5hAnimation.morph) {
                        showOnboarding = false
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 1.02)))
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    SidebarView(selection: $selectedTab)
                        .toolbar(removing: .sidebarToggle)
                } detail: {
                    detail
                }
                .navigationSplitViewStyle(.balanced)
                .onChange(of: columnVisibility) { _, newValue in
                    // Sidebar must remain visible at all times; if SwiftUI auto-collapses
                    // it (e.g. tight detail content) we restore .all immediately.
                    if newValue != .all {
                        columnVisibility = .all
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 980, minHeight: 640)
        // Glass-aware Material backdrop so the detail area never reads as flat
        // white during route bootstrap.
        .containerBackground(.thinMaterial, for: .window)
        .task(id: ObjectIdentifier(appEnv)) {
            guard let settings = appEnv.appSettingsRepository else { return }
            if await OnboardingView.shouldShow(appSettings: settings) {
                showOnboarding = true
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selectedTab {
        case .dashboard:
            DashboardView()
        case .today:
            DayCalendarScreen(date: .now, title: "Today")
        case .tomorrow:
            DayCalendarScreen(
                date: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now,
                title: "Tomorrow"
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
