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
        primaryPercent: Double,
        primaryResetsAt: TimeInterval = 1_778_364_750,
        secondaryPercent: Double? = nil,
        secondaryResetsAt: TimeInterval = 1_778_968_800,
        capturedAt: Date
    ) -> UsageSnapshot {
        let timestampString = DateTimeService.formatUTC(capturedAt)
        let secondaryFragment: String
        if let secondaryPercent {
            secondaryFragment = #","secondary":{"used_percent":\#(secondaryPercent),"window_minutes":10080,"resets_at":\#(Int(secondaryResetsAt))}"#
        } else {
            secondaryFragment = ""
        }
        let json = #"{"timestamp":"\#(timestampString)","rate_limits":{"primary":{"used_percent":\#(primaryPercent),"window_minutes":300,"resets_at":\#(Int(primaryResetsAt))}\#(secondaryFragment)}}"#
        return UsageSnapshot(
            providerID: .codex,
            capturedAt: capturedAt,
            rawJSON: json,
            normalizedJSON: ""
        )
    }
}
