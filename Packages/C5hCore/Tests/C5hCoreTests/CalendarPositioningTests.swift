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

    @Test("visibleSegment fully inside day")
    func visibleSegmentInside() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let day = cal.date(from: DateComponents(year: 2026, month: 5, day: 9))!
        let start = cal.date(from: DateComponents(year: 2026, month: 5, day: 9, hour: 9))!
        let window = DateInterval(start: start, duration: 3 * 3600)
        let seg = CalendarPositioning.visibleSegment(of: window, on: day, calendar: cal)
        #expect(seg?.start == start)
        #expect(seg?.durationSeconds == 3 * 3600)
        #expect(seg?.clippedStart == false)
        #expect(seg?.clippedEnd == false)
    }

    @Test("visibleSegment clipped at start (window from previous day)")
    func visibleSegmentClippedStart() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let day = cal.date(from: DateComponents(year: 2026, month: 5, day: 9))!
        let start = cal.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 22))!
        let window = DateInterval(start: start, duration: 5 * 3600)
        let seg = CalendarPositioning.visibleSegment(of: window, on: day, calendar: cal)
        let expectedStart = cal.startOfDay(for: day)
        #expect(seg?.start == expectedStart)
        #expect(seg?.durationSeconds == 3 * 3600)
        #expect(seg?.clippedStart == true)
        #expect(seg?.clippedEnd == false)
    }

    @Test("visibleSegment clipped at end (window spills into next day)")
    func visibleSegmentClippedEnd() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let day = cal.date(from: DateComponents(year: 2026, month: 5, day: 9))!
        let start = cal.date(from: DateComponents(year: 2026, month: 5, day: 9, hour: 22))!
        let window = DateInterval(start: start, duration: 5 * 3600)
        let seg = CalendarPositioning.visibleSegment(of: window, on: day, calendar: cal)
        #expect(seg?.start == start)
        #expect(seg?.durationSeconds == 2 * 3600)
        #expect(seg?.clippedStart == false)
        #expect(seg?.clippedEnd == true)
    }

    @Test("visibleSegment returns nil when window doesn't overlap day")
    func visibleSegmentNoOverlap() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let day = cal.date(from: DateComponents(year: 2026, month: 5, day: 9))!
        let start = cal.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 6))!
        let window = DateInterval(start: start, duration: 3 * 3600)
        let seg = CalendarPositioning.visibleSegment(of: window, on: day, calendar: cal)
        #expect(seg == nil)
    }

    @Test("windowOverlaps matches both days when window crosses midnight")
    func windowOverlapsCrossesMidnight() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let day1 = cal.date(from: DateComponents(year: 2026, month: 5, day: 8))!
        let day2 = cal.date(from: DateComponents(year: 2026, month: 5, day: 9))!
        let start = cal.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 20))!
        #expect(CalendarPositioning.windowOverlaps(
            start: start, durationSeconds: 5 * 3600, day: day1, calendar: cal
        ))
        #expect(CalendarPositioning.windowOverlaps(
            start: start, durationSeconds: 5 * 3600, day: day2, calendar: cal
        ))
    }

    @Test("windowOverlaps matches only start day when window fits in one day")
    func windowOverlapsSingleDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let day1 = cal.date(from: DateComponents(year: 2026, month: 5, day: 8))!
        let day2 = cal.date(from: DateComponents(year: 2026, month: 5, day: 9))!
        let start = cal.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 2))!
        #expect(CalendarPositioning.windowOverlaps(
            start: start, durationSeconds: 5 * 3600, day: day1, calendar: cal
        ))
        #expect(!CalendarPositioning.windowOverlaps(
            start: start, durationSeconds: 5 * 3600, day: day2, calendar: cal
        ))
    }

    @Test("windowOverlaps spans both days for 2-minute window starting at 23:59")
    func windowOverlapsLateMinute() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let day1 = cal.date(from: DateComponents(year: 2026, month: 5, day: 8))!
        let day2 = cal.date(from: DateComponents(year: 2026, month: 5, day: 9))!
        let start = cal.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 23, minute: 59))!
        #expect(CalendarPositioning.windowOverlaps(
            start: start, durationSeconds: 120, day: day1, calendar: cal
        ))
        #expect(CalendarPositioning.windowOverlaps(
            start: start, durationSeconds: 120, day: day2, calendar: cal
        ))
    }

    @Test("windowOverlaps treats interval as half-open at the end boundary")
    func windowOverlapsHalfOpenEnd() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let day1 = cal.date(from: DateComponents(year: 2026, month: 5, day: 8))!
        let day2 = cal.date(from: DateComponents(year: 2026, month: 5, day: 9))!
        // Window ends exactly at 00:00 day 2 — overlaps day 1 but NOT day 2.
        let start = cal.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 22))!
        #expect(CalendarPositioning.windowOverlaps(
            start: start, durationSeconds: 2 * 3600, day: day1, calendar: cal
        ))
        #expect(!CalendarPositioning.windowOverlaps(
            start: start, durationSeconds: 2 * 3600, day: day2, calendar: cal
        ))
    }

    @Test("vertical stack shifts overlapping blocks after previous block")
    func verticalStackShiftsOverlaps() {
        let placements = CalendarPositioning.stackVertically([
            .init(yOffset: 10, height: 50),
            .init(yOffset: 40, height: 20),
        ], gap: 6)

        #expect(placements == [
            .init(yOffset: 10),
            .init(yOffset: 66),
        ])
    }

    @Test("vertical stack keeps touching blocks at true positions")
    func verticalStackKeepsTouchingBlocks() {
        let placements = CalendarPositioning.stackVertically([
            .init(yOffset: 10, height: 50),
            .init(yOffset: 60, height: 20),
        ], gap: 6)

        #expect(placements == [
            .init(yOffset: 10),
            .init(yOffset: 60),
        ])
    }

    @Test("vertical stack chains shifted overlaps")
    func verticalStackChainsShiftedOverlaps() {
        let placements = CalendarPositioning.stackVertically([
            .init(yOffset: 10, height: 50),
            .init(yOffset: 40, height: 20),
            .init(yOffset: 70, height: 10),
        ], gap: 4)

        #expect(placements == [
            .init(yOffset: 10),
            .init(yOffset: 64),
            .init(yOffset: 88),
        ])
    }
}
