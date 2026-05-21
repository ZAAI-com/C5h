import Foundation

public enum DateTimeService {
    public static let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    // ISO8601DateFormatter is documented as thread-safe for parsing/formatting,
    // but it is not marked Sendable. Mark the shared instance unsafe-nonisolated
    // and only mutate it during initialization.
    nonisolated(unsafe) public static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    public static func formatUTC(_ date: Date) -> String {
        iso8601Formatter.string(from: date)
    }

    public static func parseUTC(_ string: String) -> Date? {
        iso8601Formatter.date(from: string)
    }

    public static func add(seconds: Int, to date: Date) -> Date {
        date.addingTimeInterval(TimeInterval(seconds))
    }

    /// Returns `YYYY-MM-DD` for `date` evaluated in `timeZone`. Used to tag a
    /// window with the calendar date it belongs to in the user's local zone.
    public static func localDate(for date: Date, in timeZone: TimeZone) -> String {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = timeZone
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            comps.year ?? 0,
            comps.month ?? 0,
            comps.day ?? 0
        )
    }
}
