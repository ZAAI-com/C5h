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
    /// When true, the block uses the condensed Week-overview layout: start time,
    /// 7d usage, and 5h usage stacked top-left. The Day view (Today/Tomorrow)
    /// keeps the default full layout with start/end corners and time-anchored
    /// 5h (left) and 7d (right) readings.
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
        // The 7d reading and the time it was captured, anchored to the window
        // end. Hidden for windows whose end is still in the future, matching the
        // 5h guard below.
        let sevenD = shownEnd > now
            ? nil
            : Self.meaningfulSevenDay(history?.sevenDayPercent(at: shownEnd))
        // Anchor the 5h reading to this window's own time (capped at `now` so an
        // in-progress window still shows the current value); hide for windows
        // that start in the future, matching the 7d guard above.
        let fiveHourAnchor = min(shownEnd, now)
        let windowed5h: (value: Double, asOf: Date)? = shownStart > now
            ? nil
            : history?.fiveHourPercent(at: fiveHourAnchor)

        Group {
            if condensed {
                condensedOverlay(
                    shownStart: shownStart,
                    endSevenD: sevenD?.value,
                    fiveHour: windowed5h
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
                    if density.showsCenter {
                        if let p = windowed5h {
                            anchoredLabel(
                                time: p.asOf,
                                text: "5h usage \(BlockFormatters.formatPercent(p.value))",
                                leading: true,
                                pad: pad
                            )
                            .offset(y: fiveHourOffset(
                                asOf: p.asOf,
                                height: height,
                                duration: duration,
                                pad: pad
                            ))
                        }
                        if let s = sevenD {
                            anchoredLabel(
                                time: s.asOf,
                                text: "7d usage \(BlockFormatters.formatPercent(s.value))",
                                leading: false,
                                pad: pad
                            )
                            .offset(y: anchoredOffset(
                                forAsOf: s.asOf,
                                height: height,
                                pad: pad
                            ))
                        }
                    }
                }
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .background(shape.fill(brandColor))
        .clipShape(shape)
        .foregroundStyle(.white)
    }

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
                cornerText(BlockFormatters.formatTime(shownEnd))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Day view: a usage reading pinned to the left (5h) or right (7d) edge,
    /// showing the capture time next to the reading. Positioned vertically by
    /// the caller via `.offset` so the reading sits at its time on the scale.
    private func anchoredLabel(
        time: Date,
        text: String,
        leading: Bool,
        pad: CGFloat
    ) -> some View {
        let timeText = Text(BlockFormatters.formatTime(time))
            .font(.system(size: compact ? 9 : 10))
            .monospacedDigit()
            .opacity(0.85)
        let mainText = Text(text)
            .font(.system(size: compact ? 9 : 10, weight: .semibold))
            .monospacedDigit()
        return HStack(spacing: 6) {
            if leading {
                timeText
                mainText
            } else {
                mainText
                timeText
            }
        }
        .fixedSize()
        .padding(.horizontal, pad)
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
    }

    /// Week overview: only start time, end 7d usage, and 5h usage, stacked
    /// top-left to stay legible in the dense tiles.
    private func condensedOverlay(
        shownStart: Date,
        endSevenD: Double?,
        fiveHour: (value: Double, asOf: Date)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            cornerText(BlockFormatters.formatTime(shownStart), weight: .semibold)
            if let v = endSevenD {
                cornerText("7d \(BlockFormatters.formatPercent(v))")
            }
            if let p = fiveHour {
                cornerText("5h \(BlockFormatters.formatPercent(p.value))")
            }
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
        let top = CalendarPositioning.yOffset(for: segmentStart, pixelsPerMinute: ppm)
        let raw = CalendarPositioning.yOffset(for: asOf, pixelsPerMinute: ppm) - top
        let h = labelLineHeight
        let minOffset = pad + h
        let maxOffset = max(minOffset, height - pad - 2 * h)
        return min(max(raw - h / 2, minOffset), maxOffset)
    }

    /// Like `anchoredOffset`, but for the in-progress window (one that contains
    /// `now`) nudges the 5h label off the red now-line to whichever side has
    /// more vertical room, so the reading never sits on top of the line.
    private func fiveHourOffset(
        asOf: Date,
        height: CGFloat,
        duration: Int,
        pad: CGFloat
    ) -> CGFloat {
        let offset = anchoredOffset(forAsOf: asOf, height: height, pad: pad)
        let segmentEnd = segmentStart.addingTimeInterval(TimeInterval(duration))
        guard segmentStart <= now, now < segmentEnd else { return offset }
        let ppm = layout.pixelsPerMinute
        let top = CalendarPositioning.yOffset(for: segmentStart, pixelsPerMinute: ppm)
        let nowY = CalendarPositioning.yOffset(for: now, pixelsPerMinute: ppm) - top
        let h = labelLineHeight
        let gap: CGFloat = 4
        let straddles = offset < nowY + gap && offset + h > nowY - gap
        guard straddles else { return offset }
        let minOffset = pad + h
        let maxOffset = max(minOffset, height - pad - 2 * h)
        if (height - nowY) >= nowY {
            return min(nowY + gap, maxOffset)
        }
        return max(nowY - h - gap, minOffset)
    }

    /// Returns the 7d reading only when there is enough data to be worth showing.
    /// A missing reading (`nil`) or one that rounds to 0% is treated as "not
    /// enough data" and hidden, so tiles don't render a meaningless `7d usage 0%`.
    private static func meaningfulSevenDay(
        _ reading: (value: Double, asOf: Date)?
    ) -> (value: Double, asOf: Date)? {
        guard let reading, reading.value.rounded() >= 1 else { return nil }
        return reading
    }

    private var brandColor: Color {
        C5hColors.tintForProvider(window.providerID)
    }
}
