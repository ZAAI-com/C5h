import SwiftUI
import UniformTypeIdentifiers
import C5hCore
import C5hStore

struct ProvidersView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var viewModel: ProvidersViewModel?
    @State private var pickingPathFor: ProviderID?

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
               let settings = appEnv.appSettingsRepository {
                let vm = ProvidersViewModel(registry: registry, appSettings: settings)
                viewModel = vm
                await vm.bootstrap()
            }
        }
        .fileImporter(
            isPresented: Binding(
                get: { pickingPathFor != nil },
                set: { if !$0 { pickingPathFor = nil } }
            ),
            allowedContentTypes: [.unixExecutable, .item],
            allowsMultipleSelection: false
        ) { result in
            guard let id = pickingPathFor else { return }
            pickingPathFor = nil
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task { await viewModel?.setCLIPath(id: id, url.path) }
                }
            case .failure:
                break
            }
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
                // LEVEL 3 — Provider cards are glass; group them so glass shares a sampling region.
                GlassEffectContainer(spacing: C5hSpacing.lg) {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: C5hSpacing.lg), GridItem(.flexible(), spacing: C5hSpacing.lg)],
                        spacing: C5hSpacing.lg
                    ) {
                        ForEach(ProviderID.allCases) { id in
                            ProviderCardView(
                                id: id,
                                status: viewModel.statuses[id],
                                configuredPath: viewModel.configuredPaths[id] ?? "",
                                isLoading: viewModel.loadingProviders.contains(id),
                                onDetect: { Task { await viewModel.detect(id: id) } },
                                onTest: { Task { await viewModel.runTestCommand(id: id) } },
                                onChoosePath: { pickingPathFor = id },
                                onClearPath: { Task { await viewModel.setCLIPath(id: id, nil) } }
                            )
                        }
                    }
                }
            }
            .padding(C5hSpacing.xl)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Text("Providers").font(.headline)
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        for id in ProviderID.allCases {
                            await viewModel.detect(id: id)
                        }
                    }
                } label: {
                    Label("Refresh all", systemImage: "arrow.clockwise")
                }
                .help("Re-detect all providers")
            }
        }
    }
}
