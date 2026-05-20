import Foundation
import Testing
@testable import C5hCore

@Suite("CalendarPositioning")
struct CalendarPositioningTests {
    @Test("Midnight is 0 minutes since start of day")
    func midnight() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: 2026, month: 5, day: 9))!
        #expect(CalendarPositioning.minutesSinceStartOfDay(date, calendar: cal) == 0)
    }

    @Test("9:30 is 570 minutes")
    func nineThirty() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: 2026, month: 5, day: 9, hour: 9, minute: 30))!
        #expect(CalendarPositioning.minutesSinceStartOfDay(date, calendar: cal) == 570)
    }

    @Test("yOffset multiplies by pixelsPerMinute")
    func yOffset() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: 2026, month: 5, day: 9, hour: 1))!
        let y = CalendarPositioning.yOffset(for: date, pixelsPerMinute: 0.85, calendar: cal)
        #expect(abs(y - (60.0 * 0.85)) < 0.001)
    }

    @Test("blockHeight with 5h duration at 0.85 px/min ≈ 255 px")
    func blockHeight5h() {
        let h = CalendarPositioning.blockHeight(
            durationSeconds: 5 * 3600,
            pixelsPerMinute: 0.85
        )
        #expect(abs(h - 255.0) < 0.001)
    }

    @Test("blockHeight enforces minimum")
    func minimumHeight() {
        let h = CalendarPositioning.blockHeight(
            durationSeconds: 60,
            pixelsPerMinute: 0.85,
            minimum: 24
        )
        #expect(h == 24)
    }

    @Test("dayInterval covers 24 hours")
    func dayInterval() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: 2026, month: 5, day: 9, hour: 14))!
        let interval = CalendarPositioning.dayInterval(for: date, calendar: cal)
        #expect(interval.duration == 86_400)
    }
}
