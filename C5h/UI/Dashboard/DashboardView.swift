import SwiftUI
import C5hCore
import C5hStore

struct DashboardView: View {
    var reloadToken: Int = 0
    @Environment(AppEnvironment.self) private var appEnv
    @State private var viewModel: DashboardViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                ProgressView("Loading dashboard…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: ObjectIdentifier(appEnv)) {
            if viewModel == nil,
               let actual5hRepo = appEnv.actualWindow5hRepository,
               let actual7dRepo = appEnv.actualWindow7dRepository,
               let scheduledRepo = appEnv.scheduledPromptRepository,
               let cmdRepo = appEnv.commandRunRepository,
               let usageRepo = appEnv.usageSnapshotRepository,
               let registry = appEnv.providerRegistry {
                let vm = DashboardViewModel(
                    actual5hRepository: actual5hRepo,
                    actual7dRepository: actual7dRepo,
                    scheduledRepository: scheduledRepo,
                    commandRunRepository: cmdRepo,
                    usageSnapshotRepository: usageRepo,
                    registry: registry
                )
                viewModel = vm
                await vm.reload()
            }
        }
        .onAppear {
            // Reload on every visit so Active Windows / Recent Runs / Provider Health
            // pick up changes that happened while the user was on another tab.
            if let viewModel {
                Task { await viewModel.reload() }
            }
        }
        .onChange(of: reloadToken) { _, _ in
            if let viewModel {
                Task { await viewModel.reload() }
            }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: DashboardViewModel) -> some View {
        ScrollView {
            // LEVEL 2 — Material content cards; navigation-layer affordances
            // remain in the toolbar.
            VStack(alignment: .leading, spacing: C5hSpacing.lg) {
                if let err = viewModel.lastError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(C5hTypography.captionFont)
                        .foregroundStyle(.red)
                        .padding(C5hSpacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.regularMaterial, in: C5hShape.rect(C5hRadius.s))
                }
                UsageTrendCard(history: viewModel.dailyUsageHistory)
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: C5hSpacing.lg), GridItem(.flexible(), spacing: C5hSpacing.lg)],
                    spacing: C5hSpacing.lg
                ) {
                    activeWindowsCard(viewModel: viewModel)
                    weeklyLimitsCard(viewModel: viewModel)
                    providerHealthCard(viewModel: viewModel)
                    recentRunsCard(viewModel: viewModel)
                }
            }
            .padding(C5hSpacing.xl)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Dashboard")
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, C5hSpacing.sm)
            }
        }
    }

    private func activeWindowsCard(viewModel: DashboardViewModel) -> some View {
        DashboardCard(title: "Active 5h windows") {
            if viewModel.activeWindows.isEmpty {
                Text("No active windows right now.").foregroundStyle(C5hColors.fgSecondary)
            } else {
                VStack(alignment: .leading, spacing: C5hSpacing.md) {
                    ForEach(viewModel.activeWindows) { window in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: C5hSpacing.sm) {
                                Circle().fill(brandColor(for: window.providerID)).frame(width: 10, height: 10)
                                Text(window.providerID.displayName).font(C5hTypography.bodyFont)
                                Text(windowKindLabel(durationSeconds: window.durationSeconds))
                                    .font(C5hTypography.captionFont)
                                    .foregroundStyle(C5hColors.fgTertiary)
                                if let pct = viewModel.activeWindowUsagePercentages[window.id] {
                                    let clamped = min(max(pct, 0), 100)
                                    ProgressView(value: clamped, total: 100)
                                        .progressViewStyle(.linear)
                                        .tint(brandColor(for: window.providerID))
                                        .frame(width: 60)
                                    Text("\(Int(clamped.rounded()))%")
                                        .font(C5hTypography.captionFont)
                                        .foregroundStyle(C5hColors.fgSecondary)
                                }
                                Spacer()
                                Text("ends \(formatEndAt(window.endAt, durationSeconds: window.durationSeconds))")
                                    .font(C5hTypography.captionFont)
                                    .foregroundStyle(C5hColors.fgSecondary)
                            }
                            Text(dataSourceLabel(for: window))
                                .font(C5hTypography.captionFont)
                                .foregroundStyle(C5hColors.fgTertiary)
                        }
                    }
                }
            }
        }
    }

    private func weeklyLimitsCard(viewModel: DashboardViewModel) -> some View {
        DashboardCard(title: "Weekly limits") {
            if viewModel.weeklyWindows.isEmpty {
                Text("No weekly limit data yet.").foregroundStyle(C5hColors.fgSecondary)
            } else {
                VStack(alignment: .leading, spacing: C5hSpacing.md) {
                    ForEach(ProviderID.allCases) { providerID in
                        if let window = viewModel.weeklyWindows.first(where: { $0.providerID == providerID }) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: C5hSpacing.sm) {
                                    Circle().fill(brandColor(for: providerID)).frame(width: 10, height: 10)
                                    Text(providerID.displayName).font(C5hTypography.bodyFont)
                                    Text("7d")
                                        .font(C5hTypography.captionFont)
                                        .foregroundStyle(C5hColors.fgTertiary)
                                    let clamped = min(max(window.usedPercentage, 0), 100)
                                    ProgressView(value: clamped, total: 100)
                                        .progressViewStyle(.linear)
                                        .tint(brandColor(for: providerID))
                                        .frame(width: 60)
                                    Text("\(Int(clamped.rounded()))%")
                                        .font(C5hTypography.captionFont)
                                        .foregroundStyle(C5hColors.fgSecondary)
                                    Spacer()
                                    Text("ends \(formatEndAt(window.endAt, durationSeconds: window.durationSeconds))")
                                        .font(C5hTypography.captionFont)
                                        .foregroundStyle(C5hColors.fgSecondary)
                                }
                                Text(dataSourceLabel(for: window))
                                    .font(C5hTypography.captionFont)
                                    .foregroundStyle(C5hColors.fgTertiary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func dataSourceLabel(for window: ActualWindow5h) -> String {
        let source = "from \(window.providerID.displayName) CLI"
        let confidence = window.confidence == .estimated ? "start: estimated" : "start: exact"
        return "\(source) · \(confidence)"
    }

    private func dataSourceLabel(for window: ActualWindow7d) -> String {
        let source = "from \(window.providerID.displayName) CLI"
        let confidence = window.confidence == .estimated ? "start: estimated" : "start: exact"
        return "\(source) · \(confidence)"
    }

    private func windowKindLabel(durationSeconds: Int) -> String {
        switch durationSeconds {
        case 5 * 3600: return "5h"
        case 7 * 24 * 3600: return "7d"
        default:
            let hours = durationSeconds / 3600
            return "\(hours)h"
        }
    }

    private func formatEndAt(_ date: Date, durationSeconds: Int) -> String {
        if durationSeconds > 24 * 3600 {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func providerHealthCard(viewModel: DashboardViewModel) -> some View {
        DashboardCard(title: "Provider health") {
            VStack(alignment: .leading, spacing: C5hSpacing.md) {
                ForEach(ProviderID.allCases) { id in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: C5hSpacing.sm) {
                            Circle().fill(brandColor(for: id)).frame(width: 10, height: 10)
                            Text(id.displayName)
                            Spacer()
                            if let status = viewModel.providerStatuses[id] {
                                ProviderStatusBadge(state: ProviderHealthState(from: status))
                            } else {
                                Text("unknown")
                                    .font(C5hTypography.captionFont)
                                    .foregroundStyle(C5hColors.fgTertiary)
                            }
                        }
                        if let counts = viewModel.sparklineCounts[id], counts.contains(where: { $0 > 0 }) {
                            UsageSparklineView(counts: counts, color: brandColor(for: id))
                                .frame(height: 22)
                        }
                    }
                }
            }
        }
    }

    private func recentRunsCard(viewModel: DashboardViewModel) -> some View {
        DashboardCard(title: "Recent command runs") {
            if viewModel.recentRuns.isEmpty {
                Text("No recent runs.").foregroundStyle(C5hColors.fgSecondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(viewModel.recentRuns) { run in
                        HStack(spacing: C5hSpacing.sm) {
                            StatusBadge(status: run.status)
                            Text(run.commandName.rawValue)
                                .font(C5hTypography.captionFont)
                            Text(run.providerID.displayName)
                                .font(C5hTypography.captionFont)
                                .foregroundStyle(C5hColors.fgSecondary)
                            Spacer()
                            Text(run.startedAt.formatted(.relative(presentation: .numeric)))
                                .font(C5hTypography.captionFont)
                                .foregroundStyle(C5hColors.fgTertiary)
                        }
                    }
                }
            }
        }
    }

    private func brandColor(for id: ProviderID) -> Color {
        C5hColors.tintForProvider(id)
    }
}

struct DashboardCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: C5hSpacing.md) {
            Text(title).font(C5hTypography.captionFont).foregroundStyle(C5hColors.fgSecondary)
            content()
        }
        .padding(C5hSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        // LEVEL 2 — content panel uses Material, not glass. Glass is reserved
        // for the navigation layer (sidebar, toolbars, sheets, inspector,
        // floating chips, hero panels).
        .background(.regularMaterial, in: C5hShape.rect(C5hRadius.l))
    }
}
