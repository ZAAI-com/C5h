import Foundation
import Testing
@testable import C5hCore

@Suite("DateTimeService")
struct DateTimeServiceTests {
    @Test("UTC round-trip")
    func utcRoundTrip() {
        let now = Date()
        let formatted = DateTimeService.formatUTC(now)
        let parsed = DateTimeService.parseUTC(formatted)
        #expect(parsed != nil)
        if let parsed {
            #expect(abs(parsed.timeIntervalSince(now)) < 0.01)
        }
    }

    @Test("Add seconds")
    func addSeconds() {
        let base = Date(timeIntervalSince1970: 0)
        let later = DateTimeService.add(seconds: 3600, to: base)
        #expect(later.timeIntervalSince1970 == 3600)
    }

    @Test("localDate disagrees with UTC across a zone")
    func localDateAcrossZone() {
        // 2026-05-10 03:00 UTC is still 2026-05-09 20:00 in Los Angeles.
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 3))!
        let la = TimeZone(identifier: "America/Los_Angeles")!
        let utc = TimeZone(identifier: "UTC")!
        #expect(DateTimeService.localDate(for: date, in: la) == "2026-05-09")
        #expect(DateTimeService.localDate(for: date, in: utc) == "2026-05-10")
    }
}
