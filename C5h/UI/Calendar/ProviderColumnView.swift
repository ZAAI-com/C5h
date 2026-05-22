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
                            history: history,
                            now: now,
                            columnWidth: columnWidth,
                            layout: layout,
                            visibleDurationSeconds: segment.durationSeconds,
                            clipsTop: segment.clippedStart,
                            clipsBottom: segment.clippedEnd,
                            displayStart: draggingPlannedID == window.id ? displayStart : nil
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
                            clipsBottom: segment.clippedEnd
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
                hoverY = hoveredStart(forY: location.y) != nil ? location.y : nil
            case .ended:
                hoverY = nil
            }
        }
        .onTapGesture { location in
            guard let start = hoveredStart(forY: location.y) else { return }
            onQuickPlan?(start)
            hoverY = nil
        }
    }

    @ViewBuilder
    private var ghostPlanBlock: some View {
        if hoveredPlannedID == nil,
           draggingPlannedID == nil,
           let hoverY,
           let start = hoveredStart(forY: hoverY) {
            let height = CalendarPositioning.blockHeight(
                durationSeconds: Self.fiveHourSeconds,
                pixelsPerMinute: layout.pixelsPerMinute
            )
            VStack(alignment: .leading, spacing: 2) {
                Text("Plan 5h \(providerID.displayName) window")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                Text("starts \(timeFormatter.string(from: start))")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer(minLength: 0)
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

    /// Maps a pointer Y to the planned-window start time, snapped to the
    /// provider grid. Returns nil for past or conflicting slots.
    private func hoveredStart(forY y: CGFloat) -> Date? {
        let snapped = snappedStart(forY: y)
        guard snapped > now else { return nil }
        guard canQuickPlan(at: snapped) else { return nil }
        return snapped
    }

    private func displayedStart(for window: PlannedWindow) -> Date {
        if draggingPlannedID == window.id {
            return dragPreviewStart ?? window.startAt
        }
        return window.startAt
    }

    private func draggedStart(for window: PlannedWindow, translationY: CGFloat) -> Date {
        snappedStart(forY: yOffset(for: window.startAt) + translationY)
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
            .validate(candidate: candidate, against: plannedWindows)
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

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }
}
