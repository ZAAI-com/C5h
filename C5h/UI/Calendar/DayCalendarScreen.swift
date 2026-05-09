import SwiftUI
import C5hCore
import C5hStore

struct DayCalendarScreen: View {
    let date: Date
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
        .task(id: ObjectIdentifier(appEnv)) {
            if viewModel == nil,
               let plannedRepo = appEnv.plannedWindowRepository,
               let actualRepo = appEnv.actualWindowRepository {
                let vm = DayCalendarViewModel(
                    date: date,
                    plannedRepository: plannedRepo,
                    actualRepository: actualRepo
                )
                viewModel = vm
                await vm.reload()
            }
        }
        .task {
            for await tick in Timer.publish(every: 30, on: .main, in: .common).autoconnect().values {
                now = tick
            }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: DayCalendarViewModel) -> some View {
        @Bindable var bound = viewModel
        VStack(spacing: 0) {
            toolbar(viewModel: viewModel)
            Divider()
            DayCalendarView(viewModel: viewModel, layout: layout, now: now)
        }
        .sheet(item: $bound.selection) { selection in
            WindowInspectorView(selection: selection)
        }
    }

    private func toolbar(viewModel: DayCalendarViewModel) -> some View {
        HStack(spacing: C5hSpacing.md) {
            Button {
                viewModel.goToPreviousDay()
                Task { await viewModel.reload() }
            } label: {
                Image(systemName: "chevron.left")
            }
            Text(viewModel.date.formatted(date: .complete, time: .omitted))
                .font(C5hTypography.titleFont)
            Button {
                viewModel.goToNextDay()
                Task { await viewModel.reload() }
            } label: {
                Image(systemName: "chevron.right")
            }
            Spacer()
            if let err = viewModel.lastError {
                Text(err).foregroundStyle(.red).font(C5hTypography.captionFont)
            }
            Button {
                Task { await viewModel.reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
        }
        .padding(.horizontal, C5hSpacing.lg)
        .padding(.vertical, C5hSpacing.sm)
        .background(C5hColors.chrome)
    }
}

struct WeekCalendarScreen: View {
    var body: some View {
        PlaceholderScreen(
            title: "Week Calendar",
            systemImage: AppTab.calendar.systemImage,
            subtitle: "7-day overview by provider — coming in M10."
        )
    }
}
