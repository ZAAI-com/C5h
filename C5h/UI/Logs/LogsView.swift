import SwiftUI
import C5hCore
import C5hStore

struct LogsView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var viewModel: LogsViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                VStack { ProgressView("Opening database…") }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: ObjectIdentifier(appEnv)) {
            if viewModel == nil, let repo = appEnv.commandRunRepository {
                let vm = LogsViewModel(repository: repo)
                viewModel = vm
                await vm.reload()
            }
        }
        .onAppear {
            if let viewModel {
                Task { await viewModel.reload() }
            }
        }
    }

    @ViewBuilder
    private func content(viewModel: LogsViewModel) -> some View {
        @Bindable var bound = viewModel
        // Plain HStack with a fixed-width detail panel. HSplitView (an
        // NSSplitView bridge) was claiming its idealWidths via SwiftUI
        // layout and pushing back on the NavigationSplitView sidebar,
        // squeezing it below the 220pt fixed width. With a fixed detail
        // and a flexible table, the sidebar holds.
        HStack(spacing: 0) {
            tableSide(viewModel: viewModel)
                .frame(minWidth: 380, maxWidth: .infinity)
            Divider()
            CommandRunDetailView(run: viewModel.selectedRun)
                .frame(width: 360)
        }
        .searchable(
            text: $bound.searchText,
            placement: .toolbar,
            prompt: "Search prompt, cwd, error…"
        )
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Provider", selection: providerBinding(viewModel: viewModel)) {
                    Text("All providers").tag(Optional<ProviderID>.none)
                    ForEach(ProviderID.allCases) { id in
                        Text(id.displayName).tag(Optional(id))
                    }
                }

                Picker("Status", selection: statusBinding(viewModel: viewModel)) {
                    Text("Any status").tag(Optional<CommandRunStatus>.none)
                    ForEach(CommandRunStatus.allCases, id: \.self) { st in
                        Text(st.rawValue.capitalized).tag(Optional(st))
                    }
                }

                Picker("Type", selection: typeBinding(viewModel: viewModel)) {
                    Text("Any type").tag(Optional<CommandRunType>.none)
                    ForEach(CommandRunType.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(Optional(t))
                    }
                }

                Picker("Range", selection: rangeBinding(viewModel: viewModel)) {
                    ForEach(LogsDateRange.allCases) { r in
                        Text(r.label).tag(r)
                    }
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload")
            }
        }
    }

    @ViewBuilder
    private func tableSide(viewModel: LogsViewModel) -> some View {
        @Bindable var bound = viewModel
        VStack(spacing: 0) {
            if let err = viewModel.lastError {
                Text(err)
                    .font(C5hTypography.captionFont)
                    .foregroundStyle(.red)
                    .padding(C5hSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
            }
            if viewModel.runs.isEmpty && !viewModel.isLoading {
                emptyState
            } else {
                CommandRunTable(runs: viewModel.filteredRuns, selection: $bound.selection)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: C5hSpacing.md) {
            Image(systemName: "terminal").font(.system(size: 32, weight: .light))
                .foregroundStyle(C5hColors.fgTertiary)
            Text("No command runs yet").font(C5hTypography.bodyFont)
            Text("CLI invocations will appear here once milestone M3 lands.")
                .font(C5hTypography.captionFont)
                .foregroundStyle(C5hColors.fgSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func providerBinding(viewModel: LogsViewModel) -> Binding<ProviderID?> {
        Binding(
            get: { viewModel.providerFilter },
            set: { viewModel.providerFilter = $0; Task { await viewModel.reload() } }
        )
    }

    private func statusBinding(viewModel: LogsViewModel) -> Binding<CommandRunStatus?> {
        Binding(
            get: { viewModel.statusFilter },
            set: { viewModel.statusFilter = $0; Task { await viewModel.reload() } }
        )
    }

    private func typeBinding(viewModel: LogsViewModel) -> Binding<CommandRunType?> {
        Binding(
            get: { viewModel.typeFilter },
            set: { viewModel.typeFilter = $0; Task { await viewModel.reload() } }
        )
    }

    private func rangeBinding(viewModel: LogsViewModel) -> Binding<LogsDateRange> {
        Binding(
            get: { viewModel.dateRange },
            set: { viewModel.dateRange = $0; Task { await viewModel.reload() } }
        )
    }
}
