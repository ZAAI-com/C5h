import SwiftUI
import C5hCore
import C5hStore

struct DashboardView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var viewModel: DashboardViewModel?
    @State private var coordinator: ManualTriggerCoordinator?
    @State private var startNowProvider: ProviderID?

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
               let actualRepo = appEnv.actualWindowRepository,
               let scheduledRepo = appEnv.scheduledPromptRepository,
               let cmdRepo = appEnv.commandRunRepository,
               let usageRepo = appEnv.usageSnapshotRepository,
               let registry = appEnv.providerRegistry {
                let vm = DashboardViewModel(
                    actualRepository: actualRepo,
                    scheduledRepository: scheduledRepo,
                    commandRunRepository: cmdRepo,
                    usageSnapshotRepository: usageRepo,
                    registry: registry
                )
                viewModel = vm
                if coordinator == nil {
                    coordinator = ManualTriggerCoordinator(
                        registry: registry,
                        actualWindowRepository: actualRepo
                    )
                }
                await vm.reload()
            }
        }
        .sheet(item: Binding(
            get: { startNowProvider.map(ProviderTag.init) },
            set: { startNowProvider = $0?.id }
        )) { tag in
            StartProviderNowSheet(defaultProviderID: tag.id) { providerID, prompt, projectPath in
                guard let coordinator else {
                    throw C5hError.providerNotConfigured("trigger coordinator")
                }
                _ = try await coordinator.startNow(
                    providerID: providerID,
                    prompt: prompt,
                    projectPath: projectPath
                )
                await viewModel?.reload()
            }
        }
        .onAppear {
            // Reload on every visit so Active Windows / Recent Runs / Provider Health
            // pick up changes that happened while the user was on another tab.
            if let viewModel {
                Task { await viewModel.reload() }
            }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: DashboardViewModel) -> some View {
        ScrollView {
            // LEVEL 2 — Material content cards; chips and quick-action buttons
            // remain glass since they are navigation-layer affordances.
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
                    quickActionsCard(viewModel: viewModel)
                    providerHealthCard(viewModel: viewModel)
                    recentRunsCard(viewModel: viewModel)
                }
            }
            .padding(C5hSpacing.xl)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Text("Dashboard").font(.headline)
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(ProviderID.allCases) { id in
                        Button("Start \(id.displayName) now") {
                            startNowProvider = id
                        }
                    }
                } label: {
                    Label("Start now", systemImage: "play.circle.fill")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload dashboard")
            }
        }
    }

    private func activeWindowsCard(viewModel: DashboardViewModel) -> some View {
        DashboardCard(title: "Active windows") {
            if viewModel.activeWindows.isEmpty {
                Text("No active windows right now.").foregroundStyle(C5hColors.fgSecondary)
            } else {
                VStack(alignment: .leading, spacing: C5hSpacing.sm) {
                    ForEach(viewModel.activeWindows) { window in
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
                    }
                }
            }
        }
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

    private func quickActionsCard(viewModel: DashboardViewModel) -> some View {
        DashboardCard(title: "Quick actions") {
            VStack(alignment: .leading, spacing: C5hSpacing.sm) {
                ForEach(ProviderID.allCases) { id in
                    Button {
                        startNowProvider = id
                    } label: {
                        Label("Start \(id.displayName) now", systemImage: "play.circle.fill")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(C5hColors.tintForProvider(id))
                }
                Button {
                    Task { await viewModel.reload() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.glass)
            }
        }
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
                            Text(run.runType.rawValue)
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

private struct ProviderTag: Identifiable {
    let id: ProviderID
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
