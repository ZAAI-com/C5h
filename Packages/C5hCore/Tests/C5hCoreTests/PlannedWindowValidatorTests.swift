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

    @Test("Same-provider active actual overlap detected")
    func sameProviderActiveActualOverlap() {
        let now = Date(timeIntervalSince1970: 1_730_000_000)
        let active = ActualWindow5h(
            providerID: .codex,
            startAt: now.addingTimeInterval(-3600),
            durationSeconds: 5 * 3600,
            source: .detectedFromUsage,
            confidence: .estimated
        )
        let candidate = PlannedWindow(
            providerID: .codex,
            startAt: now.addingTimeInterval(10 * 60),
            durationSeconds: 5 * 3600
        )
        let result = PlannedWindowValidator.validate(
            candidate: candidate,
            against: [],
            activeActualWindows: [active],
            now: now
        )
        #expect(result.hasConflict)
        #expect(result.conflictingWindowIDs == [active.id])
    }

    @Test("Inactive and different-provider actual windows are ignored")
    func ignoresInactiveAndDifferentProviderActualWindows() {
        let now = Date(timeIntervalSince1970: 1_730_000_000)
        let inactive = ActualWindow5h(
            providerID: .codex,
            startAt: now.addingTimeInterval(-6 * 3600),
            durationSeconds: 5 * 3600,
            source: .detectedFromUsage,
            confidence: .estimated
        )
        let differentProvider = ActualWindow5h(
            providerID: .claude,
            startAt: now.addingTimeInterval(-3600),
            durationSeconds: 5 * 3600,
            source: .detectedFromUsage,
            confidence: .estimated
        )
        let candidate = PlannedWindow(
            providerID: .codex,
            startAt: now.addingTimeInterval(-5 * 3600 - 30 * 60),
            durationSeconds: 5 * 3600
        )
        let result = PlannedWindowValidator.validate(
            candidate: candidate,
            against: [],
            activeActualWindows: [inactive, differentProvider],
            now: now
        )
        #expect(!result.hasConflict)
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
