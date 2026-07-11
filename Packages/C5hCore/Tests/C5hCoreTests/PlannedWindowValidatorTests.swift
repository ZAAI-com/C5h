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
            actualWindows: [active]
        )
        #expect(result.hasConflict)
        #expect(result.conflictingWindowIDs == [active.id])
    }

    @Test("Same-provider past actual overlap conflicts regardless of active state")
    func sameProviderPastActualOverlap() {
        let now = Date(timeIntervalSince1970: 1_730_000_000)
        // Fully in the past: ended an hour ago, so not currently in progress.
        let past = ActualWindow5h(
            providerID: .codex,
            startAt: now.addingTimeInterval(-6 * 3600),
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
            actualWindows: [past]
        )
        #expect(result.hasConflict)
        #expect(result.conflictingWindowIDs == [past.id])
    }

    @Test("Different-provider actual windows are ignored")
    func ignoresDifferentProviderActualWindows() {
        let now = Date(timeIntervalSince1970: 1_730_000_000)
        let differentProvider = ActualWindow5h(
            providerID: .claude,
            startAt: now.addingTimeInterval(-3600),
            durationSeconds: 5 * 3600,
            source: .detectedFromUsage,
            confidence: .estimated
        )
        let candidate = PlannedWindow(
            providerID: .codex,
            startAt: now.addingTimeInterval(-30 * 60),
            durationSeconds: 5 * 3600
        )
        let result = PlannedWindowValidator.validate(
            candidate: candidate,
            against: [],
            actualWindows: [differentProvider]
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

    // MARK: Chain risk

    private static let fiveHours: TimeInterval = 5 * 3600

    /// A recorded actual window ending at `end`.
    private func actualEnding(at end: Date, providerID: ProviderID = .claude) -> ActualWindow5h {
        ActualWindow5h(
            providerID: providerID,
            startAt: end.addingTimeInterval(-Self.fiveHours),
            durationSeconds: Int(Self.fiveHours),
            source: .detectedFromUsage,
            confidence: .estimated
        )
    }

    @Test("Warns when the start lands inside the previous window's chained slot")
    func chainRiskWarnsInsideChainedSlot() throws {
        // The incident shape: previous window ended 03:10, plan starts 80
        // minutes later. The chained slot runs to 08:10, so the block may be
        // 80 minutes short.
        let previousEnd = Date(timeIntervalSince1970: 1_730_000_000)
        let candidate = PlannedWindow(
            providerID: .claude,
            startAt: previousEnd.addingTimeInterval(80 * 60),
            durationSeconds: Int(Self.fiveHours)
        )
        let result = PlannedWindowValidator.validate(
            candidate: candidate,
            against: [],
            actualWindows: [actualEnding(at: previousEnd)]
        )
        let risk = try #require(result.chainRisk)
        #expect(!result.hasConflict)
        #expect(risk.previousWindowEnd == previousEnd)
        #expect(risk.projectedEffectiveEnd == previousEnd.addingTimeInterval(Self.fiveHours))
        #expect(risk.shortfallSeconds == 80 * 60)
        #expect(risk.suggestedStarts == [
            previousEnd,
            previousEnd.addingTimeInterval(Self.fiveHours),
        ])
    }

    @Test("No chain risk at a back-to-back start or a full window gap")
    func chainRiskAbsentAtSafeGaps() {
        let previousEnd = Date(timeIntervalSince1970: 1_730_000_000)
        let actuals = [actualEnding(at: previousEnd)]
        let backToBack = PlannedWindow(
            providerID: .claude,
            startAt: previousEnd,
            durationSeconds: Int(Self.fiveHours)
        )
        let fullGap = PlannedWindow(
            providerID: .claude,
            startAt: previousEnd.addingTimeInterval(Self.fiveHours),
            durationSeconds: Int(Self.fiveHours)
        )
        let justInside = PlannedWindow(
            providerID: .claude,
            startAt: previousEnd.addingTimeInterval(Self.fiveHours - 1),
            durationSeconds: Int(Self.fiveHours)
        )
        #expect(PlannedWindowValidator.validate(
            candidate: backToBack, against: [], actualWindows: actuals
        ).chainRisk == nil)
        #expect(PlannedWindowValidator.validate(
            candidate: fullGap, against: [], actualWindows: actuals
        ).chainRisk == nil)
        #expect(PlannedWindowValidator.validate(
            candidate: justInside, against: [], actualWindows: actuals
        ).chainRisk != nil)
    }

    @Test("Chain risk uses the latest previous window end")
    func chainRiskUsesLatestPreviousEnd() throws {
        let earlierEnd = Date(timeIntervalSince1970: 1_730_000_000)
        let laterEnd = earlierEnd.addingTimeInterval(2 * 3600)
        let candidate = PlannedWindow(
            providerID: .claude,
            startAt: laterEnd.addingTimeInterval(3600),
            durationSeconds: Int(Self.fiveHours)
        )
        let result = PlannedWindowValidator.validate(
            candidate: candidate,
            against: [],
            actualWindows: [actualEnding(at: earlierEnd), actualEnding(at: laterEnd)]
        )
        let risk = try #require(result.chainRisk)
        #expect(risk.previousWindowEnd == laterEnd)
    }

    @Test("Chain risk considers an earlier planned window's projected end")
    func chainRiskConsidersEarlierPlannedWindow() throws {
        // No actual window yet, but a scheduled window ends 90 minutes before
        // the candidate's start: once it opens a real block, the chained slot
        // will swallow the candidate.
        let base = Date(timeIntervalSince1970: 1_730_000_000)
        let earlier = PlannedWindow(
            providerID: .claude,
            startAt: base,
            durationSeconds: Int(Self.fiveHours),
            status: .scheduled
        )
        let candidate = PlannedWindow(
            providerID: .claude,
            startAt: earlier.endAt.addingTimeInterval(90 * 60),
            durationSeconds: Int(Self.fiveHours)
        )
        let result = PlannedWindowValidator.validate(
            candidate: candidate,
            against: [earlier],
            actualWindows: []
        )
        let risk = try #require(result.chainRisk)
        #expect(risk.previousWindowEnd == earlier.endAt)
    }

    @Test("Chain risk ignores other providers, terminal planned windows, and itself")
    func chainRiskIgnoresIrrelevantWindows() {
        let base = Date(timeIntervalSince1970: 1_730_000_000)
        let otherProviderActual = actualEnding(
            at: base.addingTimeInterval(-3600),
            providerID: .codex
        )
        let cancelled = PlannedWindow(
            providerID: .claude,
            startAt: base.addingTimeInterval(-Self.fiveHours - 3600),
            durationSeconds: Int(Self.fiveHours),
            status: .cancelled
        )
        let candidate = PlannedWindow(
            providerID: .claude,
            startAt: base,
            durationSeconds: Int(Self.fiveHours)
        )
        let result = PlannedWindowValidator.validate(
            candidate: candidate,
            against: [cancelled, candidate],
            actualWindows: [otherProviderActual]
        )
        #expect(result.chainRisk == nil)
    }
}
