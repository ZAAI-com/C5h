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
    /// Display-only bounds used when a reset clips an earlier persisted window.
    /// Storage still keeps the provider-reported window; the calendar labels the
    /// segment users can see.
    var displayStart: Date? = nil
    var displayEnd: Date? = nil
    /// True only when `displayEnd` is a detected quota *reset* boundary; drives
    /// the neutral reset glyph at the end corner. A rolloff-clipped end (the limit
    /// went inactive with no reset) leaves this false.
    var marksResetEnd: Bool = false
    /// When true, the block uses the condensed Week-overview layout: a bold start
    /// time pinned top-left, with the 5h and 7d usage lines sitting directly above
    /// a bold end time at the bottom-left. The Day view (Today/Tomorrow) keeps the
    /// default full layout with start/end/current time-anchored usage readings.
    var condensed: Bool = false
    /// Explicit block width, used when overlapping windows are packed into lanes so
    /// each lane gets an equal slice. When `nil`, the block keeps its default width
    /// (`columnWidth * actualBlockWidthRatio`, or the full `columnWidth` when
    /// `compact`).
    var widthOverride: CGFloat? = nil
    /// When true, the window was derived from a detected quota reset (e.g. a Claude
    /// tier change reset the 5h window early). Marked with a subtle neutral glyph.
    var isReset: Bool = false

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
        let width = widthOverride ?? (compact ? columnWidth : columnWidth * layout.actualBlockWidthRatio)
        let pad: CGFloat = compact ? 3 : 6
        let contentWidth = max(0, width - 2 * pad)

        // Cross-midnight clipping keeps real bounds; reset clipping supplies
        // display bounds so the earlier window stops where the new one starts.
        let shownStart = displayStart ?? window.startAt
        let shownEnd = displayEnd ?? window.endAt
        let marksResetStart = isReset
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
        // Day view: a floating, time-anchored row. A current window shows the
        // latest reading once it is at least 5 min past the start; a completed
        // window marks the moment 5h first hit 100%.
        let floatingReading = Self.floatingReading(
            history: history,
            isCurrent: isCurrent,
            isPast: isPast,
            shownStart: shownStart,
            shownEnd: shownEnd,
            visibleStart: visibleStart,
            usageAnchor: usageAnchor
        )

        Group {
            if condensed {
                condensedOverlay(
                    shownStart: shownStart,
                    shownEnd: shownEnd,
                    marksResetStart: false,
                    marksResetEnd: false,
                    endSevenD: condensedSevenD,
                    fiveHour: condensed5h
                )
                .padding(pad)
            } else {
                ZStack(alignment: .topLeading) {
                    cornersOverlay(
                        shownStart: shownStart,
                        shownEnd: shownEnd,
                        marksResetStart: marksResetStart,
                        marksResetEnd: marksResetEnd,
                        openReading: openReading,
                        closeReading: closeReading,
                        contentWidth: contentWidth,
                        density: density
                    )
                    .padding(pad)
                    if density.showsCenter, let reading = floatingReading {
                        let cornerHeights = cornerRowsHeight(
                            openReading: openReading,
                            closeReading: closeReading,
                            density: density
                        )
                        usageRow(
                            reading: reading,
                            pad: pad,
                            contentWidth: contentWidth
                        )
                        .offset(y: usageRowOffset(
                            capturedAt: reading.capturedAt,
                            rowHeight: usageRowHeight(reading: reading, contentWidth: contentWidth),
                            height: height,
                            duration: duration,
                            pad: pad,
                            topReservedHeight: cornerHeights.top,
                            bottomReservedHeight: cornerHeights.bottom
                        ))
                    }
                }
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .background {
            ZStack(alignment: .top) {
                shape.fill(brandColor)
                shape.strokeBorder(Color.white.opacity(0.9), lineWidth: 1)
                    .allowsHitTesting(false)
                nowLine(height: height)
            }
        }
        .clipShape(shape)
        .foregroundStyle(.white)
    }

    /// The red current-time line, drawn in the block's background layer so it sits
    /// above the colored fill and border but behind the white text. Shown only
    /// while `now` falls within the block's visible vertical span, which happens
    /// only on the day rendered as today.
    @ViewBuilder
    private func nowLine(height: CGFloat) -> some View {
        // `yOffset` is time-of-day only, so without a day guard a block on a
        // non-today column (Week view, or a navigated Day) whose clock-time span
        // contains the current time would draw a stray red line. Mirror the
        // column-level guard in ProviderColumnView.
        if Calendar.current.isDate(effectiveSegmentStart, inSameDayAs: now) {
            let ppm = layout.pixelsPerMinute
            let top = CalendarPositioning.yOffset(for: effectiveSegmentStart, pixelsPerMinute: ppm)
            let y = CalendarPositioning.yOffset(for: now, pixelsPerMinute: ppm) - top
            if y >= 0, y <= height {
                Rectangle()
                    .fill(Color.red)
                    .frame(height: 1)
                    .offset(y: y)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Subtle, neutral marker for a quota reset boundary. Deliberately plain (no
    /// plan name, no text) so it reads as a reset indicator only.
    private var resetGlyph: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: compact ? 8 : 9, weight: .semibold))
            .foregroundStyle(.white.opacity(0.7))
            .allowsHitTesting(false)
    }

    /// Start time pinned top-left and end time bottom-left, with any boundary
    /// usage readings stacked below their time labels.
    private func cornersOverlay(
        shownStart: Date,
        shownEnd: Date,
        marksResetStart: Bool,
        marksResetEnd: Bool,
        openReading: (capturedAt: Date, fiveHour: Double?, sevenDay: Double?)?,
        closeReading: (capturedAt: Date, fiveHour: Double, sevenDay: Double?)?,
        contentWidth: CGFloat,
        density: BlockDensity
    ) -> some View {
        // A minimal block shows only this top label. When it is the tail of a
        // window that began on a previous day (clipped at the top), the start
        // time is not on the displayed day, so show the end (the only boundary
        // that is) instead.
        let showsEndOnly = density == .minimal && clipsTop
        return VStack(spacing: 0) {
            usageReadingRow(
                timeText: BlockFormatters.formatTime(showsEndOnly ? shownEnd : shownStart),
                showsResetGlyph: showsEndOnly ? marksResetEnd : marksResetStart,
                fiveHour: density.showsBottomCorners ? openReading?.fiveHour : nil,
                sevenDay: density.showsBottomCorners ? openReading?.sevenDay : nil,
                showFiveHourWhenZero: false,
                contentWidth: contentWidth
            )
            Spacer(minLength: 0)
            if density.showsBottomCorners {
                usageReadingRow(
                    timeText: BlockFormatters.formatTime(shownEnd),
                    showsResetGlyph: marksResetEnd,
                    fiveHour: closeReading?.fiveHour,
                    sevenDay: closeReading?.sevenDay,
                    showFiveHourWhenZero: true,
                    contentWidth: contentWidth
                )
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Week overview: bold start time pinned top-left, then the 5h and 7d usage
    /// lines sitting directly above a bold end time at the bottom-left.
    private func condensedOverlay(
        shownStart: Date,
        shownEnd: Date,
        marksResetStart: Bool,
        marksResetEnd: Bool,
        endSevenD: Double?,
        fiveHour: (value: Double, asOf: Date)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            timeLabel(
                BlockFormatters.formatTime(shownStart),
                weight: .bold,
                showsResetGlyph: marksResetStart
            )
            Spacer(minLength: 0)
            if let p = fiveHour {
                cornerText("5h \(BlockFormatters.formatPercent(p.value))")
            }
            if let v = endSevenD {
                cornerText("7d \(BlockFormatters.formatPercent(v))")
            }
            timeLabel(
                BlockFormatters.formatTime(shownEnd),
                weight: .bold,
                showsResetGlyph: marksResetEnd
            )
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

    private func timeLabel(
        _ string: String,
        weight: Font.Weight = .regular,
        showsResetGlyph: Bool
    ) -> some View {
        HStack(spacing: compact ? 2 : 3) {
            cornerText(string, weight: weight)
            if showsResetGlyph {
                resetGlyph
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    /// Estimated line height of a reading label, used to clamp it inside the
    /// block and clear of the start/end corner times.
    private var labelLineHeight: CGFloat { compact ? 12 : 14 }

    private var usageFontSize: CGFloat { compact ? 9 : 10 }

    /// Day view row: time first, then each available usage metric on its own
    /// line. This keeps 5h and 7d readings readable at every column width.
    private func usageReadingRow(
        timeText: String,
        showsResetGlyph: Bool = false,
        fiveHour: Double?,
        sevenDay: Double?,
        showFiveHourWhenZero: Bool,
        contentWidth: CGFloat
    ) -> some View {
        let five = Self.visibleFiveHour(
            fiveHour,
            showFiveHourWhenZero: showFiveHourWhenZero
        )
        let seven = Self.meaningfulSevenDay(sevenDay)
        return VStack(alignment: .leading, spacing: 0) {
            timeLabel(
                timeText,
                weight: .semibold,
                showsResetGlyph: showsResetGlyph
            )
            if let five {
                usageMetricLabel("5h usage", value: five)
            }
            if let seven {
                usageMetricLabel("7d usage", value: seven)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: contentWidth, alignment: .leading)
    }

    private func usageLineCount(fiveHour: Double?, sevenDay: Double?, showFiveHourWhenZero: Bool) -> Int {
        let five = Self.visibleFiveHour(
            fiveHour,
            showFiveHourWhenZero: showFiveHourWhenZero
        )
        let seven = Self.meaningfulSevenDay(sevenDay)
        return 1 + (five != nil ? 1 : 0) + (seven != nil ? 1 : 0)
    }

    private func usageRowHeight(
        fiveHour: Double?,
        sevenDay: Double?,
        showFiveHourWhenZero: Bool
    ) -> CGFloat {
        labelLineHeight * CGFloat(usageLineCount(
            fiveHour: fiveHour,
            sevenDay: sevenDay,
            showFiveHourWhenZero: showFiveHourWhenZero
        ))
    }

    private func cornerRowsHeight(
        openReading: (capturedAt: Date, fiveHour: Double?, sevenDay: Double?)?,
        closeReading: (capturedAt: Date, fiveHour: Double, sevenDay: Double?)?,
        density: BlockDensity
    ) -> (top: CGFloat, bottom: CGFloat) {
        guard density.showsBottomCorners else {
            return (labelLineHeight, 0)
        }
        return (
            usageRowHeight(
                fiveHour: openReading?.fiveHour,
                sevenDay: openReading?.sevenDay,
                showFiveHourWhenZero: false
            ),
            usageRowHeight(
                fiveHour: closeReading?.fiveHour,
                sevenDay: closeReading?.sevenDay,
                showFiveHourWhenZero: true
            )
        )
    }

    /// Day view: one time-anchored usage row. The reading's captured time stays
    /// above the separate 5h/7d usage lines.
    private func usageRow(
        reading: (capturedAt: Date, fiveHour: Double, sevenDay: Double?),
        pad: CGFloat,
        contentWidth: CGFloat
    ) -> some View {
        usageReadingRow(
            timeText: BlockFormatters.formatTime(reading.capturedAt),
            showsResetGlyph: false,
            fiveHour: reading.fiveHour,
            sevenDay: reading.sevenDay,
            showFiveHourWhenZero: true,
            contentWidth: contentWidth
        )
        .padding(.horizontal, pad)
    }

    /// Rendered height of the floating usage row.
    private func usageRowHeight(
        reading: (capturedAt: Date, fiveHour: Double, sevenDay: Double?),
        contentWidth: CGFloat
    ) -> CGFloat {
        usageRowHeight(
            fiveHour: reading.fiveHour,
            sevenDay: reading.sevenDay,
            showFiveHourWhenZero: true
        )
    }

    /// Vertical offset (from the block's top edge) that places a reading row so
    /// its center sits at `asOf` on the time scale, clamped to stay inside the
    /// block and clear of the start (top) and end (bottom) corner rows.
    /// `rowHeight` is the row's rendered height.
    private func anchoredOffset(
        forAsOf asOf: Date,
        height: CGFloat,
        rowHeight: CGFloat,
        pad: CGFloat,
        topReservedHeight: CGFloat,
        bottomReservedHeight: CGFloat
    ) -> CGFloat {
        let ppm = layout.pixelsPerMinute
        let top = CalendarPositioning.yOffset(for: effectiveSegmentStart, pixelsPerMinute: ppm)
        let raw = CalendarPositioning.yOffset(for: asOf, pixelsPerMinute: ppm) - top
        let minOffset = pad + topReservedHeight
        let maxOffset = max(minOffset, height - pad - bottomReservedHeight - rowHeight)
        return min(max(raw - rowHeight / 2, minOffset), maxOffset)
    }

    /// Like `anchoredOffset`, but for the in-progress window (one that contains
    /// `now`) nudges the usage row above the red now-line when possible, falling
    /// below only when the upper side has no room.
    private func usageRowOffset(
        capturedAt: Date,
        rowHeight: CGFloat,
        height: CGFloat,
        duration: Int,
        pad: CGFloat,
        topReservedHeight: CGFloat,
        bottomReservedHeight: CGFloat
    ) -> CGFloat {
        let offset = anchoredOffset(
            forAsOf: capturedAt,
            height: height,
            rowHeight: rowHeight,
            pad: pad,
            topReservedHeight: topReservedHeight,
            bottomReservedHeight: bottomReservedHeight
        )
        let visibleStart = effectiveSegmentStart
        let segmentEnd = visibleStart.addingTimeInterval(TimeInterval(duration))
        guard visibleStart <= now, now < segmentEnd else { return offset }
        let ppm = layout.pixelsPerMinute
        let top = CalendarPositioning.yOffset(for: visibleStart, pixelsPerMinute: ppm)
        let nowY = CalendarPositioning.yOffset(for: now, pixelsPerMinute: ppm) - top
        let gap: CGFloat = 4
        let straddles = offset < nowY + gap && offset + rowHeight > nowY - gap
        guard straddles else { return offset }
        let minOffset = pad + topReservedHeight
        let maxOffset = max(minOffset, height - pad - bottomReservedHeight - rowHeight)
        let above = nowY - rowHeight - gap
        if above >= minOffset {
            return above
        }
        let below = nowY + gap
        if below <= maxOffset {
            return below
        }
        return min(max(offset, minOffset), maxOffset)
    }

    /// Returns the 7d value whenever the snapshot carried one, including readings
    /// that round to 0%. Only a missing reading (`nil`, i.e. the provider
    /// reported no 7d window) is hidden, so we never fabricate a `7d usage 0%`
    /// from absent data.
    private static func meaningfulSevenDay(_ value: Double?) -> Double? {
        value
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

    private static func visibleFiveHour(
        _ value: Double?,
        showFiveHourWhenZero: Bool
    ) -> Double? {
        guard let value else { return nil }
        if showFiveHourWhenZero { return value }
        return value.rounded() >= 1 ? value : nil
    }

    /// Window after the start within which the "opening" reading is captured.
    private static let openingWindowSeconds: TimeInterval = 4 * 60
    /// Minimum age past the start before a current window's latest reading is
    /// shown as a floating row, keeping it clear of the opening annotation.
    private static let middleLeadSeconds: TimeInterval = 5 * 60

    /// The floating, time-anchored reading for the Day view. A current window
    /// that has hit 100% freezes at the moment 5h first reached 100%; while still
    /// below 100% it shows its latest in-window reading once that reading is at
    /// least `middleLeadSeconds` past the start. A completed window marks the
    /// moment 5h first reached 100%. Future windows show nothing.
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
            // Once the cap is hit, freeze the row at the first 100% moment so it
            // stops sliding to each new poll. Below 100%, keep showing the live
            // latest reading.
            if let hit = history?.firstFiveHourReaching(100, from: visibleStart, to: usageAnchor) {
                return hit
            }
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
