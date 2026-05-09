import SwiftUI
import C5hCore

struct PlannedWindowBlockView: View {
    let window: PlannedWindow
    let columnWidth: CGFloat
    let layout: CalendarLayoutConfig

    var body: some View {
        let height = CalendarPositioning.blockHeight(
            durationSeconds: window.durationSeconds,
            pixelsPerMinute: layout.pixelsPerMinute
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
        .background(
            RoundedRectangle(cornerRadius: layout.blockCornerRadius, style: .continuous)
                .fill(brandColor.opacity(0.18))
        )
        .overlay {
            RoundedRectangle(cornerRadius: layout.blockCornerRadius, style: .continuous)
                .strokeBorder(brandColor.opacity(0.7), lineWidth: 1)
        }
    }

    private var brandColor: Color {
        window.providerID == .claude ? ProviderBrandColor.claude : ProviderBrandColor.codex
    }

    private var timeRange: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return "\(f.string(from: window.startAt))–\(f.string(from: window.endAt))"
    }
}
