import SwiftUI

struct CalendarLayoutConfig: Sendable {
    var pixelsPerMinute: CGFloat = 0.85
    var timeRulerWidth: CGFloat = 72
    var providerMinWidth: CGFloat = 280
    var plannedBlockWidthRatio: CGFloat = 0.42
    var actualBlockWidthRatio: CGFloat = 0.84
    var blockCornerRadius: CGFloat = 10
    var hourLineOpacity: Double = 0.18

    var dayHeight: CGFloat { pixelsPerMinute * 24 * 60 }
}
