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

    @Test("vertical stack never displaces a block past the column bound")
    func verticalStackClampsToMaxY() {
        // Shifts accumulate, so an unbounded stack walks a dense cluster off the
        // end of the column, where blocks are neither drawn nor hit-tested. Past
        // the bound a block stops moving and overlaps in place instead.
        let placements = CalendarPositioning.stackVertically([
            .init(yOffset: 10, height: 50),
            .init(yOffset: 40, height: 20),
            .init(yOffset: 45, height: 20),
            .init(yOffset: 50, height: 20),
        ], gap: 4, maxY: 100)

        #expect(placements == [
            .init(yOffset: 10),
            .init(yOffset: 64),
            .init(yOffset: 80),
            .init(yOffset: 80),
        ])
    }

    @Test("vertical stack bound never lifts a block above its true position")
    func verticalStackBoundKeepsLateBlocksInPlace() {
        // A block genuinely near the end of the day already extends past the
        // bound. Clamping must not drag it upward, away from its own time.
        let placements = CalendarPositioning.stackVertically([
            .init(yOffset: 80, height: 40),
            .init(yOffset: 90, height: 40),
        ], gap: 4, maxY: 100)

        #expect(placements == [
            .init(yOffset: 80),
            .init(yOffset: 90),
        ])
    }

    @Test("now line offset matches time delta at natural placement")
    func nowLineOffsetNaturalPlacement() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let segmentStart = cal.date(from: DateComponents(year: 2026, month: 5, day: 9, hour: 10))!
        let now = cal.date(from: DateComponents(year: 2026, month: 5, day: 9, hour: 10, minute: 30))!
        let ppm: CGFloat = 1.0
        let renderedTop = CalendarPositioning.yOffset(for: segmentStart, pixelsPerMinute: ppm, calendar: cal)
        let offset = CalendarPositioning.nowLineOffset(
            inBlockTop: renderedTop,
            now: now,
            pixelsPerMinute: ppm,
            calendar: cal
        )
        #expect(offset == 30.0)
        #expect(renderedTop + offset == CalendarPositioning.yOffset(for: now, pixelsPerMinute: ppm, calendar: cal))
    }

    @Test("now line absolute Y stays at now when block is vertically stacked")
    func nowLineOffsetStackedPlacement() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let segmentStart = cal.date(from: DateComponents(year: 2026, month: 5, day: 9, hour: 10))!
        let now = cal.date(from: DateComponents(year: 2026, month: 5, day: 9, hour: 10, minute: 30))!
        let ppm: CGFloat = 1.0
        let timeTop = CalendarPositioning.yOffset(for: segmentStart, pixelsPerMinute: ppm, calendar: cal)
        let renderedTop = timeTop + 26 // pushed down by vertical stacking
        let offset = CalendarPositioning.nowLineOffset(
            inBlockTop: renderedTop,
            now: now,
            pixelsPerMinute: ppm,
            calendar: cal
        )
        #expect(offset == 4.0)
        #expect(renderedTop + offset == CalendarPositioning.yOffset(for: now, pixelsPerMinute: ppm, calendar: cal))
    }

    @Test("usage row straddling the now line moves above when there is room")
    func usageRowAvoidingNowLinePlacedAbove() {
        // Preferred 46 with height 14 straddles a line at 50; the upper side
        // (50 - 14 - 4 = 32) clears the reserved top rows.
        let offset = CalendarPositioning.usageRowOffsetAvoidingNowLine(
            preferred: 46,
            rowHeight: 14,
            nowY: 50,
            minOffset: 2,
            maxOffset: 200,
            gap: 4
        )
        #expect(offset == 32)
    }

    @Test("usage row falls below the now line when the upper side has no room")
    func usageRowAvoidingNowLineForcedBelow() {
        // Preferred 6 straddles a line at 10; above would land at -8, below
        // the reserved top rows, so the row takes the lower side (10 + 4).
        let offset = CalendarPositioning.usageRowOffsetAvoidingNowLine(
            preferred: 6,
            rowHeight: 14,
            nowY: 10,
            minOffset: 2,
            maxOffset: 200,
            gap: 4
        )
        #expect(offset == 14)
    }

    @Test("usage row clamps when neither side of the now line fits")
    func usageRowAvoidingNowLineClamped() {
        // A block so short that neither above (-13) nor below (9) fits the
        // reserved bounds [2, 8]: the preferred offset clamps into them.
        let offset = CalendarPositioning.usageRowOffsetAvoidingNowLine(
            preferred: -5,
            rowHeight: 14,
            nowY: 5,
            minOffset: 2,
            maxOffset: 8,
            gap: 4
        )
        #expect(offset == 2)
    }

    @Test("usage row avoidance stays inside both bounds")
    func usageRowAvoidingNowLineRespectsBothBounds() {
        // A tall reserved footer leaves bounds [2, 20]. Preferred 30 straddles a
        // line at 40, and the upper candidate (40 - 14 - 4 = 22) overshoots
        // maxOffset: checking only `>= minOffset` let the row escape the block.
        let above = CalendarPositioning.usageRowOffsetAvoidingNowLine(
            preferred: 30,
            rowHeight: 14,
            nowY: 40,
            minOffset: 2,
            maxOffset: 20,
            gap: 4
        )
        #expect(above >= 2 && above <= 20)

        // Mirror case: the lower candidate (10 + 4 = 14) satisfies maxOffset but
        // sits above a high minOffset, which would overlap the reserved header.
        let below = CalendarPositioning.usageRowOffsetAvoidingNowLine(
            preferred: 18,
            rowHeight: 14,
            nowY: 10,
            minOffset: 16,
            maxOffset: 200,
            gap: 4
        )
        #expect(below >= 16 && below <= 200)
    }

    @Test("a non-straddling preferred offset is still clamped into bounds")
    func usageRowAvoidingNowLineClampsNonStraddling() {
        // The row does not straddle the line at 5, but its preferred offset is
        // far past maxOffset; passing it through unclamped rendered outside.
        let offset = CalendarPositioning.usageRowOffsetAvoidingNowLine(
            preferred: 500,
            rowHeight: 14,
            nowY: 5,
            minOffset: 2,
            maxOffset: 100,
            gap: 4
        )
        #expect(offset == 100)
    }

    @Test("missing now line passes the preferred offset through, clamped")
    func usageRowAvoidingNowLineMissingNowLine() {
        let within = CalendarPositioning.usageRowOffsetAvoidingNowLine(
            preferred: 30,
            rowHeight: 14,
            nowY: nil,
            minOffset: 2,
            maxOffset: 200,
            gap: 4
        )
        #expect(within == 30)
        let outside = CalendarPositioning.usageRowOffsetAvoidingNowLine(
            preferred: 500,
            rowHeight: 14,
            nowY: nil,
            minOffset: 2,
            maxOffset: 200,
            gap: 4
        )
        #expect(outside == 200)
    }

    @Test("row clear of the now line keeps its preferred offset")
    func usageRowAvoidingNowLineNonStraddling() {
        let offset = CalendarPositioning.usageRowOffsetAvoidingNowLine(
            preferred: 100,
            rowHeight: 14,
            nowY: 10,
            minOffset: 2,
            maxOffset: 200,
            gap: 4
        )
        #expect(offset == 100)
    }
}
