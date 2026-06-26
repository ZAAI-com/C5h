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
    /// The block's visible top time (the start of the segment rendered in this
    /// column). Used to convert a usage reading's capture time into a vertical
    /// offset inside the block. For cross-midnight segments this is the clamped
    /// (midnight) start, matching the block's on-screen position. Unused by the
    /// condensed Week layout.
    var segmentStart: Date = .distantPast
    /// When true, the block uses the condensed Week-overview layout: a bold start
    /// time pinned top-left, with the 5h and 7d usage lines sitting directly above
    /// a bold end time at the bottom-left. The Day view (Today/Tomorrow) keeps the
    /// default full layout with start/end corners and centered usage readings.
    var condensed: Bool = false

    private struct DayUsageRow: Identifiable {
        enum Source: String {
            case opening
            case floating
            case closing
        }

        let source: Source
        let capturedAt: Date
        let fiveHour: Double?
        let sevenDay: Double?
        let showFiveHourWhenZero: Bool

        var id: String {
            "\(source.rawValue)-\(capturedAt.timeIntervalSinceReferenceDate)"
        }
    }

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
        let pad: CGFloat = compact ? 3 : 6

        // Always label corners with the window's real bounds, even when this is
        // a clipped segment of a cross-midnight window. The rounded-corner
        // clipping (clipsTop/clipsBottom) already signals the continuation, and
        // block position/height still follow the visible segment.
        let shownStart = window.startAt
        let shownEnd = window.endAt
        let visibleStart = effectiveSegmentStart
        let usageAnchor = min(shownEnd, now)
        let isPast = shownEnd <= now
        let isCurrent = shownStart <= now && now < shownEnd
        let condensedSevenD = shownEnd > now
            ? nil
            : Self.meaningfulSevenDay(history?.sevenDayPercent(at: shownEnd)?.value)
        let condensed5h: (value: Double, asOf: Date)? = shownStart > now
            ? nil
            : history?.fiveHourPercent(at: usageAnchor)
        // Day view: the "opening" reading shown beside the start time, taken from
        // the first snapshot captured at or just after the window opened.
        let openReadingRaw = shownStart > now
            ? nil
            : history?.openingReading(at: shownStart, within: Self.openingWindowSeconds)
        // Day view: the "closing" reading shown beside the end time on a completed
        // window: the latest in-window snapshot at or before the end (targets the
        // last few minutes, falling back to the most recent earlier reading).
        let closeReading = isPast
            ? history?.usageReading(atOrBefore: shownEnd, notBefore: visibleStart)
            : nil
        // Suppress the opening annotation when it is the same capture as the close
        // (single-reading window) so the value isn't shown at both corners.
        let openReading = openReadingRaw.map(\.capturedAt) == closeReading.map(\.capturedAt)
            ? nil
            : openReadingRaw
        // Day view: the middle usage reading. A current window shows the latest
        // reading once it is at least 5 min past the start; a completed window
        // marks the moment 5h first hit 100%.
        let floatingReading = Self.floatingReading(
            history: history,
            isCurrent: isCurrent,
            isPast: isPast,
            shownStart: shownStart,
            shownEnd: shownEnd,
            visibleStart: visibleStart,
            usageAnchor: usageAnchor
        )
        let usageRows = Self.dayUsageRows(
            openReading: openReading,
            floatingReading: floatingReading,
            closeReading: closeReading
        )

        Group {
            if condensed {
                condensedOverlay(
                    shownStart: shownStart,
                    shownEnd: shownEnd,
                    endSevenD: condensedSevenD,
                    fiveHour: condensed5h
                )
                .padding(pad)
            } else {
                ZStack(alignment: .topLeading) {
                    cornersOverlay(
                        shownStart: shownStart,
                        shownEnd: shownEnd,
                        density: density
                    )
                    .padding(pad)
                    if density.showsCenter, !usageRows.isEmpty {
                        dayUsageStackOverlay(rows: usageRows, pad: pad)
                    }
                }
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .background(shape.fill(brandColor))
        .clipShape(shape)
        .foregroundStyle(.white)
    }

    /// Start time pinned top-left and end time bottom-left. Usage annotations
    /// render in the centered stack so the time corners stay visually stable.
    private func cornersOverlay(
        shownStart: Date,
        shownEnd: Date,
        density: BlockDensity
    ) -> some View {
        VStack(spacing: 0) {
            cornerText(BlockFormatters.formatTime(shownStart), weight: .semibold)
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            if density.showsBottomCorners {
                cornerText(BlockFormatters.formatTime(shownEnd), weight: .semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Day view: a vertically centered stack of all visible usage readings for
    /// the block. Equal spacers keep the stack centered while reserving room for
    /// the pinned start/end time labels.
    private func dayUsageStackOverlay(
        rows: [DayUsageRow],
        pad: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: pad + labelLineHeight)
            VStack(spacing: 2) {
                ForEach(rows) { row in
                    dayUsageRow(row)
                }
            }
            .padding(.horizontal, pad)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Spacer(minLength: pad + labelLineHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Day view: one centered usage row. Labels are regular weight; percentages
    /// are emphasized.
    private func dayUsageRow(_ row: DayUsageRow) -> some View {
        HStack(spacing: 6) {
            if let five = Self.visibleFiveHour(
                row.fiveHour,
                showFiveHourWhenZero: row.showFiveHourWhenZero
            ) {
                usageMetricLabel("5h usage", value: five)
            }
            Spacer(minLength: 8)
            if let seven = Self.meaningfulSevenDay(row.sevenDay) {
                usageMetricLabel("7d usage", value: seven)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func usageMetricLabel(_ label: String, value: Double) -> some View {
        let percent = BlockFormatters.formatPercent(value)
        var text = AttributedString("\(label) \(percent)")
        text.font = .system(size: usageFontSize, weight: .regular)
        if let percentRange = text.range(of: percent) {
            text[percentRange].font = .system(size: usageFontSize, weight: .semibold)
        }
        return Text(text)
            .monospacedDigit()
    }

    /// Week overview: bold start time pinned top-left, then the 5h and 7d usage
    /// lines sitting directly above a bold end time at the bottom-left.
    private func condensedOverlay(
        shownStart: Date,
        shownEnd: Date,
        endSevenD: Double?,
        fiveHour: (value: Double, asOf: Date)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            cornerText(BlockFormatters.formatTime(shownStart), weight: .bold)
            Spacer(minLength: 0)
            if let p = fiveHour {
                cornerText("5h \(BlockFormatters.formatPercent(p.value))")
            }
            if let v = endSevenD {
                cornerText("7d \(BlockFormatters.formatPercent(v))")
            }
            cornerText(BlockFormatters.formatTime(shownEnd), weight: .bold)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    /// Estimated line height of a reading label, used to reserve space between
    /// the centered usage stack and the start/end corner times.
    private var labelLineHeight: CGFloat { compact ? 12 : 14 }

    private var usageFontSize: CGFloat { compact ? 9 : 10 }

    /// Returns the 7d value only when there is enough data to be worth showing.
    /// A missing reading (`nil`) or one that rounds to 0% is treated as "not
    /// enough data" and hidden, so tiles don't render a meaningless `7d usage 0%`.
    private static func meaningfulSevenDay(_ value: Double?) -> Double? {
        guard let value, value.rounded() >= 1 else { return nil }
        return value
    }

    private static func visibleFiveHour(
        _ value: Double?,
        showFiveHourWhenZero: Bool
    ) -> Double? {
        guard let value else { return nil }
        if showFiveHourWhenZero { return value }
        return value.rounded() >= 1 ? value : nil
    }

    private static func dayUsageRows(
        openReading: (capturedAt: Date, fiveHour: Double?, sevenDay: Double?)?,
        floatingReading: (capturedAt: Date, fiveHour: Double, sevenDay: Double?)?,
        closeReading: (capturedAt: Date, fiveHour: Double, sevenDay: Double?)?
    ) -> [DayUsageRow] {
        var rows: [DayUsageRow] = []
        if let openReading {
            rows.append(DayUsageRow(
                source: .opening,
                capturedAt: openReading.capturedAt,
                fiveHour: openReading.fiveHour,
                sevenDay: openReading.sevenDay,
                showFiveHourWhenZero: false
            ))
        }
        if let floatingReading {
            rows.append(DayUsageRow(
                source: .floating,
                capturedAt: floatingReading.capturedAt,
                fiveHour: floatingReading.fiveHour,
                sevenDay: floatingReading.sevenDay,
                showFiveHourWhenZero: true
            ))
        }
        if let closeReading {
            rows.append(DayUsageRow(
                source: .closing,
                capturedAt: closeReading.capturedAt,
                fiveHour: closeReading.fiveHour,
                sevenDay: closeReading.sevenDay,
                showFiveHourWhenZero: true
            ))
        }
        return rows.filter { row in
            visibleFiveHour(
                row.fiveHour,
                showFiveHourWhenZero: row.showFiveHourWhenZero
            ) != nil || meaningfulSevenDay(row.sevenDay) != nil
        }
    }

    /// Window after the start within which the "opening" reading is captured.
    private static let openingWindowSeconds: TimeInterval = 4 * 60
    /// Minimum age past the start before a current window's latest reading is
    /// shown as a floating row, keeping it clear of the opening annotation.
    private static let middleLeadSeconds: TimeInterval = 5 * 60

    /// The middle usage reading for the Day view. A current window shows its
    /// latest in-window reading once that reading is at least `middleLeadSeconds`
    /// past the start; a completed window marks the moment 5h first reached
    /// 100%. Future windows show nothing.
    private static func floatingReading(
        history: UsageHistorySeries?,
        isCurrent: Bool,
        isPast: Bool,
        shownStart: Date,
        shownEnd: Date,
        visibleStart: Date,
        usageAnchor: Date
    ) -> (capturedAt: Date, fiveHour: Double, sevenDay: Double?)? {
        if isCurrent {
            guard let latest = history?.usageReading(atOrBefore: usageAnchor, notBefore: visibleStart),
                  latest.capturedAt >= shownStart.addingTimeInterval(middleLeadSeconds)
            else { return nil }
            return latest
        }
        if isPast {
            return history?.firstFiveHourReaching(100, from: visibleStart, to: shownEnd)
        }
        return nil
    }

    private var effectiveSegmentStart: Date {
        segmentStart == .distantPast ? window.startAt : segmentStart
    }

    private var brandColor: Color {
        C5hColors.tintForProvider(window.providerID)
    }
}
