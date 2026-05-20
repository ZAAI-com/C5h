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
}
