import SwiftUI
import C5hCore

struct PlannedWindowBlockView: View {
    let window: PlannedWindow
    let columnWidth: CGFloat
    let layout: CalendarLayoutConfig
    var visibleDurationSeconds: Int? = nil
    var clipsTop: Bool = false
    var clipsBottom: Bool = false

    var body: some View {
        let duration = visibleDurationSeconds ?? window.durationSeconds
        let height = CalendarPositioning.blockHeight(
            durationSeconds: duration,
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
        VStack(alignment: .leading, spacing: 2) {
            Text(timeRange).font(.system(size: 10, weight: .semibold))
            Text("Planned · \(window.status.rawValue)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let path = window.projectPath {
                Text(path).font(.system(size: 10))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(width: columnWidth * layout.plannedBlockWidthRatio, height: height, alignment: .topLeading)
        .background(shape.fill(brandColor.opacity(0.22)))
        .overlay(shape.strokeBorder(brandColor.opacity(0.7), lineWidth: 1))
        .clipShape(shape)
    }

    private var brandColor: Color {
        C5hColors.tintForProvider(window.providerID)
    }

    private var timeRange: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return "\(f.string(from: window.startAt))–\(f.string(from: window.endAt))"
    }
}
