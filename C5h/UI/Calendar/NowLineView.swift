import SwiftUI

struct NowLineView: View {
    let layout: CalendarLayoutConfig

    var body: some View {
        Rectangle()
            .fill(.red.opacity(layout.nowLineOpacity))
            .frame(height: 1)
    }
}
