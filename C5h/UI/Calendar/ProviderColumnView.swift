import SwiftUI
import C5hCore

struct ProviderColumnView: View {
    let providerID: ProviderID
    let plannedWindows: [PlannedWindow]
    let actualWindows: [ActualWindow5h]
    let date: Date
    let now: Date
    let layout: CalendarLayoutConfig
    let columnWidth: CGFloat
    let onSelectPlanned: (PlannedWindow) -> Void
    let onSelectActual: (ActualWindow5h) -> Void
    var onQuickPlan: ((Date) -> Void)? = nil

    @State private var hoverY: CGFloat?

    private static let fiveHourSeconds = ClaudeUsageStatus.fiveHourDurationSeconds
    private static let snapMinutes = 5

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            ghostPlanBlock
            ForEach(plannedWindows) { window in
                Button {
                    onSelectPlanned(window)
                } label: {
                    PlannedWindowBlockView(
                        window: window,
                        columnWidth: columnWidth,
                        layout: layout
                    )
                }
                .buttonStyle(.plain)
                .offset(y: yOffset(for: window.startAt))
                .padding(.leading, 2)
            }
            ForEach(actualWindows) { window in
                Button {
                    onSelectActual(window)
                } label: {
                    ActualWindowBlockView(
                        window: window,
                        columnWidth: columnWidth,
                        layout: layout
                    )
                }
                .buttonStyle(.plain)
                .offset(
                    x: columnWidth * (1 - layout.actualBlockWidthRatio) - 2,
                    y: yOffset(for: window.startAt)
                )
            }
            if Calendar.current.isDate(now, inSameDayAs: date) {
                NowLineView(layout: layout)
                    .frame(width: columnWidth)
                    .offset(y: yOffset(for: now))
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
        if let hoverY,
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
    /// 5-minute grid. Returns nil for times that are in the past — the hover
    /// affordance only shows for future slots.
    private func hoveredStart(forY y: CGFloat) -> Date? {
        let raw = CalendarPositioning.date(
            forYOffset: y,
            on: date,
            pixelsPerMinute: layout.pixelsPerMinute
        )
        let snapped = CalendarPositioning.snap(raw, toMinutes: Self.snapMinutes)
        guard snapped > now else { return nil }
        return snapped
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

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }
}
