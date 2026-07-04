import SwiftUI
import C5hCore

struct ProviderColumnView: View {
    let providerID: ProviderID
    let plannedWindows: [PlannedWindow]
    let actualSegments: [ActualWindow5hDisplaySegment]
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
    let onMovePlanned: (PlannedWindow, Date) -> Void
    var onQuickPlan: ((Date) -> Void)? = nil

    @State private var hoverY: CGFloat?
    @State private var hoveredPlannedID: UUID?
    @State private var draggingPlannedID: UUID?
    @State private var dragPreviewStart: Date?

    private static let fiveHourSeconds = ClaudeUsageStatus.fiveHourDurationSeconds
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
            let stackedYOffsets = stackedBlockYOffsets
            ForEach(activePlannedWindows) { window in
                let isActive = hoveredPlannedID == window.id || draggingPlannedID == window.id
                let displayStart = displayedStart(for: window)
                if let segment = visibleSegment(start: displayStart, durationSeconds: window.durationSeconds) {
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
                        widthOverride: blockContentWidth
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
                        x: blockContentX,
                        y: stackedYOffsets[.planned(window.id)] ?? yOffset(for: segment.start)
                    )
                    .opacity(draggingPlannedID == window.id ? 0.85 : 1)
                    .zIndex(draggingPlannedID == window.id ? 3 : 1)
                    .onHover { hovering in
                        if hovering {
                            hoveredPlannedID = window.id
                        } else if hoveredPlannedID == window.id {
                            hoveredPlannedID = nil
                        }
                    }
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { value in
                                draggingPlannedID = window.id
                                hoverY = nil
                                dragPreviewStart = draggedStart(
                                    for: window,
                                    translationY: value.translation.height
                                )
                            }
                            .onEnded { value in
                                let start = draggedStart(
                                    for: window,
                                    translationY: value.translation.height
                                )
                                draggingPlannedID = nil
                                dragPreviewStart = nil
                                if start != window.startAt {
                                    onMovePlanned(window, start)
                                }
                            }
                    )
                }
            }
            ForEach(actualSegments) { actualSegment in
                let window = actualSegment.window
                if let segment = visibleSegment(start: actualSegment.startAt, durationSeconds: actualSegment.durationSeconds) {
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
                        widthOverride: blockContentWidth,
                        isReset: resetWindowIDs.contains(actualSegment.id)
                    )
                    .offset(
                        x: blockContentX,
                        y: stackedYOffsets[.actual(actualSegment.id)] ?? yOffset(for: segment.start)
                    )
                    .zIndex(2)
                }
            }
        }
        .frame(width: columnWidth, height: layout.dayHeight, alignment: .topLeading)
        .clipped()
        .contentShape(Rectangle())
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
    }

    /// Resolves a tap location to the window block whose rendered frame (its
    /// horizontal extent and vertical span) contains the pointer, so taps open a
    /// block's details instead of quick-planning. The white area beside a block,
    /// even at the block's time, is not "inside" the window. Actual blocks are
    /// checked first because they are drawn on top of the planned lane, so they
    /// win when a point falls in the lane overlap of both.
    private func windowSelection(at location: CGPoint) -> WindowHit? {
        let stackedYOffsets = stackedBlockYOffsets
        for actualSegment in actualSegments {
            guard let segment = visibleSegment(
                start: actualSegment.startAt,
                durationSeconds: actualSegment.durationSeconds
            ) else { continue }
            guard verticalSpan(
                of: segment,
                stackID: .actual(actualSegment.id),
                yOffsets: stackedYOffsets
            ).contains(location.y) else { continue }
            if location.x >= blockContentX, location.x <= blockContentX + blockContentWidth {
                return .actual(actualSegment.window)
            }
        }
        if blockContentX <= location.x, location.x <= blockContentX + blockContentWidth {
            for window in activePlannedWindows {
                let displayStart = displayedStart(for: window)
                guard let segment = visibleSegment(
                    start: displayStart,
                    durationSeconds: window.durationSeconds
                ) else { continue }
                if verticalSpan(
                    of: segment,
                    stackID: .planned(window.id),
                    yOffsets: stackedYOffsets
                ).contains(location.y) {
                    return .planned(window)
                }
            }
        }
        return nil
    }

    private func verticalSpan(
        of segment: (start: Date, durationSeconds: Int, clippedStart: Bool, clippedEnd: Bool),
        stackID: StackID,
        yOffsets: [StackID: CGFloat]
    ) -> ClosedRange<CGFloat> {
        let top = yOffsets[stackID] ?? yOffset(for: segment.start)
        let height = CalendarPositioning.blockHeight(
            durationSeconds: segment.durationSeconds,
            pixelsPerMinute: layout.pixelsPerMinute
        )
        return top...(top + height)
    }

    private var activePlannedWindows: [PlannedWindow] {
        plannedWindows.filter { !$0.status.isTerminal }
    }

    private var blockContentX: CGFloat { 2 }

    private var blockContentWidth: CGFloat {
        max(0, columnWidth - 4)
    }

    private var stackedBlockYOffsets: [StackID: CGFloat] {
        var blocks: [StackBlock] = []
        for window in activePlannedWindows {
            let displayStart = displayedStart(for: window)
            guard let segment = visibleSegment(
                start: displayStart,
                durationSeconds: window.durationSeconds
            ) else { continue }
            blocks.append(StackBlock(
                id: .planned(window.id),
                yOffset: yOffset(for: segment.start),
                height: CalendarPositioning.blockHeight(
                    durationSeconds: segment.durationSeconds,
                    pixelsPerMinute: layout.pixelsPerMinute
                ),
                sortPriority: 0
            ))
        }
        for actualSegment in actualSegments {
            guard let segment = visibleSegment(
                start: actualSegment.startAt,
                durationSeconds: actualSegment.durationSeconds
            ) else { continue }
            blocks.append(StackBlock(
                id: .actual(actualSegment.id),
                yOffset: yOffset(for: segment.start),
                height: CalendarPositioning.blockHeight(
                    durationSeconds: segment.durationSeconds,
                    pixelsPerMinute: layout.pixelsPerMinute
                ),
                sortPriority: 1
            ))
        }
        let sorted = blocks.sorted {
            if $0.yOffset != $1.yOffset { return $0.yOffset < $1.yOffset }
            return $0.sortPriority < $1.sortPriority
        }
        let placements = CalendarPositioning.stackVertically(
            sorted.map { .init(yOffset: $0.yOffset, height: $0.height) },
            gap: layout.blockVerticalGap
        )
        var map: [StackID: CGFloat] = [:]
        for (block, placement) in zip(sorted, placements) {
            map[block.id] = placement.yOffset
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
                against: plannedWindows,
                actualWindows: actualSegments.map(\.window)
            )
            .hasConflict
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
