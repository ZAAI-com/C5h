import Foundation
import Testing
@testable import C5hCore

@Suite("UsageFetcher")
struct UsageFetcherTests {
    @Test("Derives Claude 5h and 7d rows separately")
    func derivesClaudeWindowsSeparately() throws {
        let snapshot = UsageSnapshot(
            providerID: .claude,
            capturedAt: Date(timeIntervalSince1970: 100),
            rawJSON: """
            {"rate_limits":{"five_hour":{"used_percentage":20,"resets_at":1778373600},"seven_day":{"used_percentage":57,"resets_at":1778893200}}}
            """,
            normalizedJSON: "{}"
        )
        let fetcher = makeFetcher()

        let derived5h = try fetcher.derived5h(from: snapshot, now: Date(timeIntervalSince1970: 0))
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

        // Weekly (secondary) is always anchored — should still derive.
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

    @Test("Skips Claude 5h row when the report is idle (0% used)")
    func skipsClaudeIdleWindow() throws {
        // Claude's statusLine keeps reporting a rolling five_hour boundary while
        // idle (used_percentage 0). Deriving a window from it would fabricate a
        // phantom 5h window on every poll.
        let snapshot = makeClaudeIdleSnapshot()
        let fetcher = makeFetcher()

        let derived5h = try fetcher.derived5h(from: snapshot, now: Date(timeIntervalSince1970: 0))
        #expect(derived5h == nil)
    }

    @Test("Anchors Claude 5h row at 0% when requireActiveWindow is false (trigger path)")
    func anchorsClaudeIdleWindowForTrigger() throws {
        // A wake prompt just opened this window on purpose, so the trigger path
        // anchors it even before usage registers.
        let snapshot = makeClaudeIdleSnapshot()
        let fetcher = makeFetcher()

        let derived5h = try fetcher.derived5h(
            from: snapshot,
            now: Date(timeIntervalSince1970: 0),
            requireActiveWindow: false
        )
        let window = try #require(derived5h)
        #expect(window.endAt.timeIntervalSince1970 == 1_778_373_600)
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

    private func makeClaudeIdleSnapshot() -> UsageSnapshot {
        UsageSnapshot(
            providerID: .claude,
            capturedAt: Date(timeIntervalSince1970: 100),
            rawJSON: """
            {"rate_limits":{"five_hour":{"used_percentage":0,"resets_at":1778373600},"seven_day":{"used_percentage":7,"resets_at":1778893200}}}
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
