import Foundation

extension Date {
    /// `2026-05-19` — calendar date only, ISO format. Use for any UI label that
    /// shows a date without a time.
    var c5hISODate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: self)
    }

    /// `2026-05-21 at 09:45:45` - local time, fixed numeric format for logs.
    var c5hLogTimestamp: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd 'at' HH:mm:ss"
        return formatter.string(from: self)
    }
}
