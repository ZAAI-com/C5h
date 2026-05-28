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
    }

    @ViewBuilder
    private func content(_ viewModel: WeekCalendarViewModel) -> some View {
        WeekCalendarView(
            viewModel: viewModel,
            now: now,
            visibleProviders: visibleProviders,
            showPlanned: showPlanned,
            showActual: showActual
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
    }
}

struct WeekCalendarView: View {
    let viewModel: WeekCalendarViewModel
    let now: Date
    let visibleProviders: Set<ProviderID>
    let showPlanned: Bool
    let showActual: Bool

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
            let columnWidth = max(
                120,
                (proxy.size.width - 2 * dynamicLayout.timeRulerWidth) / CGFloat(viewModel.days.count)
            )

            VStack(spacing: 0) {
                headerRow(columnWidth: columnWidth, layout: dynamicLayout)
                    .frame(height: Self.headerHeight)
                Divider()
                ScrollView([.horizontal, .vertical]) {
                    HStack(alignment: .top, spacing: 0) {
                        TimeRulerView(layout: dynamicLayout)
                        ForEach(viewModel.days, id: \.self) { day in
                            WeekDayColumnView(
                                day: day,
                                planned: filteredPlanned(forDay: day),
                                actual: filteredActual(forDay: day),
                                histories: viewModel.usageHistories,
                                now: now,
                                layout: dynamicLayout,
                                columnWidth: columnWidth,
                                showPlanned: showPlanned,
                                showActual: showActual
                            )
                        }
                        TimeRulerView(layout: dynamicLayout, labelAlignment: .leading)
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
                .frame(width: columnWidth, alignment: .leading)
                .padding(.horizontal, C5hSpacing.sm)
                .padding(.vertical, 6)
                .modifier(TodayHeaderBackground(isToday: Calendar.current.isDateInToday(day)))
            }
            Color.clear.frame(width: layout.timeRulerWidth)
        }
    }
}

private struct WeekDayColumnView: View {
    let day: Date
    let planned: [PlannedWindow]
    let actual: [ActualWindow5h]
    let histories: [ProviderID: UsageHistorySeries]
    let now: Date
    let layout: CalendarLayoutConfig
    let columnWidth: CGFloat
    let showPlanned: Bool
    let showActual: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            ForEach(planned) { window in
                if let segment = visibleSegment(
                    start: window.startAt,
                    durationSeconds: window.durationSeconds
                ) {
                    PlannedWindowBlockView(
                        window: window,
                        now: now,
                        columnWidth: halfColumnWidth,
                        layout: layout,
                        visibleDurationSeconds: segment.durationSeconds,
                        clipsTop: segment.clippedStart,
                        clipsBottom: segment.clippedEnd
                    )
                    .offset(
                        x: providerXOffset(for: window.providerID),
                        y: yOffset(for: segment.start)
                    )
                    .zIndex(1)
                }
            }
            ForEach(actual) { window in
                if let segment = visibleSegment(
                    start: window.startAt,
                    durationSeconds: window.durationSeconds
                ) {
                    ActualWindowBlockView(
                        window: window,
                        history: histories[window.providerID],
                        now: now,
                        columnWidth: halfColumnWidth,
                        layout: layout,
                        visibleDurationSeconds: segment.durationSeconds,
                        clipsTop: segment.clippedStart,
                        clipsBottom: segment.clippedEnd,
                        displayStart: segment.start,
                        displayEnd: segment.start.addingTimeInterval(
                            TimeInterval(segment.durationSeconds)
                        )
                    )
                    .offset(
                        x: actualXOffset(for: window.providerID),
                        y: yOffset(for: segment.start)
                    )
                    .zIndex(2)
                }
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

    private var halfColumnWidth: CGFloat {
        max(0, (columnWidth - 4) / 2)
    }

    /// Claude blocks render in the left half, Codex in the right half — keeps
    /// both providers visible at the same time of day without overlap.
    private func providerXOffset(for providerID: ProviderID) -> CGFloat {
        switch providerID {
        case .claude: return 2
        case .codex: return 2 + halfColumnWidth
        }
    }

    private func actualXOffset(for providerID: ProviderID) -> CGFloat {
        // Right-justify actual blocks within each provider's half, matching
        // the day view's convention where actual blocks sit on the right edge.
        let baseX = providerXOffset(for: providerID)
        let actualWidth = halfColumnWidth * layout.actualBlockWidthRatio
        return baseX + (halfColumnWidth - actualWidth)
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
