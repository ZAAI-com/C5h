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
}
