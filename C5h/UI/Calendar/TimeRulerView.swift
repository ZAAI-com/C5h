import SwiftUI

struct TimeRulerView: View {
    let layout: CalendarLayoutConfig
    var labelAlignment: HorizontalAlignment = .trailing

    private static let labeledHours = [0, 3, 6, 9, 12, 15, 18, 21, 24]

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
                    .offset(y: yOffset(for: hour))
            }
        }
        .frame(width: layout.timeRulerWidth, height: layout.dayHeight, alignment: .topLeading)
        .background(.background)
    }

    private func yOffset(for hour: Int) -> CGFloat {
        // Keep the 00:00 and 24:00 labels inside the ruler frame; centre the rest on their line.
        let lineY = CGFloat(hour) * 60 * layout.pixelsPerMinute
        switch hour {
        case 0: return lineY
        case 24: return lineY - 14
        default: return lineY - 6
        }
    }

    private func label(for hour: Int) -> String {
        String(format: "%02d:00", hour)
    }
}
