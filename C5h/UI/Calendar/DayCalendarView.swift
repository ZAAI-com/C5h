import SwiftUI
import C5hCore

struct DayCalendarView: View {
    let viewModel: DayCalendarViewModel
    let layout: CalendarLayoutConfig
    let now: Date
    let onSelectPlanned: (PlannedWindow) -> Void
    let onSelectActual: (ActualWindow5h) -> Void
    let onMovePlanned: (PlannedWindow, Date) -> Void

    private static let minPixelsPerMinute: CGFloat = 0.3
    private static let gridVerticalPadding: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            let providers = ProviderID.allCases
            let usableHeight = max(
                0,
                proxy.size.height - proxy.safeAreaInsets.top
            )
            let availableForGrid = max(0, usableHeight - 2 * Self.gridVerticalPadding)
            let fitPpm = availableForGrid / (24 * 60)
            let dynamicLayout: CalendarLayoutConfig = {
                var l = layout
                l.pixelsPerMinute = max(Self.minPixelsPerMinute, fitPpm)
                return l
            }()
            let columnWidth = max(
                dynamicLayout.providerMinWidth,
                (proxy.size.width - 2 * dynamicLayout.timeRulerWidth) / CGFloat(providers.count)
            )
            let overflowsViewport = dynamicLayout.dayHeight + 2 * Self.gridVerticalPadding > usableHeight
            ZStack(alignment: .topLeading) {
                ScrollViewReader { scroller in
                    ScrollView {
                        ZStack(alignment: .topLeading) {
                            HStack(alignment: .top, spacing: 0) {
                                TimeRulerView(
                                    layout: dynamicLayout,
                                    now: Calendar.current.isDate(viewModel.date, inSameDayAs: now) ? now : nil
                                )
                                .id("ruler")
                                ForEach(providers) { providerID in
                                    let cw = viewModel.windows(for: providerID)
                                    ProviderColumnView(
                                        providerID: providerID,
                                        plannedWindows: cw.planned,
                                        actualWindows: cw.actual,
                                        history: viewModel.history(for: providerID),
                                        resetWindowIDs: resetWindowIDs(for: cw.actual, providerID: providerID),
                                        date: viewModel.date,
                                        now: now,
                                        layout: dynamicLayout,
                                        columnWidth: columnWidth,
                                        onSelectPlanned: onSelectPlanned,
                                        onSelectActual: onSelectActual,
                                        onMovePlanned: onMovePlanned,
                                        onQuickPlan: { start in
                                            Task { await viewModel.quickPlan(provider: providerID, startAt: start) }
                                        }
                                    )
                                }
                                TimeRulerView(
                                    layout: dynamicLayout,
                                    labelAlignment: .leading,
                                    now: Calendar.current.isDate(viewModel.date, inSameDayAs: now) ? now : nil
                                )
                            }
                            if Calendar.current.isDate(viewModel.date, inSameDayAs: now) {
                                nowLine(layout: dynamicLayout)
                                    .offset(y: CalendarPositioning.yOffset(
                                        for: now,
                                        pixelsPerMinute: dynamicLayout.pixelsPerMinute
                                    ))
                                    .allowsHitTesting(false)
                            }
                        }
                        .padding(.vertical, Self.gridVerticalPadding)
                        .background(.background)
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
        .ignoresSafeArea(.container, edges: .bottom)
        .background(.background, ignoresSafeAreaEdges: .all)
    }

    /// Actual windows that followed a detected quota reset, for the neutral
    /// reset glyph. Uses the same matching as the inspector so both stay in sync.
    private func resetWindowIDs(for windows: [ActualWindow5h], providerID: ProviderID) -> Set<UUID> {
        Set(
            windows
                .filter { viewModel.fiveHourResetEvent(forWindowEndingAt: $0.endAt, providerID: providerID) != nil }
                .map(\.id)
        )
    }

    @ViewBuilder
    private func nowLine(layout: CalendarLayoutConfig) -> some View {
        Rectangle()
            .fill(Color.red)
            .frame(height: 1)
            .padding(.leading, layout.timeRulerWidth)
            .padding(.trailing, layout.timeRulerWidth)
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
