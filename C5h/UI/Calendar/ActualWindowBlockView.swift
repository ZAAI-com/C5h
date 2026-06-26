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
    /// default full layout with start/end corners and time-anchored 5h (left) and
    /// 7d (right) readings.
    var condensed: Bool = false

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
                    endSevenD: condensedSevenD,
                    fiveHour: condensed5h
                )
                .padding(pad)
            } else {
                ZStack(alignment: .topLeading) {
                    cornersOverlay(
                        shownStart: shownStart,
                        shownEnd: shownEnd,
                        openReading: openReading,
                        closeReading: closeReading,
                        density: density
                    )
                    .padding(pad)
                    if density.showsCenter, let reading = floatingReading {
                        usageRow(
                            reading: reading,
                            pad: pad
                        )
                        .offset(y: usageRowOffset(
                            capturedAt: reading.capturedAt,
                            height: height,
                            duration: duration,
                            pad: pad
                        ))
                    }
                }
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .background(shape.fill(brandColor))
        .clipShape(shape)
        .foregroundStyle(.white)
    }

    /// Start time pinned top-left and end time bottom-left, each with its
    /// boundary usage reading right-aligned on the same row: the "opening" 7d
    /// (plus 5h when non-zero) beside the start, and the "closing" 5h + 7d beside
    /// the end. Annotations only render once the block is tall enough to show
    /// both corner times.
    private func cornersOverlay(
        shownStart: Date,
        shownEnd: Date,
        openReading: (capturedAt: Date, fiveHour: Double?, sevenDay: Double?)?,
        closeReading: (capturedAt: Date, fiveHour: Double, sevenDay: Double?)?,
        density: BlockDensity
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                cornerText(BlockFormatters.formatTime(shownStart), weight: .semibold)
                if density.showsBottomCorners, let openReading {
                    Spacer(minLength: 8)
                    cornerUsage(
                        fiveHour: openReading.fiveHour,
                        sevenDay: openReading.sevenDay,
                        showFiveHourWhenZero: false
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            if density.showsBottomCorners {
                HStack(spacing: 6) {
                    cornerText(BlockFormatters.formatTime(shownEnd), weight: .semibold)
                    if let closeReading {
                        Spacer(minLength: 8)
                        cornerUsage(
                            fiveHour: closeReading.fiveHour,
                            sevenDay: closeReading.sevenDay,
                            showFiveHourWhenZero: true
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// A boundary usage annotation (`5h usage X%` and/or `7d usage Y%`) shown
    /// beside a corner time. The 7d value is hidden when it rounds to 0% (see
    /// `meaningfulSevenDay`). The 5h value is hidden at 0% only when
    /// `showFiveHourWhenZero` is false (the opening reading); the closing reading
    /// always shows 5h.
    private func cornerUsage(
        fiveHour: Double?,
        sevenDay: Double?,
        showFiveHourWhenZero: Bool
    ) -> some View {
        let five: Double? = {
            guard let fiveHour else { return nil }
            if showFiveHourWhenZero { return fiveHour }
            return fiveHour.rounded() >= 1 ? fiveHour : nil
        }()
        let seven = Self.meaningfulSevenDay(sevenDay)
        return HStack(spacing: 6) {
            if let five {
                usageLabel("5h usage \(BlockFormatters.formatPercent(five))")
            }
            if let seven {
                usageLabel("7d usage \(BlockFormatters.formatPercent(seven))")
            }
        }
    }

    /// Day view: one usage row, with the 5h reading on the left and the 7d
    /// reading from the same snapshot on the right when it is meaningful.
    private func usageRow(
        reading: (capturedAt: Date, fiveHour: Double, sevenDay: Double?),
        pad: CGFloat
    ) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                usageLabel(BlockFormatters.formatTime(reading.capturedAt))
                usageLabel("5h usage \(BlockFormatters.formatPercent(reading.fiveHour))")
            }
            Spacer(minLength: 8)
            if let sevenDay = Self.meaningfulSevenDay(reading.sevenDay) {
                usageLabel("7d usage \(BlockFormatters.formatPercent(sevenDay))")
            }
        }
        .padding(.horizontal, pad)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A usage label rendered in the shared reading style (semibold, monospaced
    /// digits), used by both the floating row and the corner annotations.
    private func usageLabel(_ string: String) -> Text {
        Text(string)
            .font(.system(size: compact ? 9 : 10, weight: .semibold))
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

    /// Estimated line height of a reading label, used to clamp it inside the
    /// block and clear of the start/end corner times.
    private var labelLineHeight: CGFloat { compact ? 12 : 14 }

    /// Vertical offset (from the block's top edge) that places a reading label so
    /// its center sits at `asOf` on the time scale, clamped to stay inside the
    /// block and clear of the start (top) and end (bottom) corner times.
    private func anchoredOffset(
        forAsOf asOf: Date,
        height: CGFloat,
        pad: CGFloat
    ) -> CGFloat {
        let ppm = layout.pixelsPerMinute
        let top = CalendarPositioning.yOffset(for: effectiveSegmentStart, pixelsPerMinute: ppm)
        let raw = CalendarPositioning.yOffset(for: asOf, pixelsPerMinute: ppm) - top
        let h = labelLineHeight
        let minOffset = pad + h
        let maxOffset = max(minOffset, height - pad - 2 * h)
        return min(max(raw - h / 2, minOffset), maxOffset)
    }

    /// Like `anchoredOffset`, but for the in-progress window (one that contains
    /// `now`) nudges the usage row above the red now-line when possible, falling
    /// below only when the upper side has no room.
    private func usageRowOffset(
        capturedAt: Date,
        height: CGFloat,
        duration: Int,
        pad: CGFloat
    ) -> CGFloat {
        let offset = anchoredOffset(forAsOf: capturedAt, height: height, pad: pad)
        let visibleStart = effectiveSegmentStart
        let segmentEnd = visibleStart.addingTimeInterval(TimeInterval(duration))
        guard visibleStart <= now, now < segmentEnd else { return offset }
        let ppm = layout.pixelsPerMinute
        let top = CalendarPositioning.yOffset(for: visibleStart, pixelsPerMinute: ppm)
        let nowY = CalendarPositioning.yOffset(for: now, pixelsPerMinute: ppm) - top
        let h = labelLineHeight
        let gap: CGFloat = 4
        let straddles = offset < nowY + gap && offset + h > nowY - gap
        guard straddles else { return offset }
        let minOffset = pad + h
        let maxOffset = max(minOffset, height - pad - 2 * h)
        let above = nowY - h - gap
        if above >= minOffset {
            return above
        }
        let below = nowY + gap
        if below <= maxOffset {
            return below
        }
        return min(max(offset, minOffset), maxOffset)
    }

    /// Returns the 7d value only when there is enough data to be worth showing.
    /// A missing reading (`nil`) or one that rounds to 0% is treated as "not
    /// enough data" and hidden, so tiles don't render a meaningless `7d usage 0%`.
    private static func meaningfulSevenDay(_ value: Double?) -> Double? {
        guard let value, value.rounded() >= 1 else { return nil }
        return value
    }

    /// Window after the start within which the "opening" reading is captured.
    private static let openingWindowSeconds: TimeInterval = 4 * 60
    /// Minimum age past the start before a current window's latest reading is
    /// shown as a floating row, keeping it clear of the opening annotation.
    private static let middleLeadSeconds: TimeInterval = 5 * 60

    /// The floating, time-anchored reading for the Day view. A current window
    /// shows its latest in-window reading once that reading is at least
    /// `middleLeadSeconds` past the start; a completed window marks the moment 5h
    /// first reached 100%. Future windows show nothing.
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
