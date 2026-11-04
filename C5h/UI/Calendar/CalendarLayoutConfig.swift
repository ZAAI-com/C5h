import SwiftUI

struct CalendarLayoutConfig: Sendable {
    var pixelsPerMinute: CGFloat = 0.85
    var timeRulerWidth: CGFloat = 72
    var providerMinWidth: CGFloat = 280
    var plannedBlockWidthRatio: CGFloat = 0.42
    var actualBlockWidthRatio: CGFloat = 0.84
    var blockCornerRadius: CGFloat = 10
    var blockVerticalGap: CGFloat = 4
    var hourLineOpacity: Double = 0.18

    var dayHeight: CGFloat { pixelsPerMinute * 24 * 60 }
}

/// UserDefaults keys for calendar display filters shared by the Day and Week
/// screens, so a toggle on one screen applies to the others and survives a
/// relaunch.
enum CalendarDisplayKeys {
    static let showWeeklyWindows = "calendar.showWeeklyWindows"
}
