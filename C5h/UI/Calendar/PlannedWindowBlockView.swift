import SwiftUI
import C5hCore

struct PlannedWindowBlockView: View {
    let window: PlannedWindow
    let history: UsageHistorySeries?
    var now: Date = .now
    let columnWidth: CGFloat
    let layout: CalendarLayoutConfig
    var visibleDurationSeconds: Int? = nil
    var clipsTop: Bool = false
    var clipsBottom: Bool = false
    var compact: Bool = false
    var displayStart: Date? = nil

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
        let width = compact ? columnWidth : columnWidth * layout.plannedBlockWidthRatio

        let shownStart = displayStart ?? window.startAt
        let shownEnd = shownStart.addingTimeInterval(TimeInterval(window.durationSeconds))
        let startSevenD: Double? = shownStart > now
            ? nil
            : history?.sevenDayPercent(at: shownStart)?.value
        let endSevenD: Double? = shownEnd > now
            ? nil
            : history?.sevenDayPercent(at: shownEnd)?.value

        ZStack {
            cornersOverlay(
                shownStart: shownStart,
                shownEnd: shownEnd,
                startSevenD: startSevenD,
                endSevenD: endSevenD,
                density: density
            )
            if density.showsCenter, density.showsDetailLine,
               let path = window.projectPath, !path.isEmpty {
                projectPathOverlay(path: path)
            }
        }
        .padding(compact ? 3 : 6)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(shape.fill(brandColor.opacity(0.22)))
        .overlay(shape.strokeBorder(brandColor.opacity(0.7), lineWidth: 1))
        .clipShape(shape)
    }

    private func cornersOverlay(
        shownStart: Date,
        shownEnd: Date,
        startSevenD: Double?,
        endSevenD: Double?,
        density: BlockDensity
    ) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                cornerText(BlockFormatters.formatTime(shownStart), weight: .semibold)
                Spacer(minLength: 0)
                if let v = startSevenD {
                    cornerText("7d \(BlockFormatters.formatPercent(v))", alignment: .trailing)
                }
            }
            Spacer(minLength: 0)
            if density.showsBottomCorners {
                HStack(alignment: .bottom) {
                    cornerText(BlockFormatters.formatTime(shownEnd))
                    Spacer(minLength: 0)
                    if let v = endSevenD {
                        cornerText("7d \(BlockFormatters.formatPercent(v))", alignment: .trailing)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func projectPathOverlay(path: String) -> some View {
        Text(path)
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
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
}
