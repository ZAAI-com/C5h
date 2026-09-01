import SwiftUI
import C5hCore

struct WeeklyWindowBlockView: View {
    let window: ActualWindow7d
    let history: UsageHistorySeries?
    var now: Date = .now
    let columnWidth: CGFloat
    let layout: CalendarLayoutConfig
    let visibleDurationSeconds: Int
    let clipsTop: Bool
    let clipsBottom: Bool
    let segmentStart: Date

    /// Estimated rendered height of one reading row, used to clamp rows inside the
    /// block and to keep two closely-timed readings from overlapping.
    private static let rowHeight: CGFloat = 14

    /// A real 7d reading placed at a vertical offset inside the block.
    private struct PlacedRow: Hashable {
        let capturedAt: Date
        let used: Double
        let offset: CGFloat
    }

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
        let rows = placedRows(
            scopedHistory: scopedHistory,
            segmentEnd: segmentEnd,
            height: height,
            pad: pad
        )

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

            ForEach(rows, id: \.self) { row in
                usageReadingRow(
                    at: row.capturedAt,
                    used: row.used,
                    contentWidth: contentWidth
                )
                .padding(.horizontal, pad)
                .offset(y: row.offset)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .clipShape(shape)
        .allowsHitTesting(false)
    }

    /// One reading row styled like the 5h block: the clock time the usage command
    /// ran on the left and its "7d usage X%" reading on the right. There is no 5h
    /// column, since the 7d block is only shown for weekly-only providers.
    private func usageReadingRow(
        at time: Date,
        used: Double,
        contentWidth: CGFloat
    ) -> some View {
        ZStack(alignment: .leading) {
            Text(BlockFormatters.formatTime(time))
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
            BlockFormatters.usageMetricText(label: "7d usage", value: used, size: 10)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(width: contentWidth, alignment: .leading)
        .foregroundStyle(C5hColors.fgSecondary)
    }

    /// The reading rows to draw: one per real usage-command reading captured in the
    /// past, visible part of the segment. Future time carries no measured usage, so
    /// the segment is clipped at `now` (a fully-future segment, e.g. the Tomorrow
    /// column, yields no rows and leaves only the translucent band). When two
    /// readings land closer than a row height, the later (fresher) one wins so dense
    /// polling can never stack overlapping rows.
    private func placedRows(
        scopedHistory: UsageHistorySeries?,
        segmentEnd: Date,
        height: CGFloat,
        pad: CGFloat
    ) -> [PlacedRow] {
        let visibleEnd = min(segmentEnd, now)
        guard visibleEnd > segmentStart, let scopedHistory else { return [] }
        let readings = scopedHistory.weeklyReadings(
            in: DateInterval(start: segmentStart, end: visibleEnd)
        )
        var placed: [PlacedRow] = []
        for reading in readings {
            let offset = rowOffset(for: reading.capturedAt, height: height, pad: pad)
            let row = PlacedRow(capturedAt: reading.capturedAt, used: reading.used, offset: offset)
            // Offsets are non-decreasing in capture time, so replacing the last row
            // keeps the gap to the row before it and surfaces the freshest reading in
            // an over-dense cluster.
            if let last = placed.last, offset - last.offset < Self.rowHeight {
                placed[placed.count - 1] = row
            } else {
                placed.append(row)
            }
        }
        return placed
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
