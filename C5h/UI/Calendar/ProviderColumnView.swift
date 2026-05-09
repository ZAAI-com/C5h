import SwiftUI
import C5hCore

struct ProviderColumnView: View {
    let providerID: ProviderID
    let plannedWindows: [PlannedWindow]
    let actualWindows: [ActualWindow]
    let date: Date
    let now: Date
    let layout: CalendarLayoutConfig
    let columnWidth: CGFloat
    let onSelectPlanned: (PlannedWindow) -> Void
    let onSelectActual: (ActualWindow) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            ForEach(plannedWindows) { window in
                Button {
                    onSelectPlanned(window)
                } label: {
                    PlannedWindowBlockView(
                        window: window,
                        columnWidth: columnWidth,
                        layout: layout
                    )
                }
                .buttonStyle(.plain)
                .offset(y: yOffset(for: window.startAt))
                .padding(.leading, 2)
            }
            ForEach(actualWindows) { window in
                Button {
                    onSelectActual(window)
                } label: {
                    ActualWindowBlockView(
                        window: window,
                        columnWidth: columnWidth,
                        layout: layout
                    )
                }
                .buttonStyle(.plain)
                .offset(
                    x: columnWidth * (1 - layout.actualBlockWidthRatio) - 2,
                    y: yOffset(for: window.startAt)
                )
            }
            if Calendar.current.isDate(now, inSameDayAs: date) {
                NowLineView(layout: layout)
                    .frame(width: columnWidth)
                    .offset(y: yOffset(for: now))
            }
        }
        .frame(width: columnWidth, height: layout.dayHeight, alignment: .topLeading)
    }

    private var background: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(C5hColors.background)
            ForEach(0..<24) { hour in
                Rectangle()
                    .fill(C5hColors.fgTertiary.opacity(layout.hourLineOpacity))
                    .frame(height: 1)
                    .offset(y: CGFloat(hour) * 60 * layout.pixelsPerMinute)
            }
        }
    }

    private func yOffset(for date: Date) -> CGFloat {
        CalendarPositioning.yOffset(for: date, pixelsPerMinute: layout.pixelsPerMinute)
    }
}
