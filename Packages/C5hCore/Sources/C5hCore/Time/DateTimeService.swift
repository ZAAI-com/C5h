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
}
