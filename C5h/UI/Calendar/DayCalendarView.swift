import SwiftUI
import C5hCore

struct DayCalendarView: View {
    let viewModel: DayCalendarViewModel
    let layout: CalendarLayoutConfig
    let now: Date
    let onSelectPlanned: (PlannedWindow) -> Void
    let onSelectActual: (ActualWindow) -> Void

    private static let minPixelsPerMinute: CGFloat = 0.3

    var body: some View {
        GeometryReader { proxy in
            let providers = ProviderID.allCases
            let usableHeight = max(
                0,
                proxy.size.height - proxy.safeAreaInsets.top - proxy.safeAreaInsets.bottom
            )
            let fitPpm = usableHeight / (24 * 60)
            let dynamicLayout: CalendarLayoutConfig = {
                var l = layout
                l.pixelsPerMinute = max(Self.minPixelsPerMinute, fitPpm)
                return l
            }()
            let columnWidth = max(
                dynamicLayout.providerMinWidth,
                (proxy.size.width - 2 * dynamicLayout.timeRulerWidth) / CGFloat(providers.count)
            )
            let overflowsViewport = dynamicLayout.dayHeight > usableHeight
            ZStack(alignment: .topLeading) {
                ScrollViewReader { scroller in
                    ScrollView {
                        HStack(alignment: .top, spacing: 0) {
                            TimeRulerView(layout: dynamicLayout)
                                .id("ruler")
                            ForEach(providers) { providerID in
                                let cw = viewModel.windows(for: providerID)
                                ProviderColumnView(
                                    providerID: providerID,
                                    plannedWindows: cw.planned,
                                    actualWindows: cw.actual,
                                    date: viewModel.date,
                                    now: now,
                                    layout: dynamicLayout,
                                    columnWidth: columnWidth,
                                    onSelectPlanned: onSelectPlanned,
                                    onSelectActual: onSelectActual
                                )
                            }
                            TimeRulerView(layout: dynamicLayout, labelAlignment: .leading)
                        }
                    }
                    .onAppear {
                        // Only auto-scroll to "now" when the day actually overflows the viewport;
                        // when the whole day fits, start at midnight.
                        guard overflowsViewport, dynamicLayout.dayHeight > 0 else { return }
                        let topInset = proxy.safeAreaInsets.top
                        let target = CalendarPositioning.yOffset(
                            for: now,
                            pixelsPerMinute: dynamicLayout.pixelsPerMinute
                        ) - 200 - topInset
                        scroller.scrollTo("ruler", anchor: UnitPoint(x: 0, y: max(0, target / dynamicLayout.dayHeight)))
                    }
                }

                HStack(spacing: 0) {
                    ForEach(providers) { providerID in
                        providerHeader(providerID: providerID)
                            .frame(width: columnWidth)
                    }
                }
                .padding(.leading, dynamicLayout.timeRulerWidth)
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
