import SwiftUI
import C5hCore

struct ActualWindowBlockView: View {
    let window: ActualWindow
    let columnWidth: CGFloat
    let layout: CalendarLayoutConfig

    var body: some View {
        let height = CalendarPositioning.blockHeight(
            durationSeconds: window.durationSeconds,
            pixelsPerMinute: layout.pixelsPerMinute
        )
        VStack(alignment: .leading, spacing: 2) {
            Text(timeRange)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
            Text(sourceLabel)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
            Text(confidenceLabel)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(width: columnWidth * layout.actualBlockWidthRatio, height: height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: layout.blockCornerRadius, style: .continuous)
                .fill(brandColor)
        )
        .clipped()
    }

    private var brandColor: Color {
        C5hColors.tintForProvider(window.providerID)
    }

    private var timeRange: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return "\(f.string(from: window.startAt))–\(f.string(from: window.endAt))"
    }

    private var sourceLabel: String {
        switch window.source {
        case .c5hTriggered: "from \(window.providerID.displayName) CLI (triggered)"
        case .detectedFromUsage: "from \(window.providerID.displayName) CLI"
        case .manual: "manual"
        }
    }

    private var confidenceLabel: String {
        switch window.confidence {
        case .exact: "start: exact"
        case .estimated: "start: estimated"
        }
    }
}
