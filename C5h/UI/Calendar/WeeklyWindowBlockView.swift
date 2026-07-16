import SwiftUI
import C5hCore

struct WeeklyWindowBlockView: View {
    let window: ActualWindow7d
    let history: UsageHistorySeries?
    let columnWidth: CGFloat
    let layout: CalendarLayoutConfig
    let visibleDurationSeconds: Int
    let clipsTop: Bool
    let clipsBottom: Bool
    let segmentStart: Date

    /// Cadence of the reading rows drawn down the block.
    private static let rowIntervalSeconds: TimeInterval = 2 * 60 * 60
    /// Estimated rendered height of one reading row, used to clamp rows inside the
    /// block and to keep the reset row clear of a nearby 2-hour mark.
    private static let rowHeight: CGFloat = 14

    var body: some View {
        let height = CalendarPositioning.blockHeight(
            durationSeconds: visibleDurationSeconds,
            pixelsPerMinute: layout.pixelsPerMinute
        )
        let radius = layout.blockCornerRadius
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: clipsTop ? 0 : radius,
            bottomLeadingRadius: clipsBottom ? 0 : radius,
            bottomTrailingRadius: clipsBottom ? 0 : radius,
            topTrailingRadius: clipsTop ? 0 : radius,
            style: .continuous
        )
        let width = max(0, columnWidth - 4)
        let pad: CGFloat = 6
        let contentWidth = max(0, width - 2 * pad)
        let scopedHistory = history?.scoped(toWeeklyWindowEndingAt: window.endAt)
        let segmentEnd = segmentStart.addingTimeInterval(TimeInterval(visibleDurationSeconds))
        let rows = readingRows(segmentEnd: segmentEnd)

        // The block is drawn behind the planned/actual lanes and is not
        // interactive: taps are routed to the weekly window by
        // `ProviderColumnView.windowSelection`, so every layer opts out of hit
        // testing and lets the tap fall through to the column.
        ZStack(alignment: .topLeading) {
            shape
                .fill(C5hColors.tintForProvider(window.providerID).opacity(0.12))
                .overlay {
                    shape.strokeBorder(
                        C5hColors.tintForProvider(window.providerID).opacity(0.35),
                        lineWidth: 1
                    )
                }

            ForEach(rows, id: \.self) { rowTime in
                usageReadingRow(
                    at: rowTime,
                    used: scopedHistory?.sevenDayPercent(at: rowTime)?.value,
                    contentWidth: contentWidth
                )
                .padding(.horizontal, pad)
                .offset(y: rowOffset(for: rowTime, height: height, pad: pad))
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .clipShape(shape)
        .allowsHitTesting(false)
    }

    /// One reading row styled like the 5h block: the clock time on the left and,
    /// when a reading exists, "7d usage X%" on the right. There is no 5h column,
    /// since the 7d block is only shown for weekly-only providers.
    private func usageReadingRow(
        at time: Date,
        used: Double?,
        contentWidth: CGFloat
    ) -> some View {
        ZStack(alignment: .leading) {
            Text(BlockFormatters.formatTime(time))
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
            if let used {
                BlockFormatters.usageMetricText(label: "7d usage", value: used, size: 10)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(width: contentWidth, alignment: .leading)
        .foregroundStyle(C5hColors.fgSecondary)
    }

    /// Even-clock-hour marks every 2 hours across `[segmentStart, segmentEnd)`,
    /// plus the reset boundary (`window.endAt`) as the final row on the day the
    /// window resets, mirroring the 5h block's end corner.
    private func readingRows(segmentEnd: Date) -> [Date] {
        let calendar = Calendar.current
        var mark = calendar.startOfDay(for: segmentStart)
        while mark < segmentStart {
            mark = mark.addingTimeInterval(Self.rowIntervalSeconds)
        }
        var marks: [Date] = []
        while mark < segmentEnd {
            marks.append(mark)
            mark = mark.addingTimeInterval(Self.rowIntervalSeconds)
        }
        if !clipsBottom {
            // Drop any 2-hour mark within a row's height of the reset so the reset
            // row doesn't collide with it, then show the reset time itself.
            let minGapSeconds = Double(Self.rowHeight / max(layout.pixelsPerMinute, 0.001)) * 60
            while let last = marks.last, window.endAt.timeIntervalSince(last) < minGapSeconds {
                marks.removeLast()
            }
            marks.append(window.endAt)
        }
        return marks
    }

    /// Vertical offset of a reading row from the block's top edge, clamped to keep
    /// the row inside the block.
    private func rowOffset(for time: Date, height: CGFloat, pad: CGFloat) -> CGFloat {
        let y = CalendarPositioning.yOffset(
            for: time,
            pixelsPerMinute: layout.pixelsPerMinute
        ) - CalendarPositioning.yOffset(
            for: segmentStart,
            pixelsPerMinute: layout.pixelsPerMinute
        )
        return min(max(y, pad), max(pad, height - Self.rowHeight - pad))
    }
}
