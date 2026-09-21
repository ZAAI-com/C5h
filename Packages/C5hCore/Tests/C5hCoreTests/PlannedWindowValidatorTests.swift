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

    @Test("A window moved onto itself does not conflict with itself")
    func movedWindowExcludesItself() {
        let base = Date(timeIntervalSince1970: 1_730_000_000)
        let existing = PlannedWindow(
            providerID: .claude,
            startAt: base,
            durationSeconds: 5 * 3600
        )
        // Dragging a window keeps its id, so its own stored row must not count
        // as a conflict at the new position.
        var moved = existing
        moved.startAt = base.addingTimeInterval(3600)
        let result = PlannedWindowValidator.validate(
            candidate: moved,
            against: [existing],
            actualWindows: []
        )
        #expect(!result.hasConflict)
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

    @Test("Chain risk uses the provider's observed slot length")
    func chainRiskUsesObservedSlotLength() throws {
        // Codex reports its 5h-class duration through window_minutes, so the
        // slot is not always 300 minutes. A 240-minute observed window must
        // project a 240-minute chained boundary, not a five-hour one.
        let previousEnd = Date(timeIntervalSince1970: 1_730_000_000)
        let fourHours: TimeInterval = 4 * 3600
        let previous = ActualWindow5h(
            providerID: .codex,
            startAt: previousEnd.addingTimeInterval(-fourHours),
            durationSeconds: Int(fourHours),
            source: .detectedFromUsage,
            confidence: .estimated
        )
        let candidate = PlannedWindow(
            providerID: .codex,
            startAt: previousEnd.addingTimeInterval(3600),
            durationSeconds: Int(fourHours)
        )

        let risk = try #require(PlannedWindowValidator.validate(
            candidate: candidate,
            against: [],
            actualWindows: [previous]
        ).chainRisk)

        #expect(risk.projectedEffectiveEnd == previousEnd.addingTimeInterval(fourHours))
        #expect(risk.shortfallSeconds == 3600)

        // A gap of a full observed slot is safe even though it is under 5h.
        let safe = PlannedWindow(
            providerID: .codex,
            startAt: previousEnd.addingTimeInterval(fourHours),
            durationSeconds: Int(fourHours)
        )
        #expect(PlannedWindowValidator.validate(
            candidate: safe, against: [], actualWindows: [previous]
        ).chainRisk == nil)
    }

    @Test("Chain risk sees a previous window supplied from before the day")
    func chainRiskSeesPreviousDayWindow() throws {
        // A window ending at 23:00 and a plan at 00:30: the day-bounded render
        // query cannot see the previous window, so the caller must supply it.
        let previousEnd = Date(timeIntervalSince1970: 1_730_000_000)
        let candidate = PlannedWindow(
            providerID: .claude,
            startAt: previousEnd.addingTimeInterval(90 * 60),
            durationSeconds: Int(Self.fiveHours)
        )

        #expect(PlannedWindowValidator.validate(
            candidate: candidate, against: [], actualWindows: []
        ).chainRisk == nil)
        let risk = try #require(PlannedWindowValidator.validate(
            candidate: candidate,
            against: [],
            actualWindows: [actualEnding(at: previousEnd)]
        ).chainRisk)
        #expect(risk.previousWindowEnd == previousEnd)
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

    @Test("Chain risk uses the fixed provider slot instead of candidate duration")
    func chainRiskUsesFixedProviderSlot() throws {
        let previousEnd = Date(timeIntervalSince1970: 1_730_000_000)
        let candidate = PlannedWindow(
            providerID: .claude,
            startAt: previousEnd.addingTimeInterval(4 * 3600),
            durationSeconds: 2 * 3600
        )

        let risk = try #require(PlannedWindowValidator.validate(
            candidate: candidate,
            against: [],
            actualWindows: [actualEnding(at: previousEnd)]
        ).chainRisk)

        #expect(risk.projectedEffectiveEnd == previousEnd.addingTimeInterval(Self.fiveHours))
        #expect(risk.shortfallSeconds == 3600)
    }

    @Test("Chain risk is absent when the candidate ends at the provider boundary")
    func chainRiskAbsentWhenCandidateDoesNotExceedBoundary() {
        let previousEnd = Date(timeIntervalSince1970: 1_730_000_000)
        let candidate = PlannedWindow(
            providerID: .claude,
            startAt: previousEnd.addingTimeInterval(4 * 3600),
            durationSeconds: 3600
        )

        #expect(PlannedWindowValidator.validate(
            candidate: candidate,
            against: [],
            actualWindows: [actualEnding(at: previousEnd)]
        ).chainRisk == nil)
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

    @Test("Earlier plans project a fixed five-hour provider boundary")
    func chainRiskProjectsFixedBoundaryForEarlierPlan() throws {
        let base = Date(timeIntervalSince1970: 1_730_000_000)
        let earlier = PlannedWindow(
            providerID: .claude,
            startAt: base,
            durationSeconds: 3600,
            status: .scheduled
        )
        let candidate = PlannedWindow(
            providerID: .claude,
            startAt: base.addingTimeInterval(6 * 3600),
            durationSeconds: Int(Self.fiveHours)
        )

        let risk = try #require(PlannedWindowValidator.validate(
            candidate: candidate,
            against: [earlier],
            actualWindows: []
        ).chainRisk)

        #expect(risk.previousWindowEnd == base.addingTimeInterval(Self.fiveHours))
        #expect(risk.projectedEffectiveEnd == base.addingTimeInterval(2 * Self.fiveHours))
        #expect(risk.shortfallSeconds == 3600)
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

    @Test("Chain risk ignores manually entered actual windows")
    func chainRiskIgnoresManualActualWindow() {
        // A user-entered manual window is not a provider-reported chain
        // boundary, so planning inside its slot must not raise the advisory.
        let previousEnd = Date(timeIntervalSince1970: 1_730_000_000)
        let manual = ActualWindow5h(
            providerID: .claude,
            startAt: previousEnd.addingTimeInterval(-Self.fiveHours),
            durationSeconds: Int(Self.fiveHours),
            source: .manual,
            confidence: .estimated
        )
        let candidate = PlannedWindow(
            providerID: .claude,
            startAt: previousEnd.addingTimeInterval(80 * 60),
            durationSeconds: Int(Self.fiveHours)
        )
        #expect(PlannedWindowValidator.validate(
            candidate: candidate, against: [], actualWindows: [manual]
        ).chainRisk == nil)
    }

    @Test("Chain risk ignores earlier draft planned windows")
    func chainRiskIgnoresDraftPlannedWindow() {
        // A draft has no scheduled prompt and will not open a real block, so its
        // projected end must not seed the advisory (only .scheduled windows do).
        let base = Date(timeIntervalSince1970: 1_730_000_000)
        let draft = PlannedWindow(
            providerID: .claude,
            startAt: base,
            durationSeconds: Int(Self.fiveHours),
            status: .draft
        )
        let candidate = PlannedWindow(
            providerID: .claude,
            startAt: draft.endAt.addingTimeInterval(90 * 60),
            durationSeconds: Int(Self.fiveHours)
        )
        #expect(PlannedWindowValidator.validate(
            candidate: candidate, against: [draft], actualWindows: []
        ).chainRisk == nil)
    }
}
