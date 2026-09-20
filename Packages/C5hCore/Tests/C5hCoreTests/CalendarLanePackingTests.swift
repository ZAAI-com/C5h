import Foundation
import CoreGraphics
import Testing
@testable import C5hCore

@Suite("CalendarPositioning.packLanes")
struct CalendarLanePackingTests {
    /// Builds an interval from fractional-hour bounds on a fixed reference day.
    private func interval(_ startHour: Double, _ endHour: Double) -> DateInterval {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        return DateInterval(
            start: base.addingTimeInterval(startHour * 3600),
            end: base.addingTimeInterval(endHour * 3600)
        )
    }

    @Test("Empty input returns empty")
    func empty() {
        #expect(CalendarPositioning.packLanes([]).isEmpty)
    }

    @Test("Non-overlapping intervals all sit in lane 0 with count 1")
    func nonOverlapping() {
        let placements = CalendarPositioning.packLanes([
            interval(0, 1),
            interval(2, 3),
            interval(5, 6),
        ])
        #expect(placements == [
            .init(lane: 0, laneCount: 1),
            .init(lane: 0, laneCount: 1),
            .init(lane: 0, laneCount: 1),
        ])
    }

    @Test("Two overlapping intervals take lanes 0 and 1 with count 2")
    func twoOverlapping() {
        let placements = CalendarPositioning.packLanes([
            interval(0, 2),
            interval(1, 3),
        ])
        #expect(placements == [
            .init(lane: 0, laneCount: 2),
            .init(lane: 1, laneCount: 2),
        ])
    }

    @Test("Touching edges do not overlap and reuse the same lane")
    func touchingEdges() {
        let placements = CalendarPositioning.packLanes([
            interval(0, 1),
            interval(1, 2),
        ])
        #expect(placements == [
            .init(lane: 0, laneCount: 1),
            .init(lane: 0, laneCount: 1),
        ])
    }

    @Test("Three mutually overlapping intervals form a 3-lane cluster")
    func threeDeepNest() {
        let placements = CalendarPositioning.packLanes([
            interval(0, 6),
            interval(1, 5),
            interval(2, 4),
        ])
        #expect(placements == [
            .init(lane: 0, laneCount: 3),
            .init(lane: 1, laneCount: 3),
            .init(lane: 2, laneCount: 3),
        ])
    }

    @Test("A long bridging interval keeps separate overlaps in one cluster")
    func bridgedCluster() {
        // [0,1) and [3,4) don't overlap each other, but [0.5,3.5) overlaps both,
        // so all three belong to one cluster and share laneCount 2.
        let placements = CalendarPositioning.packLanes([
            interval(0, 1),
            interval(3, 4),
            interval(0.5, 3.5),
        ])
        #expect(placements.allSatisfy { $0.laneCount == 2 })
        // The two short, non-overlapping intervals can reuse lane 0; the bridge
        // is pushed to lane 1.
        #expect(placements[0].lane == 0)
        #expect(placements[2].lane == 1)
    }

    @Test("Separate clusters are sized independently")
    func independentClusters() {
        // Cluster A: two overlapping (count 2). Gap. Cluster B: single (count 1).
        let placements = CalendarPositioning.packLanes([
            interval(0, 2),
            interval(1, 3),
            interval(10, 11),
        ])
        #expect(placements[0].laneCount == 2)
        #expect(placements[1].laneCount == 2)
        #expect(placements[2] == .init(lane: 0, laneCount: 1))
    }

    @Test("Inflating short adjacent intervals to a visual minimum splits their lanes")
    func inflatedFootprintSeparatesLanes() {
        // Two back-to-back ~36s windows touch (raw) and so reuse one lane…
        let rawA = interval(0, 0.01)
        let rawB = interval(0.01, 0.02)
        #expect(CalendarPositioning.packLanes([rawA, rawB]).allSatisfy { $0.lane == 0 })

        // …but once each is inflated to a minimum visual footprint (here 0.5h),
        // they overlap and must occupy separate lanes — matching the week view's
        // `minimumBarHeight` packing so short bars don't visually collide.
        let minimumFootprint: TimeInterval = 0.5 * 3600
        func inflated(_ i: DateInterval) -> DateInterval {
            DateInterval(start: i.start, duration: max(i.duration, minimumFootprint))
        }
        let placements = CalendarPositioning.packLanes([inflated(rawA), inflated(rawB)])
        #expect(placements == [
            .init(lane: 0, laneCount: 2),
            .init(lane: 1, laneCount: 2),
        ])
    }

    @Test("Results are returned in input order, not sorted order")
    func preservesInputOrder() {
        // Provided out of start order: later-starting interval listed first.
        let placements = CalendarPositioning.packLanes([
            interval(1, 3),   // index 0, starts later
            interval(0, 2),   // index 1, starts earlier
        ])
        // The earlier-starting interval (index 1) gets lane 0.
        #expect(placements[1].lane == 0)
        #expect(placements[0].lane == 1)
        #expect(placements.allSatisfy { $0.laneCount == 2 })
    }
    @Test("Screenshot overlap preserves times, hit targets and the following 20:00 start")
    func screenshotFrames() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            day.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
        }
        let intervals = [
            DateInterval(start: at(10, 59), end: at(15, 59)),
            DateInterval(start: at(15), end: at(20)),
            DateInterval(start: at(20), end: at(24)),
        ]
        let frames = CalendarPositioning.laneFrames(
            for: intervals, pixelsPerMinute: 1, columnWidth: 200, calendar: calendar
        )
        #expect(frames.map(\.minY) == [659, 900, 1200])
        #expect(frames.map(\.maxY) == [959, 1200, 1440])
        #expect(!frames[0].intersects(frames[1]))
        #expect(frames[2].width == 200)
        let plannedHit = CGPoint(x: frames[1].midX, y: 930)
        #expect(frames[1].contains(plannedHit))
        #expect(!frames[0].contains(plannedHit))
        #expect(CalendarPositioning.nowLineOffset(
            inBlockTop: frames[0].minY, now: at(12, 47), pixelsPerMinute: 1, calendar: calendar
        ) + frames[0].minY == 767)

        // Moving the plan beyond the actual window removes the overlap without
        // changing the time-derived position of either block.
        let moved = CalendarPositioning.laneFrames(
            for: [intervals[0], DateInterval(start: at(16), end: at(21))],
            pixelsPerMinute: 1, columnWidth: 200, calendar: calendar
        )
        #expect(moved.map(\.minY) == [659, 960])
        #expect(moved.allSatisfy { $0.width == 200 })
    }

    @Test("A lone interval keeps the full column width")
    func loneIntervalFullWidth() {
        // The day column packs planned and actual blocks in separate passes, so
        // an actual window overlapped by a plan is alone in its pass and must
        // still span the whole column.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let frames = CalendarPositioning.laneFrames(
            for: [interval(10, 15)],
            pixelsPerMinute: 1, columnWidth: 200, calendar: calendar
        )
        #expect(frames.count == 1)
        #expect(frames[0].minX == 0)
        #expect(frames[0].width == 200)
    }

    @Test("Clipped midnight segments and narrow lanes stay within their column")
    func clippedNarrowFrames() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let segment = try #require(CalendarPositioning.visibleSegment(
            of: DateInterval(start: day.addingTimeInterval(-3600), duration: 5 * 3600),
            on: day, calendar: calendar
        ))
        let clipped = DateInterval(start: segment.start, duration: TimeInterval(segment.durationSeconds))
        let frames = CalendarPositioning.laneFrames(
            for: [clipped, clipped, clipped], pixelsPerMinute: 0.5, columnWidth: 3, calendar: calendar
        )
        #expect(segment.clippedStart)
        #expect(frames.allSatisfy { $0.minY == 0 && $0.height == 120 })
        #expect(frames.allSatisfy { $0.width > 0 && $0.minX >= 0 && $0.maxX <= 3 })
        #expect(!frames[0].intersects(frames[1]))
        #expect(!frames[1].intersects(frames[2]))
    }

}
