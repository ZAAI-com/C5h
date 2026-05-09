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
}
