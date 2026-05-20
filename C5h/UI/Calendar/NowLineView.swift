import SwiftUI

struct NowLineView: View {
    let layout: CalendarLayoutConfig

    var body: some View {
        Rectangle()
            .fill(.red.opacity(layout.nowLineOpacity))
            .frame(height: 1)
            .overlay(alignment: .leading) {
                Circle().fill(.red).frame(width: 6, height: 6).offset(x: -3)
            }
    }
}
