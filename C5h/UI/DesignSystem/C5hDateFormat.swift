import Foundation

private enum C5hDateFormatters {
    static let isoDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let logTimestamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd 'at' HH:mm:ss"
        return f
    }()
}

extension Date {
    /// `2026-05-19` — calendar date only, ISO format. Use for any UI label that
    /// shows a date without a time.
    var c5hISODate: String {
        C5hDateFormatters.isoDate.string(from: self)
    }

    /// `2026-05-21 at 09:45:45` - local time, fixed numeric format for logs.
    var c5hLogTimestamp: String {
        C5hDateFormatters.logTimestamp.string(from: self)
    }
}
