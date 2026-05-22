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

        let startSevenD: Double? = window.startAt > now
            ? nil
            : history?.sevenDayPercent(at: window.startAt)?.value
        let endSevenD: Double? = window.endAt > now
            ? nil
            : history?.sevenDayPercent(at: window.endAt)?.value
        let latest5h = history?.latestFiveHourPoint()

        ZStack {
            cornersOverlay(
                startSevenD: startSevenD,
                endSevenD: endSevenD,
                density: density
            )
            if density.showsCenter {
                centerOverlay(latest5h: latest5h, density: density)
            }
        }
        .padding(compact ? 3 : 6)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(shape.fill(brandColor))
        .clipShape(shape)
        .foregroundStyle(.white)
    }

    private func cornersOverlay(
        startSevenD: Double?,
        endSevenD: Double?,
        density: BlockDensity
    ) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                cornerText(BlockFormatters.formatTime(window.startAt), weight: .semibold)
                Spacer(minLength: 0)
                if let v = startSevenD {
                    cornerText(BlockFormatters.formatPercent(v), alignment: .trailing)
                }
            }
            Spacer(minLength: 0)
            if density.showsBottomCorners {
                HStack(alignment: .bottom) {
                    cornerText(BlockFormatters.formatTime(window.endAt))
                    Spacer(minLength: 0)
                    if let v = endSevenD {
                        cornerText(BlockFormatters.formatPercent(v), alignment: .trailing)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func centerOverlay(
        latest5h: (value: Double, asOf: Date)?,
        density: BlockDensity
    ) -> some View {
        VStack(spacing: 1) {
            if let p = latest5h {
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
            if density.showsDetailLine {
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
