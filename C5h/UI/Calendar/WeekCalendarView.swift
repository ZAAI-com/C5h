import SwiftUI
import C5hCore
import C5hStore

struct WeekCalendarScreen: View {
    var reloadToken: Int = 0
    @Environment(AppEnvironment.self) private var appEnv
    @State private var viewModel: WeekCalendarViewModel?
    @State private var now: Date = .now
    @State private var visibleProviders: Set<ProviderID> = Set(ProviderID.allCases)
    @State private var showPlanned: Bool = false
    @State private var showActual: Bool = true

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
                    actual5hRepository: actual5hRepo,
                    usageSnapshotRepository: appEnv.usageSnapshotRepository
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
        .onChange(of: appEnv.databaseChangeMonitor?.changeToken) { _, _ in
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

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation(C5hAnimation.morph) {
                            if viewModel.selection == nil,
                               let firstActual = viewModel.firstVisibleActual(
                                   visibleProviders: visibleProviders,
                                   showActual: showActual
                               ) {
                                viewModel.selection = .actual(firstActual)
                            } else if viewModel.selection == nil,
                                      let firstPlanned = viewModel.firstVisiblePlanned(
                                          visibleProviders: visibleProviders,
                                          showPlanned: showPlanned
                                      ) {
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
}

struct WeekCalendarView: View {
    let viewModel: WeekCalendarViewModel
    let now: Date
    let visibleProviders: Set<ProviderID>
    let showPlanned: Bool
    let showActual: Bool
    let onSelectPlanned: (PlannedWindow) -> Void
    let onSelectActual: (ActualWindow5h) -> Void

    private static let minPixelsPerMinute: CGFloat = 0.3
    private static let gridVerticalPadding: CGFloat = 16
    private static let headerHeight: CGFloat = 44
    /// Narrow gutter so the time scale sits flush to the left, leaving the day
    /// columns as much width as possible.
    private static let timeRulerWidth: CGFloat = 44
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
                l.timeRulerWidth = Self.timeRulerWidth
                return l
            }()
            // Fit all 7 days plus a single (left) ruler into the width, with no
            // horizontal scroll, so the fixed header stays aligned with the grid
            // and the time scale never gets clipped off the right edge.
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
                        TimeRulerView(layout: dynamicLayout, labelAlignment: .leading)
                        ForEach(viewModel.days, id: \.self) { day in
                            WeekDayColumnView(
                                day: day,
                                planned: filteredPlanned(forDay: day),
                                actual: filteredActual(forDay: day),
                                histories: viewModel.usageHistories,
                                resetWindowIDs: resetWindowIDs(forDay: day),
                                now: now,
                                layout: dynamicLayout,
                                columnWidth: columnWidth,
                                showPlanned: showPlanned,
                                showActual: showActual,
                                onSelectPlanned: onSelectPlanned,
                                onSelectActual: onSelectActual
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
                && !$0.status.isTerminal
                && CalendarPositioning.windowOverlaps(
                    start: $0.startAt,
                    durationSeconds: $0.durationSeconds,
                    day: day
                )
        }
    }

    private func filteredActual(forDay day: Date) -> [ActualWindow5hDisplaySegment] {
        guard showActual else { return [] }
        return viewModel.actualDisplaySegments.filter {
            visibleProviders.contains($0.window.providerID)
                && CalendarPositioning.windowOverlaps(
                    start: $0.startAt,
                    durationSeconds: $0.durationSeconds,
                    day: day
                )
        }
    }

    /// Actual windows on `day` that followed a detected quota reset, for the
    /// neutral reset glyph. Matches the inspector's reset lookup.
    private func resetWindowIDs(forDay day: Date) -> Set<UUID> {
        Set(
            filteredActual(forDay: day)
                .filter {
                    viewModel.fiveHourResetEvent(
                        forWindowEndingAt: $0.window.endAt,
                        providerID: $0.window.providerID
                    ) != nil
                }
                .map(\.id)
        )
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
    let actual: [ActualWindow5hDisplaySegment]
    let histories: [ProviderID: UsageHistorySeries]
    let resetWindowIDs: Set<UUID>
    let now: Date
    let layout: CalendarLayoutConfig
    let columnWidth: CGFloat
    let showPlanned: Bool
    let showActual: Bool
    let onSelectPlanned: (PlannedWindow) -> Void
    let onSelectActual: (ActualWindow5h) -> Void

    private enum StackID: Hashable {
        case planned(UUID)
        case actual(UUID)
    }

    private struct StackBlock {
        let id: StackID
        let yOffset: CGFloat
        let height: CGFloat
        let sortPriority: Int
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            let stackedYOffsets = stackedBlockYOffsets
            ForEach(activePlanned) { window in
                if let segment = visibleSegment(
                    start: window.startAt,
                    durationSeconds: window.durationSeconds
                ) {
                    let renderedTop = stackedYOffsets[.planned(window.id)] ?? yOffset(for: segment.start)
                    Button {
                        onSelectPlanned(window)
                    } label: {
                        PlannedWindowBlockView(
                            window: window,
                            now: now,
                            columnWidth: providerContentWidth,
                            layout: layout,
                            visibleDurationSeconds: segment.durationSeconds,
                            clipsTop: segment.clippedStart,
                            clipsBottom: segment.clippedEnd,
                            segmentStart: segment.start,
                            widthOverride: providerContentWidth,
                            renderedTopOffset: renderedTop
                        )
                    }
                    .buttonStyle(.plain)
                    .offset(
                        x: providerXOffset(for: window.providerID),
                        y: renderedTop
                    )
                    .zIndex(1)
                }
            }
            ForEach(actual) { actualSegment in
                let window = actualSegment.window
                if let segment = visibleSegment(
                    start: actualSegment.startAt,
                    durationSeconds: actualSegment.durationSeconds
                ) {
                    let renderedTop = stackedYOffsets[.actual(actualSegment.id)] ?? yOffset(for: segment.start)
                    Button {
                        onSelectActual(window)
                    } label: {
                        ActualWindowBlockView(
                            window: window,
                            history: histories[window.providerID],
                            now: now,
                            columnWidth: halfColumnWidth,
                            layout: layout,
                            visibleDurationSeconds: segment.durationSeconds,
                            clipsTop: segment.clippedStart,
                            clipsBottom: segment.clippedEnd,
                            segmentStart: segment.start,
                            displayStart: actualSegment.startAt,
                            displayEnd: actualSegment.endAt,
                            marksResetEnd: actualSegment.marksResetEnd,
                            condensed: true,
                            widthOverride: providerContentWidth,
                            isReset: resetWindowIDs.contains(actualSegment.id),
                            renderedTopOffset: renderedTop
                        )
                    }
                    .buttonStyle(.plain)
                    .offset(
                        x: providerXOffset(for: window.providerID),
                        y: renderedTop
                    )
                    .zIndex(2)
                }
            }
            if Calendar.current.isDateInToday(day) {
                // Below the window blocks (zIndex 1/2) so it passes behind their
                // text; each block carries the line on through its own background.
                Rectangle()
                    .fill(Color.red)
                    .frame(width: columnWidth, height: 1)
                    .offset(y: yOffset(for: now))
                    .allowsHitTesting(false)
                    .zIndex(0)
            }
        }
        .frame(width: columnWidth, height: layout.dayHeight, alignment: .topLeading)
        .clipped()
    }

    private var halfColumnWidth: CGFloat {
        max(0, (columnWidth - 4) / 2)
    }

    private var providerContentWidth: CGFloat {
        max(0, halfColumnWidth - 4)
    }

    private var activePlanned: [PlannedWindow] {
        planned.filter { !$0.status.isTerminal }
    }

    private var stackedBlockYOffsets: [StackID: CGFloat] {
        var map: [StackID: CGFloat] = [:]
        for provider in ProviderID.allCases {
            var blocks: [StackBlock] = []
            for window in activePlanned where window.providerID == provider {
                guard let segment = visibleSegment(
                    start: window.startAt,
                    durationSeconds: window.durationSeconds
                ) else { continue }
                blocks.append(StackBlock(
                    id: .planned(window.id),
                    yOffset: yOffset(for: segment.start),
                    height: stackingHeight(durationSeconds: segment.durationSeconds),
                    sortPriority: 0
                ))
            }
            for actualSegment in actual where actualSegment.window.providerID == provider {
                guard let segment = visibleSegment(
                    start: actualSegment.startAt,
                    durationSeconds: actualSegment.durationSeconds
                ) else { continue }
                blocks.append(StackBlock(
                    id: .actual(actualSegment.id),
                    yOffset: yOffset(for: segment.start),
                    height: stackingHeight(durationSeconds: segment.durationSeconds),
                    sortPriority: 1
                ))
            }
            let sorted = blocks.sorted {
                if $0.yOffset != $1.yOffset { return $0.yOffset < $1.yOffset }
                return $0.sortPriority < $1.sortPriority
            }
            let placements = CalendarPositioning.stackVertically(
                sorted.map { .init(yOffset: $0.yOffset, height: $0.height) },
                gap: layout.blockVerticalGap,
                maxY: layout.dayHeight
            )
            for (block, placement) in zip(sorted, placements) {
                map[block.id] = placement.yOffset
            }
        }
        return map
    }

    /// Space a block occupies for stacking purposes: its true duration on the
    /// time scale, without the minimum height the rendered frame applies, so a
    /// short block cannot claim more of the timeline than it covers and displace
    /// every later block. See `ProviderColumnView.stackingHeight`.
    private func stackingHeight(durationSeconds: Int) -> CGFloat {
        CalendarPositioning.blockHeight(
            durationSeconds: durationSeconds,
            pixelsPerMinute: layout.pixelsPerMinute,
            minimum: 0
        )
    }

    /// Claude blocks render in the left half, Codex in the right half. This keeps
    /// both providers visible at the same time of day without overlap.
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
