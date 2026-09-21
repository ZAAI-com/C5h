import Foundation
import Testing
@testable import C5hCore

@Suite("PlannedSlotResolver")
struct PlannedSlotResolverTests {
    private let dayStart = Date(timeIntervalSince1970: 1_730_000_000)
    private var day: DateInterval { DateInterval(start: dayStart, duration: 24 * 3600) }

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        dayStart.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
    }

    @Test("An allowed candidate is returned unchanged")
    func allowedCandidate() {
        let resolved = PlannedSlotResolver.nearestAllowedStart(
            near: at(5), in: day, stepSeconds: 600
        ) { _ in true }
        #expect(resolved == at(5))
    }

    @Test("Equally close free slots prefer the later one")
    func tiePrefersLater() {
        let blocked = at(4, 50)...at(5, 10)
        let resolved = PlannedSlotResolver.nearestAllowedStart(
            near: at(5), in: day, stepSeconds: 600
        ) { !blocked.contains($0) }
        #expect(resolved == at(5, 20))
    }

    @Test("A drag into the past lands on the first future slot, ignoring a terminal plan")
    func dragIntoPastIgnoresTerminalPlan() {
        // 02:21 now; a triggered plan runs until 02:50 but is not an active
        // plan, so it is not part of the allowed check.
        let now = at(2, 21)
        let active = [PlannedWindow(providerID: .claude, startAt: at(9))]
        var dragged = PlannedWindow(providerID: .claude, startAt: at(5))
        let resolved = PlannedSlotResolver.nearestAllowedStart(
            near: at(1), in: day, stepSeconds: 600
        ) { start in
            guard start > now else { return false }
            dragged.startAt = start
            return !PlannedWindowValidator.validate(candidate: dragged, against: active).hasConflict
        }
        #expect(resolved == at(2, 30))
    }

    @Test("The provider step is honoured")
    func honoursStep() {
        let now = at(2, 21)
        let resolved = PlannedSlotResolver.nearestAllowedStart(
            near: at(1), in: day, stepSeconds: 300
        ) { $0 > now }
        #expect(resolved == at(2, 25))
    }

    @Test("Resolved starts stay inside the interval")
    func staysInsideInterval() {
        // Only slots outside the day are allowed: nothing may be returned.
        let outside = PlannedSlotResolver.nearestAllowedStart(
            near: at(23, 50), in: day, stepSeconds: 600
        ) { $0 >= day.end || $0 < day.start }
        #expect(outside == nil)

        // The latest valid start is one step before the interval end.
        let latest = PlannedSlotResolver.nearestAllowedStart(
            near: at(12), in: day, stepSeconds: 600
        ) { $0 >= at(23, 50) }
        #expect(latest == at(23, 50))
    }

    @Test("Nil when nothing is allowed")
    func nilWhenNothingAllowed() {
        let resolved = PlannedSlotResolver.nearestAllowedStart(
            near: at(5), in: day, stepSeconds: 600
        ) { _ in false }
        #expect(resolved == nil)
    }
}
