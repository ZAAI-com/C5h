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
                (proxy.size.width - 2 * layout.timeRulerWidth) / CGFloat(providers.count)
            )
            ZStack(alignment: .topLeading) {
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
                            }
                            TimeRulerView(layout: layout, labelAlignment: .leading)
                        }
                    }
                    .onAppear {
                        // Aim to position "now" ~200pt below the floating toolbar (which adds ~50pt
                        // of top safe-area inset on macOS 26). yOffset is in pixels relative to the
                        // top of the day; we convert to a 0–1 anchor fraction across the ruler.
                        guard layout.dayHeight > 0 else { return }
                        let topInset = proxy.safeAreaInsets.top
                        let target = CalendarPositioning.yOffset(
                            for: now,
                            pixelsPerMinute: layout.pixelsPerMinute
                        ) - 200 - topInset
                        scroller.scrollTo("ruler", anchor: UnitPoint(x: 0, y: max(0, target / layout.dayHeight)))
                    }
                }

                HStack(spacing: 0) {
                    ForEach(providers) { providerID in
                        providerHeader(providerID: providerID)
                            .frame(width: columnWidth)
                    }
                }
                .padding(.leading, layout.timeRulerWidth)
                .padding(.top, 4)
                .allowsHitTesting(false)
            }
        }
    }

    private func providerHeader(providerID: ProviderID) -> some View {
        // LEVEL 1 day calendar — single allowed glass element on this screen,
        // floating identity label that hovers above the column content.
        HStack(spacing: 4) {
            Circle()
                .fill(C5hColors.tintForProvider(providerID))
                .frame(width: 6, height: 6)
            Text(providerID.displayName)
                .font(C5hTypography.captionFont)
        }
        .padding(.horizontal, C5hSpacing.sm)
        .padding(.vertical, 4)
        .glassEffect(C5hGlass.toolbar, in: .capsule)
    }
}
