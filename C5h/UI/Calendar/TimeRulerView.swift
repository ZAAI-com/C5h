import SwiftUI

struct TimeRulerView: View {
    let layout: CalendarLayoutConfig

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<25) { hour in
                Text(label(for: hour))
                    .font(C5hTypography.captionFont)
                    .foregroundStyle(C5hColors.fgTertiary)
                    .frame(width: layout.timeRulerWidth, alignment: .trailing)
                    .padding(.trailing, 6)
                    .offset(y: CGFloat(hour) * 60 * layout.pixelsPerMinute - 6)
            }
        }
        .frame(width: layout.timeRulerWidth, height: layout.dayHeight, alignment: .topLeading)
        .background(C5hColors.background)
    }

    private func label(for hour: Int) -> String {
        if hour == 24 { return "" }
        return String(format: "%02d:00", hour)
    }
}
