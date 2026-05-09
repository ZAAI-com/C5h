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
            }
        }
        .task(id: ObjectIdentifier(appEnv)) {
            if viewModel == nil,
               let plannedRepo = appEnv.plannedWindowRepository,
               let actualRepo = appEnv.actualWindowRepository {
                let vm = WeekCalendarViewModel(
                    weekStart: .now,
                    plannedRepository: plannedRepo,
                    actualRepository: actualRepo
                )
                viewModel = vm
                await vm.reload()
            }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: WeekCalendarViewModel) -> some View {
        VStack(spacing: 0) {
            toolbar(viewModel: viewModel)
            Divider()
            WeekCalendarView(viewModel: viewModel)
        }
    }

    private func toolbar(viewModel: WeekCalendarViewModel) -> some View {
        HStack(spacing: C5hSpacing.md) {
            Button {
                viewModel.goToPreviousWeek()
                Task { await viewModel.reload() }
            } label: {
                Image(systemName: "chevron.left")
            }
            Text("Week of \(viewModel.weekStart.formatted(date: .abbreviated, time: .omitted))")
                .font(C5hTypography.titleFont)
            Button {
                viewModel.goToNextWeek()
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
                .background(
                    Calendar.current.isDateInToday(day)
                    ? C5hColors.accentMuted
                    : Color.clear
                )
            }
        }
    }

    private func row(for provider: ProviderID) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(brandColor(for: provider)).frame(width: 8, height: 8)
                Text(provider.displayName).font(C5hTypography.captionFont)
            }
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
                    color: brandColor(for: provider).opacity(0.18),
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
        id == .claude ? ProviderBrandColor.claude : ProviderBrandColor.codex
    }
}
