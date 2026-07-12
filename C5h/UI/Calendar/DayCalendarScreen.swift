import SwiftUI
import C5hCore
import C5hStore

struct DayCalendarScreen: View {
    let date: Date
    var title: String = ""
    var reloadToken: Int = 0
    @Environment(AppEnvironment.self) private var appEnv
    @State private var viewModel: DayCalendarViewModel?
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
               let actual5hRepo = appEnv.actualWindow5hRepository,
               let actual7dRepo = appEnv.actualWindow7dRepository,
               let scheduledRepo = appEnv.scheduledPromptRepository {
                let vm = DayCalendarViewModel(
                    date: date,
                    plannedRepository: plannedRepo,
                    actual5hRepository: actual5hRepo,
                    actual7dRepository: actual7dRepo,
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
        .onChange(of: reloadToken) { _, _ in
            if let viewModel {
                Task { await viewModel.reload() }
            }
        }
        .onChange(of: appEnv.databaseChangeMonitor?.changeToken) { _, _ in
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
        DayCalendarView(
            viewModel: viewModel,
            layout: layout,
            now: now,
            onSelectPlanned: { window in
                withAnimation(C5hAnimation.morph) {
                    let next = CalendarSelection.planned(window)
                    viewModel.selection = (viewModel.selection == next) ? nil : next
                }
            },
            onSelectActual: { window in
                withAnimation(C5hAnimation.morph) {
                    let next = CalendarSelection.actual(window)
                    viewModel.selection = (viewModel.selection == next) ? nil : next
                }
            },
            onSelectWeekly: { window in
                withAnimation(C5hAnimation.morph) {
                    let next = CalendarSelection.weekly(window)
                    viewModel.selection = (viewModel.selection == next) ? nil : next
                }
            },
            onMovePlanned: { window, start in
                Task { await viewModel.move(window: window, to: start) }
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
        // Keep the inspector inside the detail content instead of using
        // SwiftUI's native trailing column, which can temporarily collapse the
        // root NavigationSplitView sidebar while solving widths.
        .overlay(alignment: .trailing) {
            CalendarInspectorPane(
                selection: viewModel.selection,
                resetEvent: viewModel.selection.flatMap { viewModel.resetEvent(for: $0) },
                onClose: {
                    withAnimation(C5hAnimation.morph) {
                        viewModel.selection = nil
                    }
                },
                onDelete: { id in
                    withAnimation(C5hAnimation.morph) {
                        viewModel.selection = nil
                    }
                    Task { try? await viewModel.delete(id: id) }
                }
            )
        }
    }

    @ToolbarContentBuilder
    private func actionToolbar(viewModel: DayCalendarViewModel) -> some ToolbarContent {
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

private struct BootstrapKey: Hashable {
    let env: ObjectIdentifier
    let day: Date
}
