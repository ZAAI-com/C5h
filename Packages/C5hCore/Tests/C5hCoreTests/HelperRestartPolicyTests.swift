import Foundation
import Testing
@testable import C5hCore

@Suite("HelperRestartPolicy")
struct HelperRestartPolicyTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)
    private let maxUptime: TimeInterval = 24 * 60 * 60

    @Test
    func doesNotRestartBeforeMaxUptime() {
        let now = start.addingTimeInterval(maxUptime - 1)
        #expect(HelperRestartPolicy.shouldRestart(
            startedAt: start,
            now: now,
            maxUptimeSeconds: maxUptime
        ) == false)
    }

    @Test
    func restartsAtMaxUptime() {
        let now = start.addingTimeInterval(maxUptime)
        #expect(HelperRestartPolicy.shouldRestart(
            startedAt: start,
            now: now,
            maxUptimeSeconds: maxUptime
        ))
    }

    @Test
    func restartsAfterMaxUptime() {
        let now = start.addingTimeInterval(maxUptime + 3_600)
        #expect(HelperRestartPolicy.shouldRestart(
            startedAt: start,
            now: now,
            maxUptimeSeconds: maxUptime
        ))
    }

    @Test
    func defaultMaxUptimeIsTwentyFourHours() {
        #expect(HelperRestartPolicy.defaultMaxUptimeSeconds == 24 * 60 * 60)
    }
}
