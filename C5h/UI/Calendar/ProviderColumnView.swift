import SwiftUI
import C5hCore

struct ProviderColumnView: View {
    let providerID: ProviderID
    let plannedWindows: [PlannedWindow]
    let actualWindows: [ActualWindow5h]
    let history: UsageHistorySeries?
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

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            ghostPlanBlock
            ForEach(plannedWindows) { window in
                let isActive = hoveredPlannedID == window.id || draggingPlannedID == window.id
                let displayStart = displayedStart(for: window)
                if let segment = visibleSegment(start: displayStart, durationSeconds: window.durationSeconds) {
                    Button {
                        onSelectPlanned(window)
                    } label: {
                        PlannedWindowBlockView(
                            window: window,
                            now: now,
                            columnWidth: columnWidth,
                            layout: layout,
                            visibleDurationSeconds: segment.durationSeconds,
                            clipsTop: segment.clippedStart,
                            clipsBottom: segment.clippedEnd,
                            displayStart: draggingPlannedID == window.id ? displayStart : nil,
                            emphasizeEndTime: true
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
                    }
                    .buttonStyle(.plain)
                    .offset(y: yOffset(for: segment.start))
                    .padding(.leading, 2)
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
            ForEach(actualWindows) { window in
                if let segment = visibleSegment(start: window.startAt, durationSeconds: window.durationSeconds) {
                    Button {
                        onSelectActual(window)
                    } label: {
                        ActualWindowBlockView(
                            window: window,
                            history: history,
                            now: now,
                            columnWidth: columnWidth,
                            layout: layout,
                            visibleDurationSeconds: segment.durationSeconds,
                            clipsTop: segment.clippedStart,
                            clipsBottom: segment.clippedEnd,
                            segmentStart: segment.start
                        )
                    }
                    .buttonStyle(.plain)
                    .offset(
                        x: columnWidth * (1 - layout.actualBlockWidthRatio) - 2,
                        y: yOffset(for: segment.start)
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
                hoverY = resolvedPlanStart(forY: location.y) != nil ? location.y : nil
            case .ended:
                hoverY = nil
            }
        }
        .onTapGesture { location in
            guard let start = resolvedPlanStart(forY: location.y) else { return }
            onQuickPlan?(start)
            hoverY = nil
        }
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
    /// create: the snapped slot under the cursor when it is in the future and
    /// free, otherwise the earliest free slot later in the same day. Returns nil
    /// when no free slot remains before day end.
    private func resolvedPlanStart(forY y: CGFloat) -> Date? {
        let snapped = snappedStart(forY: y)
        if snapped > now, canQuickPlan(at: snapped) { return snapped }
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
                activeActualWindows: actualWindows,
                now: now
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
