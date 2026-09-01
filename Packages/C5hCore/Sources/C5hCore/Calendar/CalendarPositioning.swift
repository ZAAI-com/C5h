import Foundation
import CoreFoundation

public enum CalendarPositioning {
    public static func minutesSinceStartOfDay(
        _ date: Date,
        calendar: Calendar = .current
    ) -> Int {
        let start = calendar.startOfDay(for: date)
        let comps = calendar.dateComponents([.hour, .minute], from: start, to: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    public static func yOffset(
        for date: Date,
        pixelsPerMinute: CGFloat,
        calendar: Calendar = .current
    ) -> CGFloat {
        CGFloat(minutesSinceStartOfDay(date, calendar: calendar)) * pixelsPerMinute
    }

    /// Vertical offset of the current-time line inside a block, given the block's
    /// top edge in column coordinates (after vertical stacking).
    public static func nowLineOffset(
        inBlockTop renderedTop: CGFloat,
        now: Date,
        pixelsPerMinute: CGFloat,
        calendar: Calendar = .current
    ) -> CGFloat {
        yOffset(for: now, pixelsPerMinute: pixelsPerMinute, calendar: calendar) - renderedTop
    }

    public static func blockHeight(
        durationSeconds: Int,
        pixelsPerMinute: CGFloat,
        minimum: CGFloat = 24
    ) -> CGFloat {
        let minutes = CGFloat(durationSeconds) / 60.0
        return max(minutes * pixelsPerMinute, minimum)
    }

    public static func dayInterval(for date: Date, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

    /// Returns the portion of `window` that is visible on the day containing
    /// `day`, clipped to that day's local interval. Returns `nil` when the
    /// window does not overlap the day at all. `clippedStart` / `clippedEnd`
    /// indicate whether the window extends beyond the day boundary on the
    /// respective side — useful for squaring off rounded corners on the cut
    /// edge.
    public static func visibleSegment(
        of window: DateInterval,
        on day: Date,
        calendar: Calendar = .current
    ) -> (start: Date, durationSeconds: Int, clippedStart: Bool, clippedEnd: Bool)? {
        let dayBounds = dayInterval(for: day, calendar: calendar)
        let visibleStart = max(window.start, dayBounds.start)
        let visibleEnd = min(window.end, dayBounds.end)
        let seconds = Int(visibleEnd.timeIntervalSince(visibleStart).rounded())
        guard seconds > 0 else { return nil }
        return (
            start: visibleStart,
            durationSeconds: seconds,
            clippedStart: window.start < dayBounds.start,
            clippedEnd: window.end > dayBounds.end
        )
    }

    /// Returns true when the half-open interval [start, start+durationSeconds)
    /// overlaps the local-day interval for `day`. Used by week-view per-day
    /// filtering so windows crossing midnight render in both day columns.
    public static func windowOverlaps(
        start: Date,
        durationSeconds: Int,
        day: Date,
        calendar: Calendar = .current
    ) -> Bool {
        let dayBounds = dayInterval(for: day, calendar: calendar)
        let end = start.addingTimeInterval(TimeInterval(durationSeconds))
        return start < dayBounds.end && end > dayBounds.start
    }

    /// Inverse of `yOffset(for:pixelsPerMinute:)`: converts a Y pixel position
    /// within a day column back to the corresponding `Date`. Used by the
    /// hover-to-plan affordance in the day calendar.
    public static func date(
        forYOffset yOffset: CGFloat,
        on day: Date,
        pixelsPerMinute: CGFloat,
        calendar: Calendar = .current
    ) -> Date {
        let startOfDay = calendar.startOfDay(for: day)
        guard pixelsPerMinute > 0 else { return startOfDay }
        let clamped = max(0, yOffset)
        let minutes = Double(clamped / pixelsPerMinute)
        return startOfDay.addingTimeInterval(minutes * 60)
    }

    /// Snaps a date to a multiple of `minutes` (defaults to 5-minute grid).
    public static func snap(_ date: Date, toMinutes minutes: Int) -> Date {
        precondition(minutes > 0, "CalendarPositioning.snap requires minutes > 0")
        let interval = Double(minutes) * 60
        let snapped = (date.timeIntervalSince1970 / interval).rounded() * interval
        return Date(timeIntervalSince1970: snapped)
    }

    /// The lane (column) a window occupies once overlapping windows are laid out
    /// side-by-side, plus the number of concurrent lanes in its overlap cluster.
    /// Callers divide the available width by `laneCount` and offset by `lane`.
    public struct LanePlacement: Sendable, Equatable {
        public let lane: Int
        public let laneCount: Int

        public init(lane: Int, laneCount: Int) {
            self.lane = lane
            self.laneCount = laneCount
        }
    }

    public struct VerticalStackInput: Sendable, Equatable {
        public let yOffset: CGFloat
        public let height: CGFloat

        public init(yOffset: CGFloat, height: CGFloat) {
            self.yOffset = yOffset
            self.height = height
        }
    }

    public struct VerticalStackPlacement: Sendable, Equatable {
        public let yOffset: CGFloat

        public init(yOffset: CGFloat) {
            self.yOffset = yOffset
        }
    }

    /// Display-only vertical packing for calendar blocks in the same column.
    /// The caller supplies blocks in render order, normally sorted by their true
    /// time-derived Y position. Touching blocks keep their true position; only a
    /// block whose top would overlap the previous rendered bottom is shifted down.
    ///
    /// `maxY` bounds the displacement to the height of the column. Shifts
    /// accumulate, so without a bound a dense cluster walks blocks past the
    /// column's clipped frame, where they are neither visible nor hit-testable.
    /// Past the bound a block stops being displaced and overlaps in place
    /// instead, which keeps it reachable. A block is never moved above its own
    /// true position.
    public static func stackVertically(
        _ blocks: [VerticalStackInput],
        gap: CGFloat = 4,
        maxY: CGFloat? = nil
    ) -> [VerticalStackPlacement] {
        var previousBottom: CGFloat?
        return blocks.map { block in
            var y: CGFloat
            if let bottom = previousBottom, block.yOffset < bottom {
                y = bottom + gap
            } else {
                y = block.yOffset
            }
            if let maxY {
                y = min(y, max(block.yOffset, maxY - block.height))
            }
            previousBottom = y + block.height
            return VerticalStackPlacement(yOffset: y)
        }
    }

    /// Greedy interval-graph packing — the standard calendar column layout.
    /// Returns one placement per input interval, in the same order as the input.
    /// Overlapping intervals are assigned distinct lanes; every interval in a
    /// connected cluster of overlaps shares the same `laneCount` so their columns
    /// line up. Intervals use half-open `[start, end)` semantics, so touching
    /// edges (`a.end == b.start`) do **not** overlap and may share a lane.
    public static func packLanes(_ intervals: [DateInterval]) -> [LanePlacement] {
        guard !intervals.isEmpty else { return [] }

        // Process intervals in start order (ties broken by end), remembering the
        // original index so results can be mapped back to input order.
        let order = intervals.indices.sorted { a, b in
            let ia = intervals[a], ib = intervals[b]
            if ia.start != ib.start { return ia.start < ib.start }
            return ia.end < ib.end
        }

        var laneByIndex = [Int](repeating: 0, count: intervals.count)
        var countByIndex = [Int](repeating: 1, count: intervals.count)

        // Mutable sweep state for the cluster currently being built.
        var laneEnds: [Date] = []      // end time occupying each open lane
        var clusterMembers: [Int] = [] // original indices in the current cluster
        var clusterMaxLane = 0
        var clusterEnd: Date? = nil    // max end across the current cluster

        func closeCluster() {
            let count = max(clusterMaxLane + 1, 1)
            for idx in clusterMembers { countByIndex[idx] = count }
            clusterMembers.removeAll(keepingCapacity: true)
            clusterMaxLane = 0
            laneEnds.removeAll(keepingCapacity: true)
            clusterEnd = nil
        }

        for sortedIdx in order {
            let interval = intervals[sortedIdx]

            // A start at/after everything in the cluster has ended begins a new
            // cluster (no overlap with anything placed so far).
            if let end = clusterEnd, interval.start >= end {
                closeCluster()
            }

            // Reuse the lowest lane whose occupant has ended; otherwise open one.
            var assigned: Int? = nil
            for lane in laneEnds.indices where laneEnds[lane] <= interval.start {
                laneEnds[lane] = interval.end
                assigned = lane
                break
            }
            let lane: Int
            if let assigned {
                lane = assigned
            } else {
                lane = laneEnds.count
                laneEnds.append(interval.end)
            }

            laneByIndex[sortedIdx] = lane
            clusterMembers.append(sortedIdx)
            clusterMaxLane = max(clusterMaxLane, lane)
            clusterEnd = max(clusterEnd ?? interval.end, interval.end)
        }
        closeCluster()

        return intervals.indices.map {
            LanePlacement(lane: laneByIndex[$0], laneCount: countByIndex[$0])
        }
    }
}
