import SwiftUI

struct MainWindowView: View {
    @State private var selectedTab: AppTab = .today
    @State private var showOnboarding: Bool = false
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
                content
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Picker("Tab", selection: $selectedTab) {
                                ForEach(AppTab.navTabs) { tab in
                                    Label(tab.title, systemImage: tab.systemImage).tag(tab)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 980, minHeight: 640)
        .task(id: ObjectIdentifier(appEnv)) {
            guard let settings = appEnv.appSettingsRepository else { return }
            if await OnboardingView.shouldShow(appSettings: settings) {
                showOnboarding = true
            }
        }
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
