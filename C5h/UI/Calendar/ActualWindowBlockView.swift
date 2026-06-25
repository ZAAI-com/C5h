import SwiftUI
import C5hCore

struct ActualWindowBlockView: View {
    let window: ActualWindow5h
    let history: UsageHistorySeries?
    var now: Date = .now
    let columnWidth: CGFloat
    let layout: CalendarLayoutConfig
    var visibleDurationSeconds: Int? = nil
    var clipsTop: Bool = false
    var clipsBottom: Bool = false
    var compact: Bool = false
    /// When false, the "from … CLI" / "manual" source footer is suppressed.
    /// The Week overview hides it to keep the dense tiles readable; the Day
    /// view keeps it (the default).
    var showsSourceLabel: Bool = true
    /// When the block is rendering a clipped segment of a cross-midnight
    /// window, the caller passes the segment's actual displayed start/end so
    /// corner labels and history lookups match what's on screen.
    var displayStart: Date? = nil
    var displayEnd: Date? = nil

    var body: some View {
        let duration = visibleDurationSeconds ?? window.durationSeconds
        let height = CalendarPositioning.blockHeight(
            durationSeconds: duration,
            pixelsPerMinute: layout.pixelsPerMinute
        )
        let density = BlockDensity.forHeight(height, compact: compact)
        let radius = layout.blockCornerRadius
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: clipsTop ? 0 : radius,
            bottomLeadingRadius: clipsBottom ? 0 : radius,
            bottomTrailingRadius: clipsBottom ? 0 : radius,
            topTrailingRadius: clipsTop ? 0 : radius,
            style: .continuous
        )
        let width = compact ? columnWidth : columnWidth * layout.actualBlockWidthRatio

        let shownStart = displayStart ?? window.startAt
        let shownEnd = displayEnd ?? window.endAt
        let startSevenD: Double? = shownStart > now
            ? nil
            : Self.meaningfulSevenDay(history?.sevenDayPercent(at: shownStart)?.value)
        let endSevenD: Double? = shownEnd > now
            ? nil
            : Self.meaningfulSevenDay(history?.sevenDayPercent(at: shownEnd)?.value)
        // Anchor the 5h reading to this window's own time (capped at `now` so an
        // in-progress window still shows the current value); hide for windows
        // that start in the future, matching the 7d guards above.
        let fiveHourAnchor = min(shownEnd, now)
        let windowed5h: (value: Double, asOf: Date)? = shownStart > now
            ? nil
            : history?.fiveHourPercent(at: fiveHourAnchor)

        ZStack {
            cornersOverlay(
                shownStart: shownStart,
                shownEnd: shownEnd,
                startSevenD: startSevenD,
                endSevenD: endSevenD,
                density: density,
                isNarrow: width < 130
            )
            if density.showsCenter {
                centerOverlay(fiveHour: windowed5h, density: density)
            }
        }
        .padding(compact ? 3 : 6)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(shape.fill(brandColor))
        .clipShape(shape)
        .foregroundStyle(.white)
    }

    private func cornersOverlay(
        shownStart: Date,
        shownEnd: Date,
        startSevenD: Double?,
        endSevenD: Double?,
        density: BlockDensity,
        isNarrow: Bool
    ) -> some View {
        VStack(spacing: 0) {
            if isNarrow {
                VStack(alignment: .leading, spacing: 0) {
                    cornerText(BlockFormatters.formatTime(shownStart), weight: .semibold)
                    if let v = startSevenD {
                        cornerText("7d limit \(BlockFormatters.formatPercent(v))")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .top) {
                    cornerText(BlockFormatters.formatTime(shownStart), weight: .semibold)
                    Spacer(minLength: 0)
                    if let v = startSevenD {
                        cornerText("7d limit \(BlockFormatters.formatPercent(v))", alignment: .trailing)
                    }
                }
            }
            Spacer(minLength: 0)
            if density.showsBottomCorners {
                if isNarrow {
                    VStack(alignment: .leading, spacing: 0) {
                        if let v = endSevenD {
                            cornerText("7d limit \(BlockFormatters.formatPercent(v))")
                        }
                        cornerText(BlockFormatters.formatTime(shownEnd))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(alignment: .bottom) {
                        cornerText(BlockFormatters.formatTime(shownEnd))
                        Spacer(minLength: 0)
                        if let v = endSevenD {
                            cornerText("7d limit \(BlockFormatters.formatPercent(v))", alignment: .trailing)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func centerOverlay(
        fiveHour: (value: Double, asOf: Date)?,
        density: BlockDensity
    ) -> some View {
        VStack(spacing: 1) {
            if let p = fiveHour {
                Text("5h: \(BlockFormatters.formatPercent(p.value))")
                    .font(.system(size: compact ? 9 : 10, weight: .semibold))
                Text("@ \(BlockFormatters.formatTime(p.asOf))")
                    .font(.system(size: compact ? 8 : 9))
                    .opacity(0.85)
            } else {
                Text("—")
                    .font(.system(size: compact ? 9 : 10))
                    .opacity(0.85)
            }
            if showsSourceLabel, density.showsDetailLine {
                Text(sourceLabel)
                    .font(.system(size: 9))
                    .opacity(0.75)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func cornerText(
        _ string: String,
        weight: Font.Weight = .regular,
        alignment: TextAlignment = .leading
    ) -> some View {
        Text(string)
            .font(.system(size: compact ? 9 : 10, weight: weight))
            .multilineTextAlignment(alignment)
            .monospacedDigit()
    }

    /// Returns the 7d% only when there is enough data to be worth showing.
    /// A missing reading (`nil`) or one that rounds to 0% is treated as "not
    /// enough data" and hidden, so tiles don't render a meaningless `7d limit 0%`.
    private static func meaningfulSevenDay(_ value: Double?) -> Double? {
        guard let value, value.rounded() >= 1 else { return nil }
        return value
    }

    private var brandColor: Color {
        C5hColors.tintForProvider(window.providerID)
    }

    private var sourceLabel: String {
        switch window.source {
        case .c5hTriggered: "from \(window.providerID.displayName) CLI (triggered)"
        case .detectedFromUsage: "from \(window.providerID.displayName) CLI"
        case .manual: "manual"
        }
    }
}
