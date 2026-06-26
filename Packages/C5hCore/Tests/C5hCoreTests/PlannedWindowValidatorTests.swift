import Foundation
import Testing
@testable import C5hCore

@Suite("PlannedWindowValidator")
struct PlannedWindowValidatorTests {
    @Test("Same-provider overlap detected")
    func sameProviderOverlap() {
        let base = Date(timeIntervalSince1970: 1_730_000_000)
        let existing = PlannedWindow(
            providerID: .claude,
            startAt: base,
            durationSeconds: 5 * 3600
        )
        let candidate = PlannedWindow(
            providerID: .claude,
            startAt: base.addingTimeInterval(3600),
            durationSeconds: 5 * 3600
        )
        let result = PlannedWindowValidator.validate(
            candidate: candidate,
            against: [existing]
        )
        #expect(result.hasConflict)
        #expect(result.conflictingWindowIDs == [existing.id])
    }

    @Test("Different-provider overlap is ignored")
    func differentProvider() {
        let base = Date(timeIntervalSince1970: 1_730_000_000)
        let existing = PlannedWindow(providerID: .claude, startAt: base)
        let candidate = PlannedWindow(providerID: .codex, startAt: base)
        let result = PlannedWindowValidator.validate(
            candidate: candidate,
            against: [existing]
        )
        #expect(!result.hasConflict)
    }

    @Test("Back-to-back windows touching at a boundary do not conflict")
    func boundaryTouchAllowed() {
        let base = Date(timeIntervalSince1970: 1_730_000_000)
        let existing = PlannedWindow(
            providerID: .claude,
            startAt: base,
            durationSeconds: 5 * 3600
        )
        let after = PlannedWindow(
            providerID: .claude,
            startAt: existing.endAt,
            durationSeconds: 5 * 3600
        )
        let before = PlannedWindow(
            providerID: .claude,
            startAt: base.addingTimeInterval(-5 * 3600),
            durationSeconds: 5 * 3600
        )
        #expect(
            !PlannedWindowValidator
                .validate(candidate: after, against: [existing])
                .hasConflict
        )
        #expect(
            !PlannedWindowValidator
                .validate(candidate: before, against: [existing])
                .hasConflict
        )
    }

    @Test("Updating same window does not conflict with itself")
    func selfNoConflict() {
        let base = Date(timeIntervalSince1970: 1_730_000_000)
        let existing = PlannedWindow(providerID: .claude, startAt: base)
        let result = PlannedWindowValidator.validate(
            candidate: existing,
            against: [existing]
        )
        #expect(!result.hasConflict)
    }
}
