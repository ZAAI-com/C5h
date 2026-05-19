import Foundation

extension Date {
    /// `2026-05-19` — calendar date only, ISO format. Use for any UI label that
    /// shows a date without a time.
    var c5hISODate: String {
        formatted(.iso8601.year().month().day())
    }
}
