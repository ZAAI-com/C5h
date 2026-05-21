import SwiftUI
import C5hCore
import C5hStore

struct ProvidersView: View {
    var reloadToken: Int = 0
    @Environment(AppEnvironment.self) private var appEnv
    @State private var viewModel: ProvidersViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                ProgressView("Initializing providers…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: ObjectIdentifier(appEnv)) {
            if viewModel == nil,
               let registry = appEnv.providerRegistry,
               let settings = appEnv.appSettingsRepository,
               let usageRepo = appEnv.usageSnapshotRepository,
               let actual5hRepo = appEnv.actualWindow5hRepository,
               let actual7dRepo = appEnv.actualWindow7dRepository {
                let vm = ProvidersViewModel(
                    registry: registry,
                    appSettings: settings,
                    usageSnapshotRepository: usageRepo,
                    actual5hRepository: actual5hRepo,
                    actual7dRepository: actual7dRepo,
                    refreshProviderStatus: { id in
                        await appEnv.refreshProviderStatus(id: id)
                    }
                )
                viewModel = vm
                await vm.bootstrap()
            }
        }
        .onChange(of: reloadToken) { _, _ in
            Task { await appEnv.refreshAllProviderStatuses() }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: ProvidersViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: C5hSpacing.lg) {
                if let err = viewModel.lastError {
                    Text(err)
                        .foregroundStyle(.red)
                        .font(C5hTypography.captionFont)
                }
                // LEVEL 2 — Material content cards; action buttons inside each
                // card stay glass.
                LazyVStack(spacing: C5hSpacing.lg) {
                    ForEach(ProviderID.allCases) { id in
                        ProviderCardView(
                            id: id,
                            status: appEnv.providerStatuses[id],
                            configuredPath: viewModel.configuredPaths[id] ?? "",
                            wakePrompt: viewModel.wakePrompts[id] ?? "",
                            usageCheck: viewModel.usageChecks[id],
                            isStatusLoading: appEnv.providerStatusLoading.contains(id),
                            isUsageLoading: viewModel.loadingUsageProviders.contains(id),
                            onVersion: { Task { await appEnv.runProviderVersionStatus(id: id) } },
                            onAuthStatus: { Task { await appEnv.runProviderAuthStatus(id: id) } },
                            onUsage: { Task { await viewModel.runUsage(id: id) } },
                            onSetPath: { newPath in
                                Task { await viewModel.setCLIPath(id: id, newPath.isEmpty ? nil : newPath) }
                            },
                            onClearPath: { Task { await viewModel.setCLIPath(id: id, nil) } },
                            onSetWakePrompt: { newValue in
                                Task { await viewModel.setWakePrompt(id: id, newValue) }
                            }
                        )
                    }
                }
            }
            .padding(C5hSpacing.xl)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Providers")
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, C5hSpacing.sm)
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await appEnv.refreshAllProviderStatuses() }
                } label: {
                    Label("Refresh all", systemImage: "arrow.clockwise")
                }
                .help("Refresh provider version and authentication status")
            }
        }
    }
}
