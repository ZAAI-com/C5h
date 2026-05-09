import SwiftUI
import C5hCore

struct DayCalendarView: View {
    let viewModel: DayCalendarViewModel
    let layout: CalendarLayoutConfig
    let now: Date
    let onSelectPlanned: (PlannedWindow) -> Void
    let onSelectActual: (ActualWindow) -> Void

    var body: some View {
        GeometryReader { proxy in
            let providers = ProviderID.allCases
            let columnWidth = max(
                layout.providerMinWidth,
                (proxy.size.width - layout.timeRulerWidth) / CGFloat(providers.count)
            )
            ScrollViewReader { scroller in
                ScrollView {
                    HStack(alignment: .top, spacing: 0) {
                        TimeRulerView(layout: layout)
                            .id("ruler")
                        ForEach(providers) { providerID in
                            let cw = viewModel.windows(for: providerID)
                            ProviderColumnView(
                                providerID: providerID,
                                plannedWindows: cw.planned,
                                actualWindows: cw.actual,
                                date: viewModel.date,
                                now: now,
                                layout: layout,
                                columnWidth: columnWidth,
                                onSelectPlanned: onSelectPlanned,
                                onSelectActual: onSelectActual
                            )
                            .overlay(alignment: .top) {
                                providerHeader(providerID: providerID)
                            }
                        }
                    }
                }
                .onAppear {
                    let target = CalendarPositioning.yOffset(
                        for: now,
                        pixelsPerMinute: layout.pixelsPerMinute
                    ) - 200
                    scroller.scrollTo("ruler", anchor: UnitPoint(x: 0, y: max(0, target / layout.dayHeight)))
                }
            }
        }
    }

    private func providerHeader(providerID: ProviderID) -> some View {
        Text(providerID.displayName)
            .font(C5hTypography.captionFont)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(C5hColors.chrome)
            )
            .padding(.top, 4)
    }
}
