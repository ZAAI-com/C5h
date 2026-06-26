import SwiftUI
import C5hCore

struct TimeRulerView: View {
    let layout: CalendarLayoutConfig
    var labelAlignment: HorizontalAlignment = .trailing
    /// When set, draws a red current-time label at the now-line, alongside the
    /// fixed hour labels.
    var now: Date? = nil

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
            if let now {
                Text(BlockFormatters.formatTime(now))
                    .font(C5hTypography.captionFont)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.red)
                    .frame(
                        width: layout.timeRulerWidth,
                        alignment: labelAlignment == .leading ? .leading : .trailing
                    )
                    .padding(labelAlignment == .leading ? .leading : .trailing, 6)
                    .offset(y: CalendarPositioning.yOffset(
                        for: now,
                        pixelsPerMinute: layout.pixelsPerMinute
                    ) - 6)
            }
        }
        .frame(width: layout.timeRulerWidth, height: layout.dayHeight, alignment: .topLeading)
        .background(.background)
    }

    private func yOffset(for hour: Int) -> CGFloat {
        CGFloat(hour) * 60 * layout.pixelsPerMinute - 6
    }

    private func label(for hour: Int) -> String {
        String(format: "%02d:00", hour)
    }
}
