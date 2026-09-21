import SwiftUI
import C5hCore

struct ProviderColumnView: View {
    let providerID: ProviderID
    let plannedWindows: [PlannedWindow]
    let actualSegments: [ActualWindow5hDisplaySegment]
    var weeklyWindow: ActualWindow7d? = nil
    let history: UsageHistorySeries?
    /// IDs of actual windows that followed a detected quota reset, marked with a
    /// subtle neutral glyph on their block.
    var resetWindowIDs: Set<UUID> = []
    let date: Date
    let now: Date
    let layout: CalendarLayoutConfig
    let columnWidth: CGFloat
    let onSelectPlanned: (PlannedWindow) -> Void
    let onSelectActual: (ActualWindow5h) -> Void
    var onSelectWeekly: ((ActualWindow7d) -> Void)? = nil
    let onMovePlanned: (PlannedWindow, Date) -> Void
    var onQuickPlan: ((Date) -> Void)? = nil

    @State private var hoverY: CGFloat?
    @State private var hoveredPlannedID: UUID?
    @State private var draggingPlannedID: UUID?
    @State private var dragPreviewStart: Date?
    /// Last position the dragged window was allowed to occupy. The block sticks
    /// here while the pointer is over a disallowed stretch, and this is what a
    /// drop commits, so an invalid move is never sent to the repository.
    @State private var lastValidDragStart: Date?

    private static let fiveHourSeconds = ClaudeUsageStatus.fiveHourDurationSeconds
    private enum BlockID: Hashable {
        case planned(UUID)
        case actual(UUID)
    }

    private struct LaneBlock {
        let id: BlockID
        let interval: DateInterval
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            weeklyBlock
            ghostPlanBlock
            // Continuous current-time line for the empty timeline; it sits above
            // the column background but below the window blocks (zIndex 1/2), so
            // each block carries it on through behind its own text.
            if Calendar.current.isDate(date, inSameDayAs: now) {
                Rectangle()
                    .fill(Color.red)
                    .frame(height: 1)
                    .offset(y: yOffset(for: now))
                    .allowsHitTesting(false)
            }
            let frames = blockFrames
            ForEach(activePlannedWindows) { window in
                let isActive = hoveredPlannedID == window.id || draggingPlannedID == window.id
                let displayStart = displayedStart(for: window)
                if let segment = visibleSegment(start: displayStart, durationSeconds: window.durationSeconds) {
                    let frame = frames[.planned(window.id)] ?? .zero
                    PlannedWindowBlockView(
                        window: window,
                        now: now,
                        columnWidth: columnWidth,
                        layout: layout,
                        visibleDurationSeconds: segment.durationSeconds,
                        clipsTop: segment.clippedStart,
                        clipsBottom: segment.clippedEnd,
                        segmentStart: segment.start,
                        displayStart: draggingPlannedID == window.id ? displayStart : nil,
                        emphasizeEndTime: true,
                        widthOverride: frame.width,
                        renderedTopOffset: frame.minY
                    )
                    .overlay(alignment: .topTrailing) {
                        if isActive {
                            Image(systemName: "arrow.up.and.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(C5hColors.tintForProvider(providerID))
                                .padding(5)
                                .allowsHitTesting(false)
                        }
                    }
                    .offset(
                        x: blockContentX + frame.minX,
                        y: frame.minY
                    )
                    .opacity(draggingPlannedID == window.id ? 0.85 : 1)
                    // A dragged block lifts above its planned peers but stays below
                    // the actual layer (zIndex 2): actual windows always win.
                    .zIndex(draggingPlannedID == window.id ? 1.5 : 1)
                    .onHover { hovering in
                        if hovering {
                            hoveredPlannedID = window.id
                        } else if hoveredPlannedID == window.id {
                            hoveredPlannedID = nil
                        }
                    }
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 4, coordinateSpace: .named("provider-calendar-column"))
                            .onChanged { value in
                                if draggingPlannedID != window.id {
                                    draggingPlannedID = window.id
                                    // Seed with the window's own start so a block
                                    // that already sits in a disallowed spot keeps
                                    // its place as the fallback and can still be
                                    // dragged out to a legal slot.
                                    lastValidDragStart = window.startAt
                                }
                                hoverY = nil
                                let candidate = draggedStart(
                                    for: window,
                                    translationY: value.translation.height
                                )
                                if let resolved = nearestAllowedStart(for: window, near: candidate) {
                                    lastValidDragStart = resolved
                                }
                                dragPreviewStart = lastValidDragStart
                            }
                            .onEnded { value in
                                let candidate = draggedStart(
                                    for: window,
                                    translationY: value.translation.height
                                )
                                if let resolved = nearestAllowedStart(for: window, near: candidate) {
                                    lastValidDragStart = resolved
                                }
                                let start = lastValidDragStart ?? window.startAt
                                // Hand the drop to the model before clearing
                                // the preview: it applies the new start
                                // synchronously, so the block never falls back
                                // to its old position while the save runs.
                                if start != window.startAt {
                                    onMovePlanned(window, start)
                                }
                                draggingPlannedID = nil
                                dragPreviewStart = nil
                                lastValidDragStart = nil
                            }
                    )
                }
            }
            ForEach(actualSegments) { actualSegment in
                let window = actualSegment.window
                if let segment = visibleSegment(start: actualSegment.startAt, durationSeconds: actualSegment.durationSeconds) {
                    let frame = frames[.actual(actualSegment.id)] ?? .zero
                    ActualWindowBlockView(
                        window: window,
                        history: history,
                        now: now,
                        columnWidth: columnWidth,
                        layout: layout,
                        visibleDurationSeconds: segment.durationSeconds,
                        clipsTop: segment.clippedStart,
                        clipsBottom: segment.clippedEnd,
                        segmentStart: segment.start,
                        displayStart: actualSegment.startAt,
                        displayEnd: actualSegment.endAt,
                        marksResetEnd: actualSegment.marksResetEnd,
                        widthOverride: frame.width,
                        isReset: resetWindowIDs.contains(actualSegment.id),
                        renderedTopOffset: frame.minY
                    )
                    .offset(
                        x: blockContentX + frame.minX,
                        y: frame.minY
                    )
                    .zIndex(2)
                }
            }
        }
        .frame(width: columnWidth, height: layout.dayHeight, alignment: .topLeading)
        .clipped()
        .contentShape(Rectangle())
        .coordinateSpace(name: "provider-calendar-column")
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                // Over an existing window the pointer only selects it, so do not
                // present a plan ghost there.
                if windowSelection(at: location) != nil {
                    hoverY = nil
                } else {
                    hoverY = resolvedPlanStart(forY: location.y) != nil ? location.y : nil
                }
            case .ended:
                hoverY = nil
            }
        }
        .onTapGesture { location in
            if let hit = windowSelection(at: location) {
                switch hit {
                case .planned(let window): onSelectPlanned(window)
                case .actual(let window): onSelectActual(window)
                case .weekly(let window): onSelectWeekly?(window)
                }
                hoverY = nil
                return
            }
            guard let start = resolvedPlanStart(forY: location.y) else { return }
            onQuickPlan?(start)
            hoverY = nil
        }
    }

    private enum WindowHit {
        case planned(PlannedWindow)
        case actual(ActualWindow5h)
        case weekly(ActualWindow7d)
    }

    /// Resolves a tap location to the window block whose rendered frame (its
    /// horizontal extent and vertical span) contains the pointer, so taps open a
    /// block's details instead of quick-planning. The white area beside a block,
    /// even at the block's time, is not "inside" the window. Actual blocks are
    /// checked first because they are drawn on top of the planned lane, so they
    /// win when a point falls in the lane overlap of both.
    private func windowSelection(at location: CGPoint) -> WindowHit? {
        let frames = blockFrames
        for actualSegment in actualSegments {
            if let frame = frames[.actual(actualSegment.id)],
               frame.offsetBy(dx: blockContentX, dy: 0).contains(location) {
                return .actual(actualSegment.window)
            }
        }
        for window in activePlannedWindows {
            if let frame = frames[.planned(window.id)],
               frame.offsetBy(dx: blockContentX, dy: 0).contains(location) {
                return .planned(window)
            }
        }
        // The weekly block is drawn beneath the planned/actual lanes (zIndex 0),
        // so it is matched last: a 5h block on top wins any overlap. Without this
        // the weekly block reads as empty calendar space (a plan ghost is drawn
        // over it and a tap quick-plans instead of selecting it).
        if let weeklyWindow,
           blockContentX <= location.x, location.x <= blockContentX + blockContentWidth,
           let segment = visibleSegment(
               start: weeklyWindow.startAt,
               durationSeconds: weeklyWindow.durationSeconds
           ) {
            let top = yOffset(for: segment.start)
            let height = CalendarPositioning.blockHeight(
                durationSeconds: segment.durationSeconds,
                pixelsPerMinute: layout.pixelsPerMinute
            )
            if (top...(top + height)).contains(location.y) {
                return .weekly(weeklyWindow)
            }
        }
        return nil
    }

    private var activePlannedWindows: [PlannedWindow] {
        plannedWindows.filter { !$0.status.isTerminal }
    }

    private var blockContentX: CGFloat { 2 }

    private var blockContentWidth: CGFloat {
        max(0, columnWidth - 4)
    }

    /// Frames for the column's blocks, lane-packed in two independent passes:
    /// actual windows among themselves, planned windows among themselves. A
    /// planned window therefore never narrows an actual one: a lone actual
    /// block always spans the full column and (drawn on top) simply covers any
    /// planned block behind it. Genuinely concurrent blocks of the same kind
    /// still split into lanes so both stay visible and hit-testable.
    private var blockFrames: [BlockID: CGRect] {
        var map: [BlockID: CGRect] = [:]

        var plannedBlocks: [LaneBlock] = []
        for window in activePlannedWindows {
            guard let segment = visibleSegment(
                start: displayedStart(for: window),
                durationSeconds: window.durationSeconds
            ) else { continue }
            plannedBlocks.append(LaneBlock(
                id: .planned(window.id),
                interval: DateInterval(start: segment.start, duration: TimeInterval(segment.durationSeconds))
            ))
        }

        var actualBlocks: [LaneBlock] = []
        for actualSegment in actualSegments {
            guard let segment = visibleSegment(
                start: actualSegment.startAt,
                durationSeconds: actualSegment.durationSeconds
            ) else { continue }
            actualBlocks.append(LaneBlock(
                id: .actual(actualSegment.id),
                interval: DateInterval(start: segment.start, duration: TimeInterval(segment.durationSeconds))
            ))
        }

        for blocks in [plannedBlocks, actualBlocks] {
            let frames = CalendarPositioning.laneFrames(
                for: blocks.map(\.interval),
                pixelsPerMinute: layout.pixelsPerMinute,
                columnWidth: blockContentWidth
            )
            for (block, frame) in zip(blocks, frames) {
                map[block.id] = frame
            }
        }
        return map
    }

    @ViewBuilder
    private var ghostPlanBlock: some View {
        if hoveredPlannedID == nil,
           draggingPlannedID == nil,
           let hoverY,
           let start = resolvedPlanStart(forY: hoverY) {
            let height = CalendarPositioning.blockHeight(
                durationSeconds: Self.fiveHourSeconds,
                pixelsPerMinute: layout.pixelsPerMinute
            )
            let end = start.addingTimeInterval(TimeInterval(Self.fiveHourSeconds))
            ZStack {
                VStack(spacing: 0) {
                    ghostCornerText(BlockFormatters.formatTime(start), weight: .semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 0)
                    ghostCornerText(BlockFormatters.formatTime(end), weight: .semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("Plan \(providerID.displayName) 5h Window")
                    .font(.system(size: 11, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .padding(6)
            .frame(width: columnWidth - 4, height: height, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: layout.blockCornerRadius, style: .continuous)
                    .fill(C5hColors.tintForProvider(providerID).opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: layout.blockCornerRadius, style: .continuous)
                    .strokeBorder(
                        C5hColors.tintForProvider(providerID),
                        style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                    )
            )
            .offset(x: 2, y: CalendarPositioning.yOffset(
                for: start,
                pixelsPerMinute: layout.pixelsPerMinute
            ))
            .allowsHitTesting(false)
        }
    }

    private func ghostCornerText(_ string: String, weight: Font.Weight = .regular) -> some View {
        Text(string)
            .font(.system(size: 10, weight: weight))
            .monospacedDigit()
    }

    /// Resolves a pointer Y to the start time of the 5h window a click would
    /// create:
    /// - before now -> nil (do not offer a window in the past),
    /// - after now and the snapped slot fits free -> that slot (offer here),
    /// - after now but the snapped slot overlaps a window -> the earliest free
    ///   future slot (offer at the next possible position).
    /// Returns nil when no free slot remains before day end.
    private func resolvedPlanStart(forY y: CGFloat) -> Date? {
        let snapped = snappedStart(forY: y)
        guard snapped > now else { return nil }
        if canQuickPlan(at: snapped) { return snapped }
        return nextAvailableStart(after: snapped)
    }

    /// Walks the provider grid forward from `snapped`, returning the first slot
    /// that is in the future and free, bounded by the day's latest valid start.
    private func nextAvailableStart(after snapped: Date) -> Date? {
        let step = TimeInterval(providerID.plannedWindowSnapMinutes * 60)
        let interval = CalendarPositioning.dayInterval(for: date)
        let latestStart = interval.end.addingTimeInterval(-step)
        var candidate = snapped.addingTimeInterval(step)
        while candidate <= latestStart {
            if candidate > now, canQuickPlan(at: candidate) { return candidate }
            candidate = candidate.addingTimeInterval(step)
        }
        return nil
    }

    private func displayedStart(for window: PlannedWindow) -> Date {
        if draggingPlannedID == window.id {
            return dragPreviewStart ?? window.startAt
        }
        return window.startAt
    }

    private func draggedStart(for window: PlannedWindow, translationY: CGFloat) -> Date {
        // For cross-midnight windows the rendered block is anchored to the
        // visible (clipped) portion, so anchor the drag math there too and
        // reapply the delta to the original startAt to preserve the hidden
        // prefix.
        let dayStart = CalendarPositioning.dayInterval(for: date).start
        let visibleStart = max(window.startAt, dayStart)
        let draggedVisibleStart = snappedStart(
            forY: yOffset(for: visibleStart) + translationY
        )
        return window.startAt.addingTimeInterval(
            draggedVisibleStart.timeIntervalSince(visibleStart)
        )
    }

    private func snappedStart(forY y: CGFloat) -> Date {
        let raw = CalendarPositioning.date(
            forYOffset: y,
            on: date,
            pixelsPerMinute: layout.pixelsPerMinute
        )
        let snapped = CalendarPositioning.snap(raw, toMinutes: providerID.plannedWindowSnapMinutes)
        let interval = CalendarPositioning.dayInterval(for: date)
        let latestStart = interval.end.addingTimeInterval(
            -Double(providerID.plannedWindowSnapMinutes) * 60
        )
        return min(max(snapped, interval.start), latestStart)
    }

    private func canQuickPlan(at start: Date) -> Bool {
        let candidate = PlannedWindow(
            providerID: providerID,
            startAt: start,
            durationSeconds: Self.fiveHourSeconds
        )
        return !PlannedWindowValidator
            .validate(
                candidate: candidate,
                against: activePlannedWindows,
                actualWindows: actualSegments.map(\.window)
            )
            .hasConflict
    }

    /// The allowed start closest to `candidate` on the provider's snap grid
    /// (see `PlannedSlotResolver`). Returns nil when the day holds no allowed
    /// start at all, in which case the caller keeps the window put.
    private func nearestAllowedStart(for window: PlannedWindow, near candidate: Date) -> Date? {
        PlannedSlotResolver.nearestAllowedStart(
            near: candidate,
            in: CalendarPositioning.dayInterval(for: date),
            stepSeconds: TimeInterval(providerID.plannedWindowSnapMinutes * 60)
        ) { canPlace(window, at: $0) }
    }

    /// Whether the dragged `window` may occupy `start`: not in the past (the
    /// same rule click-to-plan uses) and not overlapping another planned window
    /// or an actual window. The candidate keeps the window's own id so the
    /// validator does not count the window as conflicting with itself.
    private func canPlace(_ window: PlannedWindow, at start: Date) -> Bool {
        guard start > now else { return false }
        var candidate = window
        candidate.startAt = start
        return !PlannedWindowValidator
            .validate(
                candidate: candidate,
                against: activePlannedWindows,
                actualWindows: actualSegments.map(\.window)
            )
            .hasConflict
    }

    @ViewBuilder
    private var weeklyBlock: some View {
        if let weeklyWindow,
           let segment = visibleSegment(
               start: weeklyWindow.startAt,
               durationSeconds: weeklyWindow.durationSeconds
           ) {
            WeeklyWindowBlockView(
                window: weeklyWindow,
                history: history,
                now: now,
                columnWidth: columnWidth,
                layout: layout,
                visibleDurationSeconds: segment.durationSeconds,
                clipsTop: segment.clippedStart,
                clipsBottom: segment.clippedEnd,
                segmentStart: segment.start
            )
            .offset(
                x: blockContentX,
                y: yOffset(for: segment.start)
            )
            .zIndex(0)
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
            on: date
        )
    }

}
