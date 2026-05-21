import SwiftUI

struct MainWindowView: View {
    @State private var selectedTab: AppTab = .today
    @State private var showOnboarding: Bool = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var dayAnchor: Date = .now
    @State private var reloadToken: Int = 0
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch appEnv.loadState {
            case .loading:
                bootstrapSplash
            case .failed(let message):
                bootstrapFailure(message: message)
            case .ready:
                readyBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 980, minHeight: 640)
        // Glass-aware Material backdrop so the detail area never reads as flat
        // white during route bootstrap.
        .containerBackground(.thinMaterial, for: .window)
    }

    @ViewBuilder
    private var readyBody: some View {
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
                    SidebarView(selection: $selectedTab) {
                        reloadToken += 1
                    }
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
        .task {
            guard let settings = appEnv.appSettingsRepository else { return }
            if await OnboardingView.shouldShow(appSettings: settings) {
                showOnboarding = true
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged).map({ $0 }) {
                dayAnchor = .now
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // Sleep/wake or app activation may have crossed midnight without
                // delivering NSCalendarDayChanged; re-anchor on activation.
                if !Calendar.current.isDate(dayAnchor, inSameDayAs: .now) {
                    dayAnchor = .now
                }
            }
        }
    }

    private var bootstrapSplash: some View {
        VStack(spacing: C5hSpacing.md) {
            ProgressView()
                .controlSize(.large)
            Text("Starting C5h…")
                .font(C5hTypography.bodyFont)
                .foregroundStyle(C5hColors.fgSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func bootstrapFailure(message: String) -> some View {
        VStack(spacing: C5hSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.red)
            Text("C5h failed to start")
                .font(C5hTypography.bodyFont)
            Text(message)
                .font(C5hTypography.captionFont)
                .foregroundStyle(C5hColors.fgSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, C5hSpacing.lg)
            Button("Retry") {
                Task { await appEnv.bootstrap() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var detail: some View {
        switch selectedTab {
        case .dashboard:
            DashboardView(reloadToken: reloadToken)
        case .today:
            DayCalendarScreen(date: dayAnchor, title: "Today", reloadToken: reloadToken)
        case .tomorrow:
            DayCalendarScreen(
                date: Calendar.current.date(byAdding: .day, value: 1, to: dayAnchor) ?? dayAnchor,
                title: "Tomorrow",
                reloadToken: reloadToken
            )
        case .calendar:
            WeekCalendarScreen(reloadToken: reloadToken)
        case .logs:
            LogsView(reloadToken: reloadToken)
        case .providers:
            ProvidersView(reloadToken: reloadToken)
        case .settings:
            SettingsView()
        }
    }
}

#Preview {
    MainWindowView()
        .frame(width: 1200, height: 800)
}
