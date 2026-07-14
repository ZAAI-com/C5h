import SwiftUI
import C5hCore

struct WeeklyWindowBlockView: View {
    let window: ActualWindow7d
    let history: UsageHistorySeries?
    let date: Date
    let columnWidth: CGFloat
    let layout: CalendarLayoutConfig
    let visibleDurationSeconds: Int
    let clipsTop: Bool
    let clipsBottom: Bool
    let segmentStart: Date
    let onSelect: () -> Void

    private static let openingWindowSeconds: TimeInterval = 4 * 60

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
        let scopedHistory = history?.scoped(toWeeklyWindowEndingAt: window.endAt)
        let carryIn = scopedHistory?.weeklyOpeningReading(
            at: segmentStart,
            within: Self.openingWindowSeconds
        )
        let inDayReading = scopedHistory?.latestDistinctWeeklyReading(
            on: date,
            carryInUsed: carryIn?.used
        )
        // The reading is picked from the whole calendar day, but this view
        // renders only [segmentStart, segmentEnd). A reading outside that span
        // (e.g. captured just after the reset on a partial last day) would be
        // clamped onto a block edge by `inDayOffset`, misrepresenting when it
        // happened, so it is dropped rather than shown at the wrong position.
        let segmentEnd = segmentStart.addingTimeInterval(TimeInterval(visibleDurationSeconds))
        let remaining = window.remainingPercentage

        ZStack(alignment: .topLeading) {
            shape
                .fill(C5hColors.tintForProvider(window.providerID).opacity(0.12))
                .overlay {
                    shape.strokeBorder(
                        C5hColors.tintForProvider(window.providerID).opacity(0.35),
                        lineWidth: 1
                    )
                }
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 2) {
                if let carryIn {
                    weeklyRemainingLabel(used: carryIn.used)
                }
                Spacer(minLength: 0)
            }
            .padding(pad)
            .allowsHitTesting(false)

            if let inDayReading,
               inDayReading.capturedAt >= segmentStart,
               inDayReading.capturedAt < segmentEnd {
                weeklyRemainingLabel(used: inDayReading.used)
                    .padding(.horizontal, pad)
                    .offset(y: inDayOffset(
                        capturedAt: inDayReading.capturedAt,
                        height: height,
                        pad: pad
                    ))
                    .allowsHitTesting(false)
            }

            HStack {
                Spacer(minLength: 0)
                weeklyBadge(remaining: remaining)
                    .padding(pad)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .clipShape(shape)
    }

    private func weeklyBadge(remaining: Double) -> some View {
        Button(action: onSelect) {
            VStack(alignment: .trailing, spacing: 4) {
                Text("7d · \(BlockFormatters.formatPercent(remaining)) remaining")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                Text("resets \(BlockFormatters.formatTime(window.endAt))")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                ProgressView(value: remaining, total: 100)
                    .progressViewStyle(.linear)
                    .tint(C5hColors.tintForProvider(window.providerID))
                    .frame(width: 120)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Shared "7d N% remaining" reading label used for both the carry-in and the
    /// in-day snapshot, so their formatting and styling cannot drift apart.
    private func weeklyRemainingLabel(used: Double) -> some View {
        Text("7d \(BlockFormatters.formatPercent(ActualWindow7d.remainingPercentage(fromUsed: used))) remaining")
            .font(.system(size: 10, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(C5hColors.fgSecondary)
    }

    private func inDayOffset(capturedAt: Date, height: CGFloat, pad: CGFloat) -> CGFloat {
        let y = CalendarPositioning.yOffset(
            for: capturedAt,
            pixelsPerMinute: layout.pixelsPerMinute
        ) - CalendarPositioning.yOffset(
            for: segmentStart,
            pixelsPerMinute: layout.pixelsPerMinute
        )
        return min(max(y, pad), max(pad, height - 20))
    }
}
