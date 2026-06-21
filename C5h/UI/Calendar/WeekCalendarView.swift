import SwiftUI
import C5hCore
import C5hStore

struct WeekCalendarScreen: View {
    var reloadToken: Int = 0
    @Environment(AppEnvironment.self) private var appEnv
    @State private var viewModel: WeekCalendarViewModel?
    @State private var now: Date = .now
    @State private var visibleProviders: Set<ProviderID> = Set(ProviderID.allCases)
    @State private var showPlanned: Bool = true
    @State private var showActual: Bool = true
    @State private var selection: CalendarSelection?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                ProgressView("Loading week…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Text("Week")
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
    }

    @ViewBuilder
    private func content(_ viewModel: WeekCalendarViewModel) -> some View {
        WeekCalendarView(
            viewModel: viewModel,
            now: now,
            visibleProviders: visibleProviders,
            showPlanned: showPlanned,
            showActual: showActual,
            onSelect: { sel in
                withAnimation(C5hAnimation.morph) { selection = sel }
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
                    Menu {
                        ForEach(ProviderID.allCases) { provider in
                            Toggle(provider.displayName, isOn: Binding(
                                get: { visibleProviders.contains(provider) },
                                set: { isOn in
                                    if isOn { visibleProviders.insert(provider) }
                                    else { visibleProviders.remove(provider) }
                                }
                            ))
                        }
                    } label: {
                        Label("Providers", systemImage: "person.2")
                    }
                    .help("Show/hide providers")
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Toggle("Planned windows", isOn: $showPlanned)
                        Toggle("Actual windows", isOn: $showActual)
                    } label: {
                        Label("Windows", systemImage: "rectangle.on.rectangle")
                    }
                    .help("Show/hide window types")
                }
            }
            // Non-blocking right-side glass pane carrying the window detail that
            // no longer fits inside the slim week bars.
            .inspector(isPresented: Binding(
                get: { selection != nil },
                set: { newValue in
                    if !newValue {
                        withAnimation(C5hAnimation.morph) { selection = nil }
                    }
                }
            )) {
                if let sel = selection {
                    WindowInspectorView(selection: sel)
                        .inspectorColumnWidth(min: 280, ideal: 360, max: 480)
                } else {
                    EmptyView()
                }
            }
    }
}

struct WeekCalendarView: View {
    let viewModel: WeekCalendarViewModel
    let now: Date
    let visibleProviders: Set<ProviderID>
    let showPlanned: Bool
    let showActual: Bool
    let onSelect: (CalendarSelection) -> Void

    private static let minPixelsPerMinute: CGFloat = 0.3
    private static let gridVerticalPadding: CGFloat = 16
    private static let headerHeight: CGFloat = 44
    private let baseLayout = CalendarLayoutConfig()

    var body: some View {
        GeometryReader { proxy in
            let usableHeight = max(
                0,
                proxy.size.height - proxy.safeAreaInsets.top - Self.headerHeight
            )
            let availableForGrid = max(0, usableHeight - 2 * Self.gridVerticalPadding)
            let fitPpm = availableForGrid / (24 * 60)
            let dynamicLayout: CalendarLayoutConfig = {
                var l = baseLayout
                l.pixelsPerMinute = max(Self.minPixelsPerMinute, fitPpm)
                return l
            }()
            // Fit all 7 days plus a single (left) ruler into the width — no
            // horizontal scroll, so the fixed header stays aligned with the grid.
            let columnWidth = max(
                1,
                (proxy.size.width - dynamicLayout.timeRulerWidth) / CGFloat(viewModel.days.count)
            )

            VStack(spacing: 0) {
                headerRow(columnWidth: columnWidth, layout: dynamicLayout)
                    .frame(height: Self.headerHeight)
                Divider()
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        TimeRulerView(layout: dynamicLayout)
                        ForEach(viewModel.days, id: \.self) { day in
                            WeekDayColumnView(
                                day: day,
                                planned: filteredPlanned(forDay: day),
                                actual: filteredActual(forDay: day),
                                now: now,
                                layout: dynamicLayout,
                                columnWidth: columnWidth,
                                onSelect: onSelect
                            )
                        }
                    }
                    .padding(.vertical, Self.gridVerticalPadding)
                    .background(.background)
                }
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .background(.background, ignoresSafeAreaEdges: .all)
    }

    private func filteredPlanned(forDay day: Date) -> [PlannedWindow] {
        guard showPlanned else { return [] }
        return viewModel.planned.filter {
            visibleProviders.contains($0.providerID)
                && CalendarPositioning.windowOverlaps(
                    start: $0.startAt,
                    durationSeconds: $0.durationSeconds,
                    day: day
                )
        }
    }

    private func filteredActual(forDay day: Date) -> [ActualWindow5h] {
        guard showActual else { return [] }
        return viewModel.actual.filter {
            visibleProviders.contains($0.providerID)
                && CalendarPositioning.windowOverlaps(
                    start: $0.startAt,
                    durationSeconds: $0.durationSeconds,
                    day: day
                )
        }
    }

    private func headerRow(columnWidth: CGFloat, layout: CalendarLayoutConfig) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: layout.timeRulerWidth)
            ForEach(viewModel.days, id: \.self) { day in
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.formatted(.dateTime.weekday(.abbreviated)))
                        .font(C5hTypography.captionFont)
                        .foregroundStyle(C5hColors.fgSecondary)
                    Text(day.formatted(.dateTime.day()))
                        .font(C5hTypography.bodyFont)
                }
                .padding(.horizontal, C5hSpacing.sm)
                .padding(.vertical, 6)
                .frame(width: columnWidth, alignment: .leading)
                .modifier(TodayHeaderBackground(isToday: Calendar.current.isDateInToday(day)))
            }
        }
    }
}

private struct WeekDayColumnView: View {
    let day: Date
    let planned: [PlannedWindow]
    let actual: [ActualWindow5h]
    let now: Date
    let layout: CalendarLayoutConfig
    let columnWidth: CGFloat
    let onSelect: (CalendarSelection) -> Void

    /// Gap between lanes packed within a single provider half.
    private static let laneGap: CGFloat = 1

    /// Minimum rendered bar height. Bars are packed against this footprint so
    /// short windows that don't temporally overlap still get distinct lanes
    /// rather than visually colliding at the height floor.
    private static let minimumBarHeight: CGFloat = 24

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            ForEach(laidOutBars) { bar in
                Button {
                    onSelect(bar.selection)
                } label: {
                    WeekWindowBarView(
                        providerID: bar.providerID,
                        kind: bar.kind,
                        startLabel: bar.startLabel,
                        width: bar.width,
                        height: bar.height,
                        clipsTop: bar.clipsTop,
                        clipsBottom: bar.clipsBottom,
                        cornerRadius: layout.blockCornerRadius
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "\(bar.kind == .actual ? "Actual" : "Planned") \(bar.providerID.displayName) window starting \(bar.startLabel)"
                )
                .accessibilityHint("Opens window details")
                .offset(x: bar.x, y: bar.y)
                .zIndex(bar.kind == .actual ? 2 : 1)
            }
            if Calendar.current.isDateInToday(day) {
                Rectangle()
                    .fill(Color.red)
                    .frame(width: columnWidth, height: 1)
                    .offset(y: yOffset(for: now))
                    .allowsHitTesting(false)
                    .zIndex(3)
            }
        }
        .frame(width: columnWidth, height: layout.dayHeight, alignment: .topLeading)
        .clipped()
    }

    // MARK: - Layout

    private struct LaidOutBar: Identifiable {
        let id: String
        let kind: WeekWindowBarView.Kind
        let providerID: ProviderID
        let startLabel: String
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
        let clipsTop: Bool
        let clipsBottom: Bool
        let selection: CalendarSelection
    }

    private struct PackItem {
        let kind: WeekWindowBarView.Kind
        let selection: CalendarSelection
        let segment: (start: Date, durationSeconds: Int, clippedStart: Bool, clippedEnd: Bool)
    }

    /// All bars for the day, lane-packed independently within each provider's
    /// half so overlapping windows sit side-by-side instead of stacking, and
    /// never bleed past their half.
    private var laidOutBars: [LaidOutBar] {
        var bars: [LaidOutBar] = []
        for providerID in ProviderID.allCases {
            let providerItems = items(for: providerID)
            guard !providerItems.isEmpty else { continue }
            // Pack against the rendered footprint, not the raw duration: bars are
            // clamped to `minimumBarHeight`, so inflate each interval to that
            // minimum so near-adjacent short windows land in separate lanes.
            let minimumVisualSeconds = layout.pixelsPerMinute > 0
                ? Int(ceil((Self.minimumBarHeight / layout.pixelsPerMinute) * 60))
                : 0
            let intervals = providerItems.map {
                DateInterval(
                    start: $0.segment.start,
                    duration: TimeInterval(max($0.segment.durationSeconds, minimumVisualSeconds))
                )
            }
            let placements = CalendarPositioning.packLanes(intervals)
            let baseX = providerXOffset(for: providerID)
            for (item, placement) in zip(providerItems, placements) {
                let laneWidth = halfColumnWidth / CGFloat(max(placement.laneCount, 1))
                // Shrink the gap rather than overflow the slot when lanes are thin.
                let effectiveLaneGap = min(Self.laneGap, max(laneWidth - 2, 0))
                bars.append(LaidOutBar(
                    id: item.selection.id,
                    kind: item.kind,
                    providerID: providerID,
                    startLabel: BlockFormatters.formatTime(item.segment.start),
                    x: baseX + CGFloat(placement.lane) * laneWidth,
                    y: yOffset(for: item.segment.start),
                    width: max(laneWidth - effectiveLaneGap, 0),
                    height: CalendarPositioning.blockHeight(
                        durationSeconds: item.segment.durationSeconds,
                        pixelsPerMinute: layout.pixelsPerMinute,
                        minimum: Self.minimumBarHeight
                    ),
                    clipsTop: item.segment.clippedStart,
                    clipsBottom: item.segment.clippedEnd,
                    selection: item.selection
                ))
            }
        }
        return bars
    }

    private func items(for providerID: ProviderID) -> [PackItem] {
        var result: [PackItem] = []
        for window in planned where window.providerID == providerID {
            if let segment = visibleSegment(start: window.startAt, durationSeconds: window.durationSeconds) {
                result.append(PackItem(kind: .planned, selection: .planned(window), segment: segment))
            }
        }
        for window in actual where window.providerID == providerID {
            if let segment = visibleSegment(start: window.startAt, durationSeconds: window.durationSeconds) {
                result.append(PackItem(kind: .actual, selection: .actual(window), segment: segment))
            }
        }
        return result
    }

    private var halfColumnWidth: CGFloat {
        max(0, (columnWidth - 4) / 2)
    }

    /// Claude bars render in the left half, Codex in the right half — keeps both
    /// providers visible at the same time of day without overlap.
    private func providerXOffset(for providerID: ProviderID) -> CGFloat {
        switch providerID {
        case .claude: return 2
        case .codex: return 2 + halfColumnWidth
        }
    }

    private var background: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.background)
            ForEach(0..<25, id: \.self) { hour in
                Rectangle()
                    .fill(C5hColors.fgTertiary.opacity(layout.hourLineOpacity))
                    .frame(height: 1)
                    .offset(y: min(
                        layout.dayHeight - 1,
                        CGFloat(hour) * 60 * layout.pixelsPerMinute
                    ))
            }
        }
    }

    private func yOffset(for date: Date) -> CGFloat {
        CalendarPositioning.yOffset(for: date, pixelsPerMinute: layout.pixelsPerMinute)
    }

    private func visibleSegment(
        start: Date,
        durationSeconds: Int
    ) -> (start: Date, durationSeconds: Int, clippedStart: Bool, clippedEnd: Bool)? {
        let end = start.addingTimeInterval(TimeInterval(durationSeconds))
        return CalendarPositioning.visibleSegment(
            of: DateInterval(start: start, end: end),
            on: day
        )
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
