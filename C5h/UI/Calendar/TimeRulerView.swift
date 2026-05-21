import SwiftUI

struct TimeRulerView: View {
    let layout: CalendarLayoutConfig
    var labelAlignment: HorizontalAlignment = .trailing

    private static let labeledHours = [3, 6, 9, 12, 15, 18, 21]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Self.labeledHours, id: \.self) { hour in
                Text(label(for: hour))
                    .font(C5hTypography.captionFont)
                    .foregroundStyle(C5hColors.fgTertiary)
                    .frame(
                        width: layout.timeRulerWidth,
                        alignment: labelAlignment == .leading ? .leading : .trailing
                    )
                    .padding(labelAlignment == .leading ? .leading : .trailing, 6)
                    .offset(y: CGFloat(hour) * 60 * layout.pixelsPerMinute - 6)
            }
        }
        .frame(width: layout.timeRulerWidth, height: layout.dayHeight, alignment: .topLeading)
        .background(.background)
    }

    private func label(for hour: Int) -> String {
        String(format: "%02d:00", hour)
    }
}
