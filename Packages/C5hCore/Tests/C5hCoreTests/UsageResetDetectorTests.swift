import Foundation
import Testing
@testable import C5hCore

@Suite("UsageResetDetector")
struct UsageResetDetectorTests {
    // Anchor times: a 5h window that resets at R1, sampled before/after.
    private let r1: TimeInterval = 1_778_373_600
    private let sevenDayEnd: TimeInterval = 1_778_893_200

    @Test("Normal 5h rollover is not a reset")
    func normalFiveHourRolloverIsNotReset() {
        // First sample sits inside the window (before R1); the second is captured
        // at/after R1 with the next window's reset end. That is a rollover.
        let before = claudeSnapshot(
            fiveHourPercent: 80,
            fiveHourResetsAt: r1,
            capturedAt: Date(timeIntervalSince1970: r1 - 3_600)
        )
        let after = claudeSnapshot(
            fiveHourPercent: 5,
            fiveHourResetsAt: r1 + 18_000,
            capturedAt: Date(timeIntervalSince1970: r1 + 60)
        )
        let series = UsageHistorySeries(providerID: .claude, snapshots: [before, after])

        let events = UsageResetDetector.detect(in: series).filter { $0.kind == .fiveHour }
        #expect(events.isEmpty)
    }

    @Test("Early 5h reset is detected")
    func earlyFiveHourResetIsDetected() {
        // The reset end moves while the previous window is still open: a reset.
        let prev = claudeSnapshot(
            fiveHourPercent: 90,
            fiveHourResetsAt: r1,
            capturedAt: Date(timeIntervalSince1970: r1 - 13_600)
        )
        let newEnd = r1 - 9_400
        let curr = claudeSnapshot(
            fiveHourPercent: 4,
            fiveHourResetsAt: newEnd,
            capturedAt: Date(timeIntervalSince1970: r1 - 8_600)
        )
        let series = UsageHistorySeries(providerID: .claude, snapshots: [prev, curr])

        let events = UsageResetDetector.detect(in: series).filter { $0.kind == .fiveHour }
        #expect(events.count == 1)
        let event = events.first
        #expect(event?.previousResetEnd == Date(timeIntervalSince1970: r1))
        #expect(event?.newResetEnd == Date(timeIntervalSince1970: newEnd))
        #expect(event?.detectedAt == Date(timeIntervalSince1970: r1 - 8_600))
    }

    @Test("Codex synthetic sliding 5h ends are not resets")
    func codexSyntheticSlidingFiveHourEndsAreIgnored() {
        let firstCapture = Date(timeIntervalSince1970: r1 - 20_000)
        let secondCapture = firstCapture.addingTimeInterval(120)
        let first = codexSnapshot(
            fiveHourPercent: 1,
            fiveHourResetsAt: firstCapture.addingTimeInterval(18_000).timeIntervalSince1970,
            capturedAt: firstCapture
        )
        let second = codexSnapshot(
            fiveHourPercent: 1,
            fiveHourResetsAt: secondCapture.addingTimeInterval(18_000).timeIntervalSince1970,
            capturedAt: secondCapture
        )
        let series = UsageHistorySeries(providerID: .codex, snapshots: [first, second])

        #expect(series.points.map(\.hasActiveFiveHourWindow) == [false, false])
        let events = UsageResetDetector.detect(in: series).filter { $0.kind == .fiveHour }
        #expect(events.isEmpty)
    }

    @Test("Codex synthetic to anchored 5h window is not a reset")
    func codexSyntheticToAnchoredFiveHourWindowIsIgnored() {
        let firstCapture = Date(timeIntervalSince1970: r1 - 20_000)
        let secondCapture = firstCapture.addingTimeInterval(120)
        let first = codexSnapshot(
            fiveHourPercent: 1,
            fiveHourResetsAt: firstCapture.addingTimeInterval(18_000).timeIntervalSince1970,
            capturedAt: firstCapture
        )
        let second = codexSnapshot(
            fiveHourPercent: 3,
            fiveHourResetsAt: firstCapture.addingTimeInterval(17_000).timeIntervalSince1970,
            capturedAt: secondCapture
        )
        let series = UsageHistorySeries(providerID: .codex, snapshots: [first, second])

        #expect(series.points.map(\.hasActiveFiveHourWindow) == [false, true])
        let events = UsageResetDetector.detect(in: series).filter { $0.kind == .fiveHour }
        #expect(events.isEmpty)
    }

    @Test("7d sharp percentage drop against an unchanged end is detected")
    func sevenDaySharpDropIsDetected() {
        let prev = claudeSnapshot(
            fiveHourPercent: 50,
            fiveHourResetsAt: r1,
            sevenDayPercent: 60,
            sevenDayResetsAt: sevenDayEnd,
            capturedAt: Date(timeIntervalSince1970: r1 - 10_000)
        )
        let curr = claudeSnapshot(
            fiveHourPercent: 50,
            fiveHourResetsAt: r1,
            sevenDayPercent: 25,
            sevenDayResetsAt: sevenDayEnd,
            capturedAt: Date(timeIntervalSince1970: r1 - 9_000)
        )
        let series = UsageHistorySeries(providerID: .claude, snapshots: [prev, curr])

        let events = UsageResetDetector.detect(in: series).filter { $0.kind == .sevenDay }
        #expect(events.count == 1)
        #expect(events.first?.previousResetEnd == Date(timeIntervalSince1970: sevenDayEnd))
        #expect(events.first?.newResetEnd == Date(timeIntervalSince1970: sevenDayEnd))
    }

    @Test("Normal 7d increase is ignored")
    func normalSevenDayIncreaseIsIgnored() {
        let prev = claudeSnapshot(
            fiveHourPercent: 50,
            fiveHourResetsAt: r1,
            sevenDayPercent: 20,
            sevenDayResetsAt: sevenDayEnd,
            capturedAt: Date(timeIntervalSince1970: r1 - 10_000)
        )
        let curr = claudeSnapshot(
            fiveHourPercent: 50,
            fiveHourResetsAt: r1,
            sevenDayPercent: 34,
            sevenDayResetsAt: sevenDayEnd,
            capturedAt: Date(timeIntervalSince1970: r1 - 9_000)
        )
        let series = UsageHistorySeries(providerID: .claude, snapshots: [prev, curr])

        let events = UsageResetDetector.detect(in: series)
        #expect(events.isEmpty)
    }

    private func claudeSnapshot(
        fiveHourPercent: Double,
        fiveHourResetsAt: TimeInterval,
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
        fiveHourPercent: Double,
        fiveHourResetsAt: TimeInterval,
        sevenDayPercent: Double? = nil,
        sevenDayResetsAt: TimeInterval = 1_778_893_200,
        capturedAt: Date
    ) -> UsageSnapshot {
        let sevenDayFragment: String
        if let sevenDayPercent {
            sevenDayFragment = ",\"secondary\":{\"usedPercent\":\(sevenDayPercent),"
                + "\"windowDurationMins\":10080,"
                + "\"resetsAt\":\(Int(sevenDayResetsAt))}"
        } else {
            sevenDayFragment = ""
        }
        let json = "{\"rateLimits\":{\"primary\":{\"usedPercent\":\(fiveHourPercent),"
            + "\"windowDurationMins\":300,"
            + "\"resetsAt\":\(Int(fiveHourResetsAt))}"
            + "\(sevenDayFragment),\"planType\":\"plus\"}}"
        return UsageSnapshot(
            providerID: .codex,
            capturedAt: capturedAt,
            rawJSON: json,
            normalizedJSON: ""
        )
    }
}
