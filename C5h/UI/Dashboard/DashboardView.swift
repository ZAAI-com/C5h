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
    }

    @ViewBuilder
    private func content(_ viewModel: DashboardViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: C5hSpacing.lg) {
                Text("Dashboard").font(C5hTypography.titleFont)
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
    }

    private func activeWindowsCard(viewModel: DashboardViewModel) -> some View {
        DashboardCard(title: "Active windows") {
            if viewModel.activeWindows.isEmpty {
                Text("No active 5h window right now.").foregroundStyle(C5hColors.fgSecondary)
            } else {
                VStack(alignment: .leading, spacing: C5hSpacing.sm) {
                    ForEach(viewModel.activeWindows) { window in
                        HStack(spacing: C5hSpacing.sm) {
                            Circle().fill(brandColor(for: window.providerID)).frame(width: 10, height: 10)
                            Text(window.providerID.displayName).font(C5hTypography.bodyFont)
                            Spacer()
                            Text("ends \(window.endAt.formatted(date: .omitted, time: .shortened))")
                                .font(C5hTypography.captionFont)
                                .foregroundStyle(C5hColors.fgSecondary)
                        }
                    }
                }
            }
        }
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
                }
                Button {
                    Task { await viewModel.reload() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func providerHealthCard(viewModel: DashboardViewModel) -> some View {
        DashboardCard(title: "Provider health") {
            VStack(alignment: .leading, spacing: C5hSpacing.sm) {
                ForEach(ProviderID.allCases) { id in
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
        id == .claude ? ProviderBrandColor.claude : ProviderBrandColor.codex
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
        .background(C5hColors.chrome)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
