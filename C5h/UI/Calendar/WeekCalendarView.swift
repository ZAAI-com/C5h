import SwiftUI
import C5hCore
import C5hStore

struct WeekCalendarScreen: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var viewModel: WeekCalendarViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                ProgressView("Loading week…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Text("Calendar")
                                .font(.title3.weight(.semibold))
                                .padding(.horizontal, C5hSpacing.sm)
                        }
                    }
            }
        }
        .task(id: ObjectIdentifier(appEnv)) {
            if viewModel == nil,
               let plannedRepo = appEnv.plannedWindowRepository,
               let actual5hRepo = appEnv.actualWindow5hRepository {
                let vm = WeekCalendarViewModel(
                    weekStart: .now,
                    plannedRepository: plannedRepo,
                    actual5hRepository: actual5hRepo
                )
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
    private func content(_ viewModel: WeekCalendarViewModel) -> some View {
        WeekCalendarView(viewModel: viewModel)
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
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: C5hSpacing.sm) {
                        Button {
                            viewModel.goToPreviousWeek()
                            Task { await viewModel.reload() }
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .help("Previous week")

                        Text("Week of \(viewModel.weekStart.c5hISODate)")
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()

                        Button {
                            viewModel.goToNextWeek()
                            Task { await viewModel.reload() }
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .help("Next week")
                    }
                    .padding(.horizontal, C5hSpacing.sm)
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
}

struct WeekCalendarView: View {
    let viewModel: WeekCalendarViewModel

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            Divider()
            ForEach(ProviderID.allCases) { provider in
                row(for: provider)
                Divider()
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("Provider")
                .font(C5hTypography.captionFont)
                .frame(width: 110, alignment: .leading)
                .padding(.horizontal, C5hSpacing.md)
            ForEach(viewModel.days, id: \.self) { day in
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.formatted(.dateTime.weekday(.abbreviated)))
                        .font(C5hTypography.captionFont)
                        .foregroundStyle(C5hColors.fgSecondary)
                    Text(day.formatted(.dateTime.day()))
                        .font(C5hTypography.bodyFont)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, C5hSpacing.sm)
                .padding(.vertical, 6)
                // LEVEL 2 — "you are here" cue uses tinted glass for today's column.
                .modifier(TodayHeaderBackground(isToday: Calendar.current.isDateInToday(day)))
            }
        }
    }

    private func row(for provider: ProviderID) -> some View {
        HStack(spacing: 0) {
            // LEVEL 2 — provider chip is a floating identity affordance; glass capsule.
            HStack(spacing: 6) {
                Circle().fill(brandColor(for: provider)).frame(width: 8, height: 8)
                Text(provider.displayName).font(C5hTypography.captionFont)
            }
            .padding(.horizontal, C5hSpacing.sm)
            .padding(.vertical, 4)
            .glassEffect(C5hGlass.toolbar, in: .capsule)
            .frame(width: 110, alignment: .leading)
            .padding(.horizontal, C5hSpacing.md)

            ForEach(viewModel.days, id: \.self) { day in
                cellFor(day: day, provider: provider)
            }
        }
        .frame(minHeight: 80)
    }

    private func cellFor(day: Date, provider: ProviderID) -> some View {
        let cw = viewModel.windows(forDay: day, providerID: provider)
        return VStack(spacing: 4) {
            ForEach(cw.planned) { window in
                compactBlock(
                    label: timeLabel(window.startAt),
                    color: brandColor(for: provider).opacity(0.22),
                    border: brandColor(for: provider)
                )
            }
            ForEach(cw.actual) { window in
                compactBlock(
                    label: timeLabel(window.startAt),
                    color: brandColor(for: provider),
                    border: nil,
                    foreground: .white
                )
            }
            Spacer(minLength: 0)
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func compactBlock(
        label: String,
        color: Color,
        border: Color?,
        foreground: Color = .primary
    ) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(color)
            )
            .overlay {
                if let border {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(border, lineWidth: 1)
                }
            }
    }

    private func timeLabel(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func brandColor(for id: ProviderID) -> Color {
        C5hColors.tintForProvider(id)
    }
}

private struct TodayHeaderBackground: ViewModifier {
    let isToday: Bool

    func body(content: Content) -> some View {
        if isToday {
            content.glassEffect(
                .regular.tint(C5hColors.accentOnGlass.opacity(0.20)),
                in: C5hShape.rect(C5hRadius.s)
            )
        } else {
            content
        }
    }
}
