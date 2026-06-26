import SwiftUI
import C5hCore

struct PlannedWindowBlockView: View {
    let window: PlannedWindow
    var now: Date = .now
    let columnWidth: CGFloat
    let layout: CalendarLayoutConfig
    var visibleDurationSeconds: Int? = nil
    var clipsTop: Bool = false
    var clipsBottom: Bool = false
    var compact: Bool = false
    var displayStart: Date? = nil
    /// When true, the end-time corner label is rendered bold to match the start
    /// time. The Day view (Today/Tomorrow) sets this so every block time reads
    /// uniformly; the Week tab leaves it off.
    var emphasizeEndTime: Bool = false

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
        // Height uses the clipped visible duration, but the corner labels should
        // show the planned window's real bounds like actual-window blocks do.
        let shownEnd = shownStart.addingTimeInterval(TimeInterval(window.durationSeconds))

        ZStack {
            cornersOverlay(
                shownStart: shownStart,
                shownEnd: shownEnd,
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
        density: BlockDensity
    ) -> some View {
        // A minimal block shows only the top label. When it is the tail of a
        // window that began on a previous day (clipped at the top), the start
        // time is not on the displayed day, so show the end (the only boundary
        // that is) instead.
        let showsEndOnly = density == .minimal && clipsTop
        return VStack(spacing: 0) {
            cornerText(BlockFormatters.formatTime(showsEndOnly ? shownEnd : shownStart), weight: .semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            if density.showsBottomCorners {
                cornerText(BlockFormatters.formatTime(shownEnd), weight: emphasizeEndTime ? .semibold : .regular)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
