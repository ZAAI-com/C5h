import Foundation
import Testing
@testable import C5hCore

@Suite("UsageFetcher")
struct UsageFetcherTests {
    @Test("Derives Claude 5h and 7d rows separately")
    func derivesClaudeWindowsSeparately() throws {
        let capturedAt = Date(timeIntervalSince1970: 1_778_373_600 - (4 * 3600))
        let snapshot = UsageSnapshot(
            providerID: .claude,
            capturedAt: capturedAt,
            rawJSON: """
            {"rate_limits":{"five_hour":{"used_percentage":20,"resets_at":1778373600},"seven_day":{"used_percentage":57,"resets_at":1778893200}}}
            """,
            normalizedJSON: "{}"
        )
        let fetcher = makeFetcher()

        let derived5h = try fetcher.derived5h(from: snapshot, now: capturedAt)
        let derived7d = try fetcher.derived7d(from: snapshot)
        let fiveHour = try #require(derived5h)
        let weekly = try #require(derived7d)

        #expect(fiveHour.durationSeconds == 5 * 3600)
        #expect(fiveHour.endAt.timeIntervalSince1970 == 1_778_373_600)
        #expect(weekly.durationSeconds == 7 * 24 * 3600)
        #expect(weekly.usedPercentage == 57)
        #expect(weekly.usageSnapshotID == snapshot.id)
    }

    @Test("Skips Codex 5h row when primary window is synthetic (no real window started)")
    func skipsCodexSyntheticPrimaryWindow() throws {
        // `codex app-server` returns `resetsAt = capturedAt + 18000` when no
        // real 5h window has anchored. Treating that as an active window would
        // produce a phantom row whose end slides with the clock on every poll.
        let capturedAt = Date(timeIntervalSince1970: 1_779_408_036)
        let syntheticResetsAt = capturedAt.addingTimeInterval(18_000).timeIntervalSince1970
        let snapshot = UsageSnapshot(
            providerID: .codex,
            capturedAt: capturedAt,
            rawJSON: """
            {"rateLimits":{"primary":{"usedPercent":1,"windowDurationMins":300,"resetsAt":\(Int(syntheticResetsAt))},"secondary":{"usedPercent":30,"windowDurationMins":10080,"resetsAt":1779838110},"planType":"plus"}}
            """,
            normalizedJSON: "{}"
        )
        let fetcher = makeFetcher()

        let derived5h = try fetcher.derived5h(from: snapshot, now: capturedAt)
        #expect(derived5h == nil)

        // Weekly (secondary) is always anchored, so it should still derive.
        let weekly = try #require(try fetcher.derived7d(from: snapshot))
        #expect(weekly.usedPercentage == 30)
    }

    @Test("Derives Codex 5h row when primary window is anchored")
    func derivesCodexAnchoredPrimaryWindow() throws {
        // A real anchored window: resetsAt is fixed at first-usage + 5h, so
        // `resetsAt - capturedAt` is < primaryDuration as the window ages.
        let capturedAt = Date(timeIntervalSince1970: 1_779_438_857)
        let anchoredResetsAt = 1_779_455_535 // 16678s ahead of capturedAt
        let snapshot = UsageSnapshot(
            providerID: .codex,
            capturedAt: capturedAt,
            rawJSON: """
            {"rateLimits":{"primary":{"usedPercent":1,"windowDurationMins":300,"resetsAt":\(anchoredResetsAt)},"secondary":{"usedPercent":30,"windowDurationMins":10080,"resetsAt":1779838110},"planType":"plus"}}
            """,
            normalizedJSON: "{}"
        )
        let fetcher = makeFetcher()

        let derived5h = try #require(try fetcher.derived5h(from: snapshot, now: capturedAt))
        #expect(derived5h.durationSeconds == 5 * 3600)
        #expect(derived5h.endAt.timeIntervalSince1970 == TimeInterval(anchoredResetsAt))
    }

    @Test("Skips the synthetic Codex weekly slot no usage has anchored")
    func skipsCodexSyntheticWeeklySlot() throws {
        // A weekly-only Codex account reports the weekly limit in the primary
        // slot, and while idle it returns `resetsAt = capturedAt + 7d` at 0%.
        // Persisting that inserted one weekly row per poll.
        let capturedAt = Date(timeIntervalSince1970: 1_788_505_603)
        let syntheticResetsAt = capturedAt
            .addingTimeInterval(TimeInterval(CodexUsageStatus.defaultSecondaryDurationSeconds))
            .timeIntervalSince1970
        let snapshot = UsageSnapshot(
            providerID: .codex,
            capturedAt: capturedAt,
            rawJSON: """
            {"rateLimits":{"primary":{"usedPercent":0,"windowDurationMins":10080,"resetsAt":\(Int(syntheticResetsAt))},"secondary":null,"planType":"pro"}}
            """,
            normalizedJSON: "{}"
        )
        let fetcher = makeFetcher()

        #expect(try fetcher.derived7d(from: snapshot) == nil)
    }

    @Test("Keeps the Codex weekly window once usage anchors it")
    func keepsAnchoredCodexWeeklyWindow() throws {
        // The moment real usage lands, the reported reset stops tracking the
        // clock: `resetsAt - capturedAt` falls below one full week.
        let capturedAt = Date(timeIntervalSince1970: 1_788_505_603)
        let anchoredResetsAt = capturedAt
            .addingTimeInterval(TimeInterval(CodexUsageStatus.defaultSecondaryDurationSeconds) - 14_400)
            .timeIntervalSince1970
        let snapshot = UsageSnapshot(
            providerID: .codex,
            capturedAt: capturedAt,
            rawJSON: """
            {"rateLimits":{"primary":{"usedPercent":1,"windowDurationMins":10080,"resetsAt":\(Int(anchoredResetsAt))},"secondary":null,"planType":"pro"}}
            """,
            normalizedJSON: "{}"
        )
        let fetcher = makeFetcher()

        let weekly = try #require(try fetcher.derived7d(from: snapshot))
        #expect(weekly.usedPercentage == 1)
    }

    @Test("Keeps a weekly slot with synthetic timing that already reports usage")
    func keepsSyntheticallyTimedCodexWeeklyWindowWithUsage() throws {
        // Timing alone is not proof: a real window can report a reset almost
        // exactly one duration out. Consumption settles it.
        let capturedAt = Date(timeIntervalSince1970: 1_788_505_603)
        let resetsAt = capturedAt
            .addingTimeInterval(TimeInterval(CodexUsageStatus.defaultSecondaryDurationSeconds))
            .timeIntervalSince1970
        let snapshot = UsageSnapshot(
            providerID: .codex,
            capturedAt: capturedAt,
            rawJSON: """
            {"rateLimits":{"primary":{"usedPercent":97,"windowDurationMins":10080,"resetsAt":\(Int(resetsAt))},"secondary":null,"planType":"pro"}}
            """,
            normalizedJSON: "{}"
        )
        let fetcher = makeFetcher()

        let weekly = try #require(try fetcher.derived7d(from: snapshot))
        #expect(weekly.usedPercentage == 97)
    }

    @Test("Derives Codex secondary row as weekly data")
    func derivesCodexWeeklyWindow() throws {
        let snapshot = UsageSnapshot(
            providerID: .codex,
            capturedAt: Date(timeIntervalSince1970: 100),
            rawJSON: """
            {"timestamp":"2026-05-09T20:19:03.777Z","rate_limits":{"primary":{"used_percent":82,"window_minutes":300,"resets_at":1778364750},"secondary":{"used_percent":45,"window_minutes":10080,"resets_at":1778968800}}}
            """,
            normalizedJSON: "{}"
        )
        let fetcher = makeFetcher()

        let derived5h = try fetcher.derived5h(from: snapshot, now: Date(timeIntervalSince1970: 0))
        let derived7d = try fetcher.derived7d(from: snapshot)
        let fiveHour = try #require(derived5h)
        let weekly = try #require(derived7d)

        #expect(fiveHour.durationSeconds == 5 * 3600)
        #expect(weekly.durationSeconds == 10080 * 60)
        #expect(weekly.usedPercentage == 45)
        #expect(weekly.usageSnapshotID == snapshot.id)
    }

    @Test("Drops 5h row when both Codex slots are weekly")
    func dropsFiveHourRowWhenBothCodexSlotsAreWeekly() throws {
        let snapshot = UsageSnapshot(
            providerID: .codex,
            capturedAt: Date(timeIntervalSince1970: 1_779_300_000),
            rawJSON: """
            {"rateLimits":{"primary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":1779838000},"secondary":{"usedPercent":30,"windowDurationMins":10080,"resetsAt":1779838110},"planType":"plus"}}
            """,
            normalizedJSON: "{}"
        )
        let fetcher = makeFetcher()

        let derived5h = try fetcher.derived5h(from: snapshot, now: snapshot.capturedAt)
        let weekly = try #require(try fetcher.derived7d(from: snapshot))

        #expect(derived5h == nil)
        #expect(weekly.usedPercentage == 30)
        #expect(weekly.endAt.timeIntervalSince1970 == 1_779_838_110)
    }

    @Test("Routes primary-only Codex weekly slot to 7d row")
    func routesPrimaryOnlyCodexWeeklySlot() throws {
        let snapshot = UsageSnapshot(
            providerID: .codex,
            capturedAt: Date(timeIntervalSince1970: 1_779_300_000),
            rawJSON: """
            {"rateLimits":{"primary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":1779838000},"planType":"plus"}}
            """,
            normalizedJSON: "{}"
        )
        let fetcher = makeFetcher()

        let derived5h = try fetcher.derived5h(from: snapshot, now: snapshot.capturedAt)
        let weekly = try #require(try fetcher.derived7d(from: snapshot))

        #expect(derived5h == nil)
        #expect(weekly.usedPercentage == 20)
        #expect(weekly.endAt.timeIntervalSince1970 == 1_779_838_000)
    }

    @Test("Uses short secondary Codex slot and respects active-window requirement")
    func usesShortSecondaryCodexSlot() throws {
        let capturedAt = Date(timeIntervalSince1970: 1_779_300_000)
        let syntheticReset = Int(capturedAt.addingTimeInterval(18_000).timeIntervalSince1970)
        let snapshot = UsageSnapshot(
            providerID: .codex,
            capturedAt: capturedAt,
            rawJSON: """
            {"rateLimits":{"primary":{"usedPercent":30,"windowDurationMins":10080,"resetsAt":1779838110},"secondary":{"usedPercent":1,"windowDurationMins":300,"resetsAt":\(syntheticReset)},"planType":"plus"}}
            """,
            normalizedJSON: "{}"
        )
        let fetcher = makeFetcher()

        let activeOnly = try fetcher.derived5h(from: snapshot, now: capturedAt)
        let triggerAnchored = try #require(try fetcher.derived5h(
            from: snapshot,
            now: capturedAt,
            requireActiveWindow: false
        ))

        #expect(activeOnly == nil)
        #expect(triggerAnchored.durationSeconds == 5 * 3600)
        #expect(triggerAnchored.endAt.timeIntervalSince1970 == TimeInterval(syntheticReset))
    }

    @Test("Derives Claude 5h row from a 0% timer whose start has stopped sliding")
    func derivesClaudeZeroUsageTimer() throws {
        // 3:58 remaining puts the reported start well over a slide step before
        // capture: the boundary has settled, so a 0% report is a real window
        // used below Claude's reporting resolution.
        let snapshot = makeClaudeSnapshot(remaining: (3 * 3600) + (58 * 60))
        let fetcher = makeFetcher()

        let window = try #require(try fetcher.derived5h(
            from: snapshot,
            now: snapshot.capturedAt
        ))

        #expect(window.startAt.timeIntervalSince1970 == 1_778_355_600)
        #expect(window.endAt.timeIntervalSince1970 == 1_778_373_600)
    }

    @Test("Skips the prospective Claude slot the provider slides forward while idle")
    func skipsProspectiveClaudeSlot() throws {
        // 4:58 remaining: the reported start is 120s before capture at 0% used,
        // the shape Claude re-issues on every poll while the account is idle.
        let snapshot = makeClaudeSnapshot(remaining: (4 * 3600) + (58 * 60))
        let fetcher = makeFetcher()

        #expect(try fetcher.derived5h(from: snapshot, now: snapshot.capturedAt) == nil)
    }

    @Test("Two consecutive idle slides derive no window at all")
    func skipsConsecutiveClaudeSlides() throws {
        let fetcher = makeFetcher()
        // The live regression: each poll reported a start on the next 10-minute
        // grid step, so every poll inserted a row with a different reset end.
        for remaining in [(4 * 3600) + (58 * 60), (4 * 3600) + (52 * 60)] {
            let snapshot = makeClaudeSnapshot(remaining: TimeInterval(remaining))
            #expect(try fetcher.derived5h(from: snapshot, now: snapshot.capturedAt) == nil)
        }
    }

    @Test("Anchors the prospective Claude slot for a trigger")
    func anchorsProspectiveClaudeSlotForTrigger() throws {
        let snapshot = makeClaudeSnapshot(remaining: (4 * 3600) + (58 * 60))
        let fetcher = makeFetcher()

        // A wake prompt just opened this window, so the trigger path force-
        // anchors it even though a routine poll would drop it.
        let window = try #require(try fetcher.derived5h(
            from: snapshot,
            now: snapshot.capturedAt,
            requireActiveWindow: false
        ))

        #expect(window.startAt.timeIntervalSince1970 == 1_778_355_600)
    }

    @Test("Keeps a fresh Claude window that already reports consumption")
    func keepsFreshClaudeWindowWithUsage() throws {
        // Same fresh start as the prospective slot, but with usage recorded: the
        // window is real and must not be dropped.
        let snapshot = makeClaudeSnapshot(
            remaining: (4 * 3600) + (58 * 60),
            usedPercentage: 7
        )
        let fetcher = makeFetcher()

        #expect(try fetcher.derived5h(from: snapshot, now: snapshot.capturedAt) != nil)
    }

    @Test("Keeps the idle boundary Claude chains onto a previous window's end")
    func keepsChainedClaudeBoundary() throws {
        // A chained boundary reports 0% with a start that is already well in the
        // past, so it stays a real window (usage arriving hours later lands in
        // it). Only the sliding slot is dropped.
        let snapshot = makeClaudeSnapshot(remaining: (3 * 3600) + (40 * 60))
        let fetcher = makeFetcher()

        #expect(try fetcher.derived5h(from: snapshot, now: snapshot.capturedAt) != nil)
    }

    @Test("Keeps a Claude window that was live at capture after delayed processing")
    func keepsClaudeTimerAfterDelayedProcessing() throws {
        let snapshot = makeClaudeSnapshot(remaining: 60)
        let processedAt = snapshot.capturedAt.addingTimeInterval(120)
        let fetcher = makeFetcher()

        let window = try #require(try fetcher.derived5h(
            from: snapshot,
            now: processedAt
        ))

        #expect(window.endAt < processedAt)
    }

    @Test("Accepts Claude countdown at five hours plus clock tolerance")
    func acceptsClaudeTimerAtUpperBound() throws {
        let remaining = TimeInterval(
            ClaudeUsageStatus.fiveHourDurationSeconds
                + ClaudeUsageStatus.fiveHourTimerToleranceSeconds
        )
        // Reports consumption so this stays a test of the clock-skew bound in
        // `hasLiveFiveHourTimer` rather than of the prospective-slot guard (the
        // reported start lands 60s after capture, well inside a slide step).
        let snapshot = makeClaudeSnapshot(remaining: remaining, usedPercentage: 3)
        let fetcher = makeFetcher()

        let window = try fetcher.derived5h(
            from: snapshot,
            now: snapshot.capturedAt
        )

        #expect(window != nil)
    }

    @Test("Rejects Claude countdown that expired at capture time")
    func rejectsExpiredClaudeTimer() throws {
        let snapshot = makeClaudeSnapshot(remaining: 0)
        let fetcher = makeFetcher()

        let window = try fetcher.derived5h(
            from: snapshot,
            now: snapshot.capturedAt
        )

        #expect(window == nil)
    }

    @Test("Rejects Claude countdown beyond five hours plus clock tolerance")
    func rejectsTooDistantClaudeTimer() throws {
        let remaining = TimeInterval(
            ClaudeUsageStatus.fiveHourDurationSeconds
                + ClaudeUsageStatus.fiveHourTimerToleranceSeconds
                + 1
        )
        let snapshot = makeClaudeSnapshot(remaining: remaining)
        let fetcher = makeFetcher()

        let regularWindow = try fetcher.derived5h(
            from: snapshot,
            now: snapshot.capturedAt
        )
        let triggerWindow = try fetcher.derived5h(
            from: snapshot,
            now: snapshot.capturedAt,
            requireActiveWindow: false
        )

        #expect(regularWindow == nil)
        #expect(triggerWindow == nil)
    }

    @Test("Secondary-only Codex snapshot persists weekly row without 5h row")
    func secondaryOnlyCodexSnapshot() throws {
        let snapshot = UsageSnapshot(
            providerID: .codex,
            capturedAt: Date(timeIntervalSince1970: 100),
            rawJSON: """
            {"timestamp":"2026-05-09T20:19:03.777Z","rate_limits":{"secondary":{"used_percent":45,"window_minutes":10080,"resets_at":1778968800}}}
            """,
            normalizedJSON: "{}"
        )
        let fetcher = makeFetcher()

        let derived5h = try fetcher.derived5h(from: snapshot, now: Date(timeIntervalSince1970: 0))
        let weekly = try #require(try fetcher.derived7d(from: snapshot))

        #expect(derived5h == nil)
        #expect(weekly.durationSeconds == 10080 * 60)
        #expect(weekly.usedPercentage == 45)
        #expect(weekly.usageSnapshotID == snapshot.id)
    }

    private func makeClaudeSnapshot(
        remaining: TimeInterval,
        usedPercentage: Double = 0
    ) -> UsageSnapshot {
        let resetAt: TimeInterval = 1_778_373_600
        return UsageSnapshot(
            providerID: .claude,
            capturedAt: Date(timeIntervalSince1970: resetAt - remaining),
            rawJSON: """
            {"rate_limits":{"five_hour":{"used_percentage":\(usedPercentage),"resets_at":\(Int(resetAt))},"seven_day":{"used_percentage":7,"resets_at":1778893200}}}
            """,
            normalizedJSON: "{}"
        )
    }

    private func makeFetcher() -> UsageFetcher {
        UsageFetcher(
            persistSnapshot: { _ in },
            upsertActualWindow5h: { _, _ in },
            upsertActualWindow7d: { _, _ in }
        )
    }
}
