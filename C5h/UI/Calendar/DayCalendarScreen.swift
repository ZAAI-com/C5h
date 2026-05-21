import SwiftUI
import C5hCore
import C5hStore

struct DayCalendarScreen: View {
    let date: Date
    var title: String = ""
    @Environment(AppEnvironment.self) private var appEnv
    @State private var viewModel: DayCalendarViewModel?
    @State private var coordinator: ManualTriggerCoordinator?
    @State private var now: Date = .now
    private let layout = CalendarLayoutConfig()

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                ProgressView("Loading calendar…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar { principalTitle }
        .task(id: BootstrapKey(env: ObjectIdentifier(appEnv), day: Calendar.current.startOfDay(for: date))) {
            if viewModel == nil,
               let plannedRepo = appEnv.plannedWindowRepository,
               let actualRepo = appEnv.actualWindowRepository,
               let scheduledRepo = appEnv.scheduledPromptRepository {
                let vm = DayCalendarViewModel(
                    date: date,
                    plannedRepository: plannedRepo,
                    actualRepository: actualRepo,
                    scheduledRepository: scheduledRepo,
                    usageSnapshotRepository: appEnv.usageSnapshotRepository,
                    providerRegistry: appEnv.providerRegistry,
                    appSettings: appEnv.appSettingsRepository
                )
                viewModel = vm
                await vm.reload()
            } else if let vm = viewModel,
                      !Calendar.current.isDate(vm.date, inSameDayAs: date) {
                vm.date = date
                await vm.reload()
            }
            if coordinator == nil,
               let registry = appEnv.providerRegistry,
               let actualRepo = appEnv.actualWindowRepository,
               let usageRepo = appEnv.usageSnapshotRepository {
                coordinator = ManualTriggerCoordinator(
                    registry: registry,
                    actualWindowRepository: actualRepo,
                    usageSnapshotRepository: usageRepo
                )
            }
        }
        .task {
            for await tick in Timer.publish(every: 30, on: .main, in: .common).autoconnect().values {
                now = tick
            }
        }
        .onAppear {
            if let viewModel {
                Task { await viewModel.reload() }
            }
        }
    }

    @ToolbarContentBuilder
    private var principalTitle: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text("\(title) \(date.c5hISODate)")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .padding(.horizontal, C5hSpacing.sm)
        }
    }

    @ViewBuilder
    private func content(_ viewModel: DayCalendarViewModel) -> some View {
        @Bindable var bound = viewModel
        DayCalendarView(
            viewModel: viewModel,
            layout: layout,
            now: now,
            onSelectPlanned: { window in
                withAnimation(C5hAnimation.morph) {
                    viewModel.selection = .planned(window)
                }
            },
            onSelectActual: { window in
                withAnimation(C5hAnimation.morph) {
                    viewModel.selection = .actual(window)
                }
            }
        )
        .safeAreaInset(edge: .top, spacing: 0) {
            if let err = viewModel.lastError {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(C5hTypography.captionFont)
                    .foregroundStyle(.red)
                    .padding(.horizontal, C5hSpacing.lg)
                    .padding(.vertical, C5hSpacing.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .toolbar { actionToolbar(viewModel: viewModel) }
        // Non-blocking right-side glass pane (replaces the old .sheet inspector).
        .inspector(isPresented: Binding(
            get: { viewModel.selection != nil },
            set: { newValue in
                if !newValue {
                    withAnimation(C5hAnimation.morph) {
                        viewModel.selection = nil
                    }
                }
            }
        )) {
            if let sel = viewModel.selection {
                WindowInspectorView(
                    selection: sel,
                    onEdit: { window in
                        viewModel.selection = nil
                        viewModel.presentEdit(for: window)
                    },
                    onDelete: { id in
                        viewModel.selection = nil
                        Task { try? await viewModel.delete(id: id) }
                    }
                )
                .inspectorColumnWidth(min: 280, ideal: 360, max: 480)
            } else {
                EmptyView()
            }
        }
        .sheet(isPresented: $bound.editingDraftPresented) {
            PlannedWindowEditorSheet(
                editing: viewModel.editingExisting,
                defaultStart: viewModel.date.atHour(9),
                allWindows: viewModel.planned,
                onSave: { draft in try await viewModel.save(draft: draft) },
                onDelete: { id in try await viewModel.delete(id: id) }
            )
        }
        .sheet(isPresented: $bound.startNowPresented) {
            StartProviderNowSheet(
                defaultProviderID: viewModel.startNowDefaultProvider
            ) { providerID, prompt, projectPath in
                guard let coordinator else {
                    throw C5hError.providerNotConfigured("trigger coordinator")
                }
                _ = try await coordinator.startNow(
                    providerID: providerID,
                    prompt: prompt,
                    projectPath: projectPath
                )
                await viewModel.reload()
            }
        }
    }

    @ToolbarContentBuilder
    private func actionToolbar(viewModel: DayCalendarViewModel) -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                viewModel.presentNewDraft()
            } label: {
                Label("Add planned", systemImage: "plus.circle")
            }
            .help("Create planned window")
        }

        ToolbarItem(placement: .primaryAction) {
            Menu {
                ForEach(ProviderID.allCases) { id in
                    Button("Start \(id.displayName) now") {
                        viewModel.presentStartNow(provider: id)
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
            .help("Reload")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                withAnimation(C5hAnimation.morph) {
                    if viewModel.selection == nil,
                       let firstActual = viewModel.actual.first {
                        viewModel.selection = .actual(firstActual)
                    } else if viewModel.selection == nil,
                              let firstPlanned = viewModel.planned.first {
                        viewModel.selection = .planned(firstPlanned)
                    } else {
                        viewModel.selection = nil
                    }
                }
            } label: {
                Image(systemName: "sidebar.right")
            }
            .help("Toggle inspector")
        }
    }
}

private extension Date {
    func atHour(_ hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: self) ?? self
    }
}

private struct BootstrapKey: Hashable {
    let env: ObjectIdentifier
    let day: Date
}
