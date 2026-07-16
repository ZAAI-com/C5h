import Foundation
import Testing
@testable import C5hCore

@Suite("UsageHistorySeries")
struct UsageHistorySeriesTests {
    @Test("Builds Claude series sorted by capturedAt and parses 5h + 7d")
    func buildsClaudeSeries() {
        let early = claudeSnapshot(
            fiveHourPercent: 10,
            fiveHourResetsAt: 1_778_373_600,
            sevenDayPercent: 30,
            sevenDayResetsAt: 1_778_893_200,
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )
        let late = claudeSnapshot(
            fiveHourPercent: 42,
            fiveHourResetsAt: 1_778_373_600,
            sevenDayPercent: 57,
            sevenDayResetsAt: 1_778_893_200,
            capturedAt: Date(timeIntervalSince1970: 5_000)
        )

        // Pass out-of-order to verify sorting.
        let series = UsageHistorySeries(providerID: .claude, snapshots: [late, early])

        #expect(series.points.count == 2)
        #expect(series.points[0].capturedAt.timeIntervalSince1970 == 1_000)
        #expect(series.points[0].fiveHour == 10)
        #expect(series.points[0].sevenDay == 30)
        #expect(series.points[1].fiveHour == 42)
        #expect(series.points[1].sevenDay == 57)
    }

    @Test("Builds Codex series from current payload shape")
    func buildsCodexSeries() {
        let snapshot = codexSnapshot(
            primaryPercent: 82,
            primaryResetsAt: 1_778_364_750,
            secondaryPercent: 45,
            secondaryResetsAt: 1_778_968_800,
            capturedAt: Date(timeIntervalSince1970: 2_000)
        )

        let series = UsageHistorySeries(providerID: .codex, snapshots: [snapshot])

        #expect(series.points.count == 1)
        #expect(series.points[0].fiveHour == 82)
        #expect(series.points[0].sevenDay == 45)
    }

    @Test("Classifies primary-only weekly Codex readings as 7d history")
    func buildsPrimaryOnlyWeeklyCodexSeries() {
        let snapshot = UsageSnapshot(
            providerID: .codex,
            capturedAt: Date(timeIntervalSince1970: 2_000),
            rawJSON: """
            {"timestamp":"2026-07-15T10:54:55.483Z","rate_limits":{"primary":{"used_percent":13,"window_minutes":10080,"resets_at":1784666161}}}
            """,
            normalizedJSON: "{}"
        )

        let series = UsageHistorySeries(providerID: .codex, snapshots: [snapshot])

        #expect(series.points.count == 1)
        #expect(series.points[0].fiveHour == nil)
        #expect(series.points[0].sevenDay == 13)
        #expect(series.points[0].fiveHourResetsAt == nil)
        #expect(series.points[0].hasActiveFiveHourWindow == false)
        #expect(series.points[0].sevenDayResetsAt?.timeIntervalSince1970 == 1_784_666_161)
    }

    @Test("sevenDayPercent returns nil before any point")
    func sevenDayPercentBeforeAnyPoint() {
        let snapshot = claudeSnapshot(
            fiveHourPercent: 10,
            sevenDayPercent: 30,
            capturedAt: Date(timeIntervalSince1970: 5_000)
        )
        let series = UsageHistorySeries(providerID: .claude, snapshots: [snapshot])

        #expect(series.sevenDayPercent(at: Date(timeIntervalSince1970: 1_000)) == nil)
    }

    @Test("sevenDayPercent returns latest-<=-time when between points")
    func sevenDayPercentBetweenPoints() {
        let early = claudeSnapshot(
            fiveHourPercent: 10,
            sevenDayPercent: 30,
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )
        let mid = claudeSnapshot(
            fiveHourPercent: 20,
            sevenDayPercent: 40,
            capturedAt: Date(timeIntervalSince1970: 2_000)
        )
        let late = claudeSnapshot(
            fiveHourPercent: 30,
            sevenDayPercent: 50,
            capturedAt: Date(timeIntervalSince1970: 3_000)
        )
        let series = UsageHistorySeries(providerID: .claude, snapshots: [early, mid, late])

        let result = series.sevenDayPercent(at: Date(timeIntervalSince1970: 2_500))
        #expect(result?.value == 40)
        #expect(result?.asOf.timeIntervalSince1970 == 2_000)
    }

    @Test("sevenDayPercent returns the latest point when time is after all points")
    func sevenDayPercentAfterLastPoint() {
        // The series itself doesn't know about "now". It returns the latest
        // point with capturedAt <= time. View-layer code is responsible for
        // suppressing the value when the target time is in the future relative
        // to `now`.
        let snapshot = claudeSnapshot(
            fiveHourPercent: 10,
            sevenDayPercent: 30,
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )
        let series = UsageHistorySeries(providerID: .claude, snapshots: [snapshot])

        let result = series.sevenDayPercent(at: Date(timeIntervalSince1970: 9_999))
        #expect(result?.value == 30)
        #expect(result?.asOf.timeIntervalSince1970 == 1_000)
    }

    @Test("Empty snapshots produces empty series")
    func emptySnapshots() {
        let series = UsageHistorySeries(providerID: .claude, snapshots: [])
        #expect(series.points.isEmpty)
        #expect(series.latest == nil)
        #expect(series.latestFiveHourPoint() == nil)
        #expect(series.sevenDayPercent(at: .now) == nil)
    }

    @Test("Unparseable rawJSON is skipped without throwing")
    func skipsUnparseable() {
        let garbage = UsageSnapshot(
            providerID: .claude,
            capturedAt: Date(timeIntervalSince1970: 1_000),
            rawJSON: "{ not valid json }",
            normalizedJSON: ""
        )
        let good = claudeSnapshot(
            fiveHourPercent: 11,
            sevenDayPercent: 22,
            capturedAt: Date(timeIntervalSince1970: 2_000)
        )

        let series = UsageHistorySeries(providerID: .claude, snapshots: [garbage, good])

        #expect(series.points.count == 1)
        #expect(series.points[0].fiveHour == 11)
    }

    @Test("Filters out snapshots from other providers")
    func filtersOtherProviders() {
        let claude = claudeSnapshot(
            fiveHourPercent: 11,
            sevenDayPercent: 22,
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )
        let codex = codexSnapshot(
            primaryPercent: 33,
            secondaryPercent: 44,
            capturedAt: Date(timeIntervalSince1970: 2_000)
        )

        let claudeSeries = UsageHistorySeries(providerID: .claude, snapshots: [claude, codex])
        let codexSeries = UsageHistorySeries(providerID: .codex, snapshots: [claude, codex])

        #expect(claudeSeries.points.count == 1)
        #expect(claudeSeries.points[0].fiveHour == 11)
        #expect(codexSeries.points.count == 1)
        #expect(codexSeries.points[0].fiveHour == 33)
    }

    @Test("latestFiveHourPoint returns last point with a 5h value")
    func latestFiveHourPointSkipsMissing() {
        let withFive = claudeSnapshot(
            fiveHourPercent: 7,
            sevenDayPercent: 8,
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )
        // Build a synthetic point with no 5h via the alternate initializer.
        let synthetic = UsagePoint(
            capturedAt: Date(timeIntervalSince1970: 2_000),
            fiveHour: nil,
            sevenDay: 9
        )
        let parsed = UsageHistorySeries(providerID: .claude, snapshots: [withFive])
        let combined = UsageHistorySeries(
            providerID: .claude,
            points: parsed.points + [synthetic]
        )

        let latest = combined.latestFiveHourPoint()
        #expect(latest?.value == 7)
        #expect(latest?.asOf.timeIntervalSince1970 == 1_000)
    }

    @Test("fiveHourPercent is anchored to time, not the global latest point")
    func fiveHourPercentAtTime() {
        let t0 = claudeSnapshot(
            fiveHourPercent: 10,
            sevenDayPercent: 30,
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )
        let t1 = claudeSnapshot(
            fiveHourPercent: 42,
            sevenDayPercent: 40,
            capturedAt: Date(timeIntervalSince1970: 2_000)
        )
        let t2 = claudeSnapshot(
            fiveHourPercent: 92,
            sevenDayPercent: 50,
            capturedAt: Date(timeIntervalSince1970: 3_000)
        )
        let series = UsageHistorySeries(providerID: .claude, snapshots: [t0, t1, t2])

        // Before any point: nil.
        #expect(series.fiveHourPercent(at: Date(timeIntervalSince1970: 500)) == nil)

        // At t0 and between t0/t1: the t0 reading.
        #expect(series.fiveHourPercent(at: Date(timeIntervalSince1970: 1_000))?.value == 10)
        let between = series.fiveHourPercent(at: Date(timeIntervalSince1970: 2_500))
        #expect(between?.value == 42)
        #expect(between?.asOf.timeIntervalSince1970 == 2_000)

        // At/after t2: the t2 reading. Distinct from earlier anchors: the bug
        // was every window collapsing to this single latest value.
        #expect(series.fiveHourPercent(at: Date(timeIntervalSince1970: 9_999))?.value == 92)
    }

    @Test("fiveHourPercent skips points without a 5h value")
    func fiveHourPercentSkipsMissing() {
        let withFive = claudeSnapshot(
            fiveHourPercent: 7,
            sevenDayPercent: 8,
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )
        let synthetic = UsagePoint(
            capturedAt: Date(timeIntervalSince1970: 2_000),
            fiveHour: nil,
            sevenDay: 9
        )
        let parsed = UsageHistorySeries(providerID: .claude, snapshots: [withFive])
        let combined = UsageHistorySeries(
            providerID: .claude,
            points: parsed.points + [synthetic]
        )

        // Anchoring at t=2_000 (which has no 5h) falls back to the t=1_000 reading.
        let result = combined.fiveHourPercent(at: Date(timeIntervalSince1970: 2_000))
        #expect(result?.value == 7)
        #expect(result?.asOf.timeIntervalSince1970 == 1_000)
    }

    @Test("usageReading ignores stale samples before lower bound")
    func usageReadingIgnoresStaleSamplesBeforeLowerBound() {
        let stale = claudeSnapshot(
            fiveHourPercent: 15,
            sevenDayPercent: 25,
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )
        let series = UsageHistorySeries(providerID: .claude, snapshots: [stale])

        let result = series.usageReading(
            atOrBefore: Date(timeIntervalSince1970: 3_000),
            notBefore: Date(timeIntervalSince1970: 2_000)
        )

        #expect(result == nil)
    }

    @Test("usageReading returns in-window 5h and same-snapshot 7d")
    func usageReadingReturnsSameSnapshotValues() {
        let reading = claudeSnapshot(
            fiveHourPercent: 31,
            sevenDayPercent: 44,
            capturedAt: Date(timeIntervalSince1970: 1_500)
        )
        let series = UsageHistorySeries(providerID: .claude, snapshots: [reading])

        let result = series.usageReading(
            atOrBefore: Date(timeIntervalSince1970: 2_000),
            notBefore: Date(timeIntervalSince1970: 1_000)
        )

        #expect(result?.capturedAt.timeIntervalSince1970 == 1_500)
        #expect(result?.fiveHour == 31)
        #expect(result?.sevenDay == 44)
    }

    @Test("usageReading skips samples without 5h")
    func usageReadingSkipsMissingFiveHour() {
        let withFive = UsagePoint(
            capturedAt: Date(timeIntervalSince1970: 1_000),
            fiveHour: 12,
            sevenDay: 22
        )
        let withoutFive = UsagePoint(
            capturedAt: Date(timeIntervalSince1970: 2_000),
            fiveHour: nil,
            sevenDay: 33
        )
        let series = UsageHistorySeries(
            providerID: .claude,
            points: [withFive, withoutFive]
        )

        let result = series.usageReading(
            atOrBefore: Date(timeIntervalSince1970: 2_000),
            notBefore: Date(timeIntervalSince1970: 500)
        )

        #expect(result?.capturedAt.timeIntervalSince1970 == 1_000)
        #expect(result?.fiveHour == 12)
        #expect(result?.sevenDay == 22)
    }

    @Test("usageReading returns latest valid in-window sample")
    func usageReadingReturnsLatestValidInWindowSample() {
        let beforeWindow = claudeSnapshot(
            fiveHourPercent: 10,
            sevenDayPercent: 20,
            capturedAt: Date(timeIntervalSince1970: 900)
        )
        let early = claudeSnapshot(
            fiveHourPercent: 21,
            sevenDayPercent: 31,
            capturedAt: Date(timeIntervalSince1970: 1_100)
        )
        let latest = claudeSnapshot(
            fiveHourPercent: 42,
            sevenDayPercent: 52,
            capturedAt: Date(timeIntervalSince1970: 1_800)
        )
        let future = claudeSnapshot(
            fiveHourPercent: 99,
            sevenDayPercent: 99,
            capturedAt: Date(timeIntervalSince1970: 2_500)
        )
        let series = UsageHistorySeries(
            providerID: .claude,
            snapshots: [future, beforeWindow, latest, early]
        )

        let result = series.usageReading(
            atOrBefore: Date(timeIntervalSince1970: 2_000),
            notBefore: Date(timeIntervalSince1970: 1_000)
        )

        #expect(result?.capturedAt.timeIntervalSince1970 == 1_800)
        #expect(result?.fiveHour == 42)
        #expect(result?.sevenDay == 52)
    }

    @Test("openingReading returns the earliest sample within the window")
    func openingReadingReturnsEarliestInWindow() {
        let opening = claudeSnapshot(
            fiveHourPercent: 10,
            sevenDayPercent: 20,
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )
        let slightlyLater = claudeSnapshot(
            fiveHourPercent: 21,
            sevenDayPercent: 31,
            capturedAt: Date(timeIntervalSince1970: 1_100)
        )
        let outside = claudeSnapshot(
            fiveHourPercent: 99,
            sevenDayPercent: 99,
            capturedAt: Date(timeIntervalSince1970: 1_300)
        )
        let series = UsageHistorySeries(
            providerID: .claude,
            snapshots: [outside, opening, slightlyLater]
        )

        let result = series.openingReading(
            at: Date(timeIntervalSince1970: 1_000),
            within: 200
        )

        #expect(result?.capturedAt.timeIntervalSince1970 == 1_000)
        #expect(result?.fiveHour == 10)
        #expect(result?.sevenDay == 20)
    }

    @Test("openingReading returns nil when no sample falls in the window")
    func openingReadingReturnsNilOutsideWindow() {
        let snapshot = claudeSnapshot(
            fiveHourPercent: 10,
            sevenDayPercent: 20,
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )
        let series = UsageHistorySeries(providerID: .claude, snapshots: [snapshot])

        let result = series.openingReading(
            at: Date(timeIntervalSince1970: 5_000),
            within: 200
        )

        #expect(result == nil)
    }

    @Test("openingReading does not require a 5h value")
    func openingReadingAllows7dOnlySample() {
        let sevenDayOnly = UsagePoint(
            capturedAt: Date(timeIntervalSince1970: 1_000),
            fiveHour: nil,
            sevenDay: 30
        )
        let series = UsageHistorySeries(providerID: .claude, points: [sevenDayOnly])

        let result = series.openingReading(
            at: Date(timeIntervalSince1970: 1_000),
            within: 200
        )

        #expect(result?.capturedAt.timeIntervalSince1970 == 1_000)
        #expect(result?.fiveHour == nil)
        #expect(result?.sevenDay == 30)
    }

    @Test("firstFiveHourReaching returns the first sample at or above threshold")
    func firstFiveHourReachingReturnsFirstAtThreshold() {
        let below = claudeSnapshot(
            fiveHourPercent: 50,
            sevenDayPercent: 10,
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )
        let firstFull = claudeSnapshot(
            fiveHourPercent: 100,
            sevenDayPercent: 20,
            capturedAt: Date(timeIntervalSince1970: 2_000)
        )
        let stillFull = claudeSnapshot(
            fiveHourPercent: 100,
            sevenDayPercent: 25,
            capturedAt: Date(timeIntervalSince1970: 3_000)
        )
        let series = UsageHistorySeries(
            providerID: .claude,
            snapshots: [below, firstFull, stillFull]
        )

        let result = series.firstFiveHourReaching(
            100,
            from: Date(timeIntervalSince1970: 500),
            to: Date(timeIntervalSince1970: 4_000)
        )

        #expect(result?.capturedAt.timeIntervalSince1970 == 2_000)
        #expect(result?.fiveHour == 100)
        #expect(result?.sevenDay == 20)
    }

    @Test("firstFiveHourReaching rounds the 5h value before comparing")
    func firstFiveHourReachingRounds() {
        let nearlyFull = claudeSnapshot(
            fiveHourPercent: 99.6,
            sevenDayPercent: 20,
            capturedAt: Date(timeIntervalSince1970: 1_500)
        )
        let series = UsageHistorySeries(providerID: .claude, snapshots: [nearlyFull])

        let result = series.firstFiveHourReaching(
            100,
            from: Date(timeIntervalSince1970: 500),
            to: Date(timeIntervalSince1970: 4_000)
        )

        #expect(result?.capturedAt.timeIntervalSince1970 == 1_500)
    }

    @Test("firstFiveHourReaching returns nil when the threshold is never reached")
    func firstFiveHourReachingNeverReached() {
        let low = claudeSnapshot(
            fiveHourPercent: 60,
            sevenDayPercent: 10,
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )
        let series = UsageHistorySeries(providerID: .claude, snapshots: [low])

        let result = series.firstFiveHourReaching(
            100,
            from: Date(timeIntervalSince1970: 500),
            to: Date(timeIntervalSince1970: 4_000)
        )

        #expect(result == nil)
    }

    @Test("firstFiveHourReaching ignores samples outside the range")
    func firstFiveHourReachingIgnoresOutOfRange() {
        let beforeRange = claudeSnapshot(
            fiveHourPercent: 100,
            sevenDayPercent: 10,
            capturedAt: Date(timeIntervalSince1970: 100)
        )
        let inRange = claudeSnapshot(
            fiveHourPercent: 100,
            sevenDayPercent: 20,
            capturedAt: Date(timeIntervalSince1970: 2_000)
        )
        let afterRange = claudeSnapshot(
            fiveHourPercent: 100,
            sevenDayPercent: 30,
            capturedAt: Date(timeIntervalSince1970: 9_000)
        )
        let series = UsageHistorySeries(
            providerID: .claude,
            snapshots: [beforeRange, inRange, afterRange]
        )

        let result = series.firstFiveHourReaching(
            100,
            from: Date(timeIntervalSince1970: 500),
            to: Date(timeIntervalSince1970: 4_000)
        )

        #expect(result?.capturedAt.timeIntervalSince1970 == 2_000)
        #expect(result?.sevenDay == 20)
    }

    @Test("scoped keeps only points reporting the window's own reset end")
    func scopedKeepsOwnWindowPoints() {
        let oldWindowReading = claudeSnapshot(
            fiveHourPercent: 19,
            fiveHourResetsAt: 40_200,
            capturedAt: Date(timeIntervalSince1970: 27_120)
        )
        let oldWindowCap = claudeSnapshot(
            fiveHourPercent: 100,
            fiveHourResetsAt: 40_200,
            capturedAt: Date(timeIntervalSince1970: 29_760)
        )
        let newWindowReading = claudeSnapshot(
            fiveHourPercent: 4,
            fiveHourResetsAt: 47_400,
            capturedAt: Date(timeIntervalSince1970: 30_060)
        )
        let series = UsageHistorySeries(
            providerID: .claude,
            snapshots: [oldWindowReading, oldWindowCap, newWindowReading]
        )

        let scopedOld = series.scoped(
            toFiveHourWindowEndingAt: Date(timeIntervalSince1970: 40_200)
        )
        let scopedNew = series.scoped(
            toFiveHourWindowEndingAt: Date(timeIntervalSince1970: 47_400)
        )

        #expect(scopedOld.points.map(\.fiveHour) == [19, 100])
        #expect(scopedNew.points.map(\.fiveHour) == [4])
    }

    @Test("Regression: a tier-change recalibration does not pin the old 100% in the new window")
    func tierChangeDoesNotPinOldCapInNewWindow() {
        // 2026-07-04 incident: the old window (ending 40_200) capped at 100%,
        // the user upgraded their plan, and the provider re-anchored a new
        // window (ending 47_400) whose retroactive start predates the capped
        // snapshot. Scoping must keep that snapshot out of the new window's
        // readings so the block follows the live post-upgrade values.
        let oldWindowReading = claudeSnapshot(
            fiveHourPercent: 19,
            fiveHourResetsAt: 40_200,
            capturedAt: Date(timeIntervalSince1970: 27_120)
        )
        let oldWindowCap = claudeSnapshot(
            fiveHourPercent: 100,
            fiveHourResetsAt: 40_200,
            capturedAt: Date(timeIntervalSince1970: 29_760)
        )
        let newWindowReading = claudeSnapshot(
            fiveHourPercent: 4,
            fiveHourResetsAt: 47_400,
            capturedAt: Date(timeIntervalSince1970: 30_060)
        )
        let series = UsageHistorySeries(
            providerID: .claude,
            snapshots: [oldWindowReading, oldWindowCap, newWindowReading]
        )
        let newWindowStart = Date(timeIntervalSince1970: 29_400)
        let now = Date(timeIntervalSince1970: 30_600)

        let scopedNew = series.scoped(
            toFiveHourWindowEndingAt: Date(timeIntervalSince1970: 47_400)
        )

        #expect(scopedNew.trailingFiveHourRunStart(
            reaching: 100,
            from: newWindowStart,
            to: now
        ) == nil)
        #expect(scopedNew.firstFiveHourReaching(100, from: newWindowStart, to: now) == nil)
        let latest = scopedNew.usageReading(atOrBefore: now, notBefore: newWindowStart)
        #expect(latest?.capturedAt.timeIntervalSince1970 == 30_060)
        #expect(latest?.fiveHour == 4)
    }

    @Test("scoped applies the reset-end tolerance and drops unanchored points")
    func scopedToleranceAndUnanchoredPoints() {
        let end = Date(timeIntervalSince1970: 40_200)
        let withinTolerance = UsagePoint(
            capturedAt: Date(timeIntervalSince1970: 1_000),
            fiveHour: 10,
            sevenDay: nil,
            fiveHourResetsAt: end.addingTimeInterval(30)
        )
        let beyondTolerance = UsagePoint(
            capturedAt: Date(timeIntervalSince1970: 2_000),
            fiveHour: 20,
            sevenDay: nil,
            fiveHourResetsAt: end.addingTimeInterval(90)
        )
        let noResetEnd = UsagePoint(
            capturedAt: Date(timeIntervalSince1970: 3_000),
            fiveHour: 30,
            sevenDay: nil
        )
        let syntheticFreshSlot = UsagePoint(
            capturedAt: Date(timeIntervalSince1970: 4_000),
            fiveHour: 40,
            sevenDay: nil,
            fiveHourResetsAt: end,
            hasActiveFiveHourWindow: false
        )
        let series = UsageHistorySeries(
            providerID: .codex,
            points: [withinTolerance, beyondTolerance, noResetEnd, syntheticFreshSlot]
        )

        let scoped = series.scoped(toFiveHourWindowEndingAt: end)

        #expect(scoped.points.map(\.fiveHour) == [10])
    }

    @Test("trailingFiveHourRunStart returns the first sample of the trailing capped run")
    func trailingRunStartReturnsRunStart() {
        let below = claudeSnapshot(
            fiveHourPercent: 50,
            sevenDayPercent: 10,
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )
        let firstFull = claudeSnapshot(
            fiveHourPercent: 100,
            sevenDayPercent: 20,
            capturedAt: Date(timeIntervalSince1970: 2_000)
        )
        let stillFullRounded = claudeSnapshot(
            fiveHourPercent: 99.6,
            sevenDayPercent: 25,
            capturedAt: Date(timeIntervalSince1970: 3_000)
        )
        let series = UsageHistorySeries(
            providerID: .claude,
            snapshots: [below, firstFull, stillFullRounded]
        )

        let result = series.trailingFiveHourRunStart(
            reaching: 100,
            from: Date(timeIntervalSince1970: 500),
            to: Date(timeIntervalSince1970: 4_000)
        )

        #expect(result?.capturedAt.timeIntervalSince1970 == 2_000)
        #expect(result?.fiveHour == 100)
        #expect(result?.sevenDay == 20)
    }

    @Test("trailingFiveHourRunStart unpins after a same-end re-baseline")
    func trailingRunStartUnpinsAfterRebaseline() {
        let capped = claudeSnapshot(
            fiveHourPercent: 100,
            sevenDayPercent: 20,
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )
        let rebaselined = claudeSnapshot(
            fiveHourPercent: 30,
            sevenDayPercent: 21,
            capturedAt: Date(timeIntervalSince1970: 2_000)
        )
        let series = UsageHistorySeries(providerID: .claude, snapshots: [capped, rebaselined])

        let result = series.trailingFiveHourRunStart(
            reaching: 100,
            from: Date(timeIntervalSince1970: 500),
            to: Date(timeIntervalSince1970: 4_000)
        )

        #expect(result == nil)
    }

    @Test("trailingFiveHourRunStart skips samples without a 5h value inside the run")
    func trailingRunStartSkipsMissingFiveHour() {
        let capped = claudeSnapshot(
            fiveHourPercent: 100,
            sevenDayPercent: 20,
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )
        let sevenDayOnly = UsagePoint(
            capturedAt: Date(timeIntervalSince1970: 2_000),
            fiveHour: nil,
            sevenDay: 30
        )
        let stillCapped = claudeSnapshot(
            fiveHourPercent: 100,
            sevenDayPercent: 40,
            capturedAt: Date(timeIntervalSince1970: 3_000)
        )
        let parsed = UsageHistorySeries(providerID: .claude, snapshots: [capped, stillCapped])
        let series = UsageHistorySeries(
            providerID: .claude,
            points: parsed.points + [sevenDayOnly]
        )

        let result = series.trailingFiveHourRunStart(
            reaching: 100,
            from: Date(timeIntervalSince1970: 500),
            to: Date(timeIntervalSince1970: 4_000)
        )

        #expect(result?.capturedAt.timeIntervalSince1970 == 1_000)
    }

    @Test("trailingFiveHourRunStart ignores samples outside the range")
    func trailingRunStartIgnoresOutOfRange() {
        let beforeRange = claudeSnapshot(
            fiveHourPercent: 100,
            sevenDayPercent: 10,
            capturedAt: Date(timeIntervalSince1970: 100)
        )
        let inRange = claudeSnapshot(
            fiveHourPercent: 100,
            sevenDayPercent: 20,
            capturedAt: Date(timeIntervalSince1970: 2_000)
        )
        let afterRange = claudeSnapshot(
            fiveHourPercent: 30,
            sevenDayPercent: 30,
            capturedAt: Date(timeIntervalSince1970: 9_000)
        )
        let series = UsageHistorySeries(
            providerID: .claude,
            snapshots: [beforeRange, inRange, afterRange]
        )

        let result = series.trailingFiveHourRunStart(
            reaching: 100,
            from: Date(timeIntervalSince1970: 500),
            to: Date(timeIntervalSince1970: 4_000)
        )

        #expect(result?.capturedAt.timeIntervalSince1970 == 2_000)
        #expect(result?.sevenDay == 20)
    }

    @Test("A scoped series with no confirming points yields nil readings")
    func scopedEmptySeriesYieldsNilReadings() {
        let foreign = claudeSnapshot(
            fiveHourPercent: 100,
            fiveHourResetsAt: 40_200,
            sevenDayPercent: 50,
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )
        let series = UsageHistorySeries(providerID: .claude, snapshots: [foreign])

        let scoped = series.scoped(
            toFiveHourWindowEndingAt: Date(timeIntervalSince1970: 99_999)
        )

        #expect(scoped.points.isEmpty)
        #expect(scoped.usageReading(
            atOrBefore: Date(timeIntervalSince1970: 2_000),
            notBefore: Date(timeIntervalSince1970: 500)
        ) == nil)
        #expect(scoped.openingReading(at: Date(timeIntervalSince1970: 500), within: 240) == nil)
        #expect(scoped.trailingFiveHourRunStart(
            reaching: 100,
            from: Date(timeIntervalSince1970: 500),
            to: Date(timeIntervalSince1970: 2_000)
        ) == nil)
        #expect(scoped.fiveHourPercent(at: Date(timeIntervalSince1970: 2_000)) == nil)
        #expect(scoped.sevenDayPercent(at: Date(timeIntervalSince1970: 2_000)) == nil)
    }

    @Test("A scoped weekly series keeps only matching reset-end points")
    func scopedWeeklySeriesFiltersByResetEnd() {
        let matching = codexSnapshot(
            primaryPercent: 10,
            secondaryPercent: 30,
            secondaryResetsAt: 1_778_968_800,
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )
        let foreign = codexSnapshot(
            primaryPercent: 20,
            secondaryPercent: 40,
            secondaryResetsAt: 1_779_000_000,
            capturedAt: Date(timeIntervalSince1970: 2_000)
        )
        let series = UsageHistorySeries(providerID: .codex, snapshots: [matching, foreign])

        let scoped = series.scoped(toWeeklyWindowEndingAt: Date(timeIntervalSince1970: 1_778_968_800))

        #expect(scoped.points.count == 1)
        #expect(scoped.points[0].sevenDay == 30)
    }

    @Test("weeklyOpeningReading returns carry-in from before segment start")
    func weeklyOpeningReadingUsesLatestBeforeStart() {
        let beforeDay = codexSnapshot(
            primaryPercent: nil,
            secondaryPercent: 100,
            secondaryResetsAt: 1_778_968_800,
            capturedAt: Date(timeIntervalSince1970: 500)
        )
        let onDay = codexSnapshot(
            primaryPercent: nil,
            secondaryPercent: 10,
            secondaryResetsAt: 1_778_968_800,
            capturedAt: Date(timeIntervalSince1970: 2_000)
        )
        let series = UsageHistorySeries(providerID: .codex, snapshots: [beforeDay, onDay])
            .scoped(toWeeklyWindowEndingAt: Date(timeIntervalSince1970: 1_778_968_800))

        let carryIn = series.weeklyOpeningReading(
            at: Date(timeIntervalSince1970: 1_500),
            within: 60
        )

        #expect(carryIn?.used == 100)
    }

    @Test("weeklyOpeningReading skips newer points without weekly data")
    func weeklyOpeningReadingSearchesPastMissingWeeklyValues() {
        let weekly = UsagePoint(
            capturedAt: Date(timeIntervalSince1970: 500),
            fiveHour: nil,
            sevenDay: 42
        )
        let newerWithoutWeekly = UsagePoint(
            capturedAt: Date(timeIntervalSince1970: 1_000),
            fiveHour: 10,
            sevenDay: nil
        )
        let series = UsageHistorySeries(
            providerID: .codex,
            points: [weekly, newerWithoutWeekly]
        )

        let carryIn = series.weeklyOpeningReading(
            at: Date(timeIntervalSince1970: 1_500),
            within: 60
        )

        #expect(carryIn?.used == 42)
        #expect(carryIn?.capturedAt == weekly.capturedAt)
    }

    @Test("latestDistinctWeeklyReading skips carry-in value on the same day")
    func latestDistinctWeeklyReadingFindsChangedValue() {
        let dayStart = Date(timeIntervalSince1970: 86_400)
        let early = codexSnapshot(
            primaryPercent: nil,
            secondaryPercent: 100,
            secondaryResetsAt: 1_778_968_800,
            capturedAt: dayStart.addingTimeInterval(100)
        )
        let later = codexSnapshot(
            primaryPercent: nil,
            secondaryPercent: 10,
            secondaryResetsAt: 1_778_968_800,
            capturedAt: dayStart.addingTimeInterval(7_200)
        )
        let series = UsageHistorySeries(providerID: .codex, snapshots: [early, later])
            .scoped(toWeeklyWindowEndingAt: Date(timeIntervalSince1970: 1_778_968_800))

        let reading = series.latestDistinctWeeklyReading(on: dayStart, carryInUsed: 100)

        #expect(reading?.used == 10)
        #expect(reading?.capturedAt == dayStart.addingTimeInterval(7_200))
    }

    @Test("weeklyReadings keeps only points inside the interval")
    func weeklyReadingsFiltersOutsideInterval() {
        let series = UsageHistorySeries(providerID: .codex, points: [
            UsagePoint(capturedAt: Date(timeIntervalSince1970: 1_000), fiveHour: nil, sevenDay: 10),
            UsagePoint(capturedAt: Date(timeIntervalSince1970: 2_000), fiveHour: nil, sevenDay: 20),
            UsagePoint(capturedAt: Date(timeIntervalSince1970: 3_000), fiveHour: nil, sevenDay: 30),
        ])

        let readings = series.weeklyReadings(in: DateInterval(
            start: Date(timeIntervalSince1970: 1_500),
            end: Date(timeIntervalSince1970: 2_500)
        ))

        #expect(readings.count == 1)
        #expect(readings[0].capturedAt.timeIntervalSince1970 == 2_000)
        #expect(readings[0].used == 20)
    }

    @Test("weeklyReadings collapses consecutive equal rounded percentages")
    func weeklyReadingsCollapsesEqualPercentages() {
        // 1.0 and 1.4 both display as 1%; 2.0 and 2.2 both display as 2%. A value
        // polled repeatedly without a visible change should not stack rows.
        let series = UsageHistorySeries(providerID: .codex, points: [
            UsagePoint(capturedAt: Date(timeIntervalSince1970: 1_000), fiveHour: nil, sevenDay: 1.0),
            UsagePoint(capturedAt: Date(timeIntervalSince1970: 2_000), fiveHour: nil, sevenDay: 1.4),
            UsagePoint(capturedAt: Date(timeIntervalSince1970: 3_000), fiveHour: nil, sevenDay: 2.0),
            UsagePoint(capturedAt: Date(timeIntervalSince1970: 4_000), fiveHour: nil, sevenDay: 2.2),
        ])

        let readings = series.weeklyReadings(in: DateInterval(
            start: Date(timeIntervalSince1970: 500),
            end: Date(timeIntervalSince1970: 5_000)
        ))

        #expect(readings.count == 2)
        #expect(readings[0].capturedAt.timeIntervalSince1970 == 1_000)
        #expect(readings[0].used == 1.0)
        #expect(readings[1].capturedAt.timeIntervalSince1970 == 3_000)
        #expect(readings[1].used == 2.0)
    }

    @Test("weeklyReadings skips points without a 7d value")
    func weeklyReadingsSkipsMissingSevenDay() {
        let series = UsageHistorySeries(providerID: .codex, points: [
            UsagePoint(capturedAt: Date(timeIntervalSince1970: 1_000), fiveHour: 50, sevenDay: nil),
            UsagePoint(capturedAt: Date(timeIntervalSince1970: 2_000), fiveHour: nil, sevenDay: 5),
        ])

        let readings = series.weeklyReadings(in: DateInterval(
            start: Date(timeIntervalSince1970: 500),
            end: Date(timeIntervalSince1970: 3_000)
        ))

        #expect(readings.count == 1)
        #expect(readings[0].capturedAt.timeIntervalSince1970 == 2_000)
        #expect(readings[0].used == 5)
    }

    @Test("weeklyReadings is empty when the interval ends before the first point")
    func weeklyReadingsEmptyForFutureInterval() {
        // Mirrors the Tomorrow column, where the whole visible segment is after the
        // latest capture: no readings, so the block draws no future values.
        let series = UsageHistorySeries(providerID: .codex, points: [
            UsagePoint(capturedAt: Date(timeIntervalSince1970: 5_000), fiveHour: nil, sevenDay: 10),
        ])

        let readings = series.weeklyReadings(in: DateInterval(
            start: Date(timeIntervalSince1970: 1_000),
            end: Date(timeIntervalSince1970: 2_000)
        ))

        #expect(readings.isEmpty)
    }

    @Test("ProviderUsageLimits marks Codex secondary-only snapshots")
    func providerUsageLimitsWeeklyOnly() {
        let snapshot = UsageSnapshot(
            providerID: .codex,
            capturedAt: Date(timeIntervalSince1970: 100),
            rawJSON: """
            {"timestamp":"2026-05-09T20:19:03.777Z","rate_limits":{"secondary":{"used_percent":45,"window_minutes":10080,"resets_at":1778968800}}}
            """,
            normalizedJSON: "{}"
        )

        let limits = ProviderUsageLimits.from(snapshot: snapshot)

        #expect(limits?.hasFiveHourLimit == false)
        #expect(limits?.hasWeeklyLimit == true)
        #expect(limits?.isWeeklyOnly == true)
    }

    @Test("ProviderUsageLimits marks a weekly-length Codex primary as weekly-only")
    func providerUsageLimitsWeeklyOnlyInPrimarySlot() {
        // Weekly-only Codex accounts report the 7-day limit in the primary slot
        // (window_minutes 10080) with no secondary. Classification must be by
        // duration, not slot, so this counts as weekly-only, not a 5h limit.
        let snapshot = UsageSnapshot(
            providerID: .codex,
            capturedAt: Date(timeIntervalSince1970: 100),
            rawJSON: """
            {"timestamp":"2026-07-15T10:54:55.483Z","rate_limits":{"primary":{"used_percent":13,"window_minutes":10080,"resets_at":1784666161}}}
            """,
            normalizedJSON: "{}"
        )

        let limits = ProviderUsageLimits.from(snapshot: snapshot)

        #expect(limits?.hasFiveHourLimit == false)
        #expect(limits?.hasWeeklyLimit == true)
        #expect(limits?.isWeeklyOnly == true)
    }

    @Test("ProviderUsageLimits marks a normal Codex 5h+weekly snapshot")
    func providerUsageLimitsFiveHourAndWeekly() {
        let snapshot = codexSnapshot(
            primaryPercent: 20,
            secondaryPercent: 45,
            capturedAt: Date(timeIntervalSince1970: 100)
        )

        let limits = ProviderUsageLimits.from(snapshot: snapshot)

        #expect(limits?.hasFiveHourLimit == true)
        #expect(limits?.hasWeeklyLimit == true)
        #expect(limits?.isWeeklyOnly == false)
    }

    // MARK: - Helpers

    private func claudeSnapshot(
        fiveHourPercent: Double,
        fiveHourResetsAt: TimeInterval = 1_778_373_600,
        sevenDayPercent: Double? = nil,
        sevenDayResetsAt: TimeInterval = 1_778_893_200,
        capturedAt: Date
    ) -> UsageSnapshot {
        let sevenDayFragment: String
        if let sevenDayPercent {
            sevenDayFragment = #","seven_day":{"used_percentage":\#(sevenDayPercent),"resets_at":\#(Int(sevenDayResetsAt))}"#
        } else {
            sevenDayFragment = ""
        }
        let json = #"{"rate_limits":{"five_hour":{"used_percentage":\#(fiveHourPercent),"resets_at":\#(Int(fiveHourResetsAt))}\#(sevenDayFragment)}}"#
        return UsageSnapshot(
            providerID: .claude,
            capturedAt: capturedAt,
            rawJSON: json,
            normalizedJSON: ""
        )
    }

    private func codexSnapshot(
        primaryPercent: Double?,
        primaryResetsAt: TimeInterval = 1_778_364_750,
        secondaryPercent: Double? = nil,
        secondaryResetsAt: TimeInterval = 1_778_968_800,
        capturedAt: Date
    ) -> UsageSnapshot {
        let timestampString = DateTimeService.formatUTC(capturedAt)
        var parts: [String] = []
        if let primaryPercent {
            parts.append(#""primary":{"used_percent":\#(primaryPercent),"window_minutes":300,"resets_at":\#(Int(primaryResetsAt))}"#)
        }
        if let secondaryPercent {
            parts.append(#""secondary":{"used_percent":\#(secondaryPercent),"window_minutes":10080,"resets_at":\#(Int(secondaryResetsAt))}"#)
        }
        let rateLimitsBody = parts.joined(separator: ",")
        let json = #"{"timestamp":"\#(timestampString)","rate_limits":{\#(rateLimitsBody)}}"#
        return UsageSnapshot(
            providerID: .codex,
            capturedAt: capturedAt,
            rawJSON: json,
            normalizedJSON: ""
        )
    }
}
