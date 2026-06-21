import Foundation
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
}
