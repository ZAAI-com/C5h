import Foundation
import Testing
@testable import C5hCore

@Suite("ClaudeUsageStatus")
struct ClaudeUsageStatusTests {
    @Test("Parses five hour reset from statusLine payload")
    func parsesFiveHourReset() throws {
        let status = try ClaudeUsageStatus.parsePayload("""
        {"rate_limits":{"five_hour":{"used_percentage":20,"resets_at":1778373600}}}
        """)

        #expect(status.fiveHour.usedPercentage == 20)
        #expect(status.fiveHour.resetsAt.timeIntervalSince1970 == 1_778_373_600)
        #expect(status.fiveHourStartAt.timeIntervalSince1970 == 1_778_355_600)
    }

    @Test("Builds estimated ActualWindow5h from reset timestamp")
    func buildsActualWindow() throws {
        let status = try ClaudeUsageStatus.parsePayload("""
        {"rate_limits":{"five_hour":{"used_percentage":20,"resets_at":1778373600}}}
        """)
        let window = status.actualWindow(createdAt: Date(timeIntervalSince1970: 100))

        #expect(window.providerID == .claude)
        #expect(window.source == .detectedFromUsage)
        #expect(window.confidence == .estimated)
        #expect(window.durationSeconds == 5 * 3600)
        #expect(window.startAt.timeIntervalSince1970 == 1_778_355_600)
        #expect(window.endAt.timeIntervalSince1970 == 1_778_373_600)
    }

    @Test("Treats a plausible Claude countdown as live regardless of percentage")
    func validatesLiveFiveHourTimer() {
        let capturedAt = Date(timeIntervalSince1970: 1_000)
        let fourHoursFiftyEightMinutes: TimeInterval = (4 * 60 * 60) + (58 * 60)
        let zeroPercent = ClaudeUsageStatus(
            fiveHour: RateLimitWindow(
                usedPercentage: 0,
                resetsAt: capturedAt.addingTimeInterval(fourHoursFiftyEightMinutes)
            )
        )
        let highPercentage = ClaudeUsageStatus(
            fiveHour: RateLimitWindow(
                usedPercentage: 99,
                resetsAt: capturedAt.addingTimeInterval(fourHoursFiftyEightMinutes)
            )
        )

        #expect(zeroPercent.hasLiveFiveHourTimer(capturedAt: capturedAt))
        #expect(highPercentage.hasLiveFiveHourTimer(capturedAt: capturedAt))
    }

    @Test("Accepts only positive countdowns within five hours plus tolerance")
    func boundsLiveFiveHourTimer() {
        let capturedAt = Date(timeIntervalSince1970: 1_000)
        let upperBound = TimeInterval(
            ClaudeUsageStatus.fiveHourDurationSeconds
                + ClaudeUsageStatus.fiveHourTimerToleranceSeconds
        )
        let atUpperBound = ClaudeUsageStatus(
            fiveHour: RateLimitWindow(
                usedPercentage: 0,
                resetsAt: capturedAt.addingTimeInterval(upperBound)
            )
        )
        let tooDistant = ClaudeUsageStatus(
            fiveHour: RateLimitWindow(
                usedPercentage: 0,
                resetsAt: capturedAt.addingTimeInterval(upperBound + 1)
            )
        )
        let expired = ClaudeUsageStatus(
            fiveHour: RateLimitWindow(usedPercentage: 0, resetsAt: capturedAt)
        )

        #expect(atUpperBound.hasLiveFiveHourTimer(capturedAt: capturedAt))
        #expect(!tooDistant.hasLiveFiveHourTimer(capturedAt: capturedAt))
        #expect(!expired.hasLiveFiveHourTimer(capturedAt: capturedAt))
    }

    @Test("Extracts latest parseable sentinel payload from PTY output")
    func parsesSentinelOutput() throws {
        let output = """
        noise
        C5H_RATE_LIMITS:{"rate_limits":{"five_hour":null}}
        prompt C5H_RATE_LIMITS:{"rate_limits":{"five_hour":{"used_percentage":"20","resets_at":"1778373600000"}}}
        """

        let status = try ClaudeUsageStatus.parseLatestSentinel(in: output)

        #expect(status.fiveHour.usedPercentage == 20)
        #expect(status.fiveHour.resetsAt.timeIntervalSince1970 == 1_778_373_600)
    }

    @Test("Normalizer stores Claude reset window and percentage")
    func normalizerUsesClaudeStatusPayload() {
        let normalized = UsageNormalizer.normalize(
            rawJSON: #"{"rate_limits":{"five_hour":{"used_percentage":20,"resets_at":1778373600}}}"#,
            providerID: .claude,
            capturedAt: Date(timeIntervalSince1970: 50)
        )

        #expect(normalized.windowStartedAt?.timeIntervalSince1970 == 1_778_355_600)
        #expect(normalized.windowEndsAt?.timeIntervalSince1970 == 1_778_373_600)
        #expect(normalized.usedPercentage == 20)
    }

    @Test("Parses seven day reset alongside five hour")
    func parsesSevenDayReset() throws {
        let status = try ClaudeUsageStatus.parsePayload("""
        {"rate_limits":{"five_hour":{"used_percentage":20,"resets_at":1778373600},"seven_day":{"used_percentage":57,"resets_at":1778893200}}}
        """)

        #expect(status.sevenDay?.usedPercentage == 57)
        #expect(status.sevenDay?.resetsAt.timeIntervalSince1970 == 1_778_893_200)
        #expect(status.sevenDayStartAt?.timeIntervalSince1970 == 1_778_288_400)
    }

    @Test("Builds seven day ActualWindow7d with usage")
    func buildsSevenDayActualWindow() throws {
        let status = try ClaudeUsageStatus.parsePayload("""
        {"rate_limits":{"five_hour":{"used_percentage":20,"resets_at":1778373600},"seven_day":{"used_percentage":57,"resets_at":1778893200}}}
        """)
        let snapshotID = UUID()
        let window = try #require(status.sevenDayActualWindow(
            usageSnapshotID: snapshotID,
            createdAt: Date(timeIntervalSince1970: 100)
        ))

        #expect(window.providerID == .claude)
        #expect(window.source == .detectedFromUsage)
        #expect(window.confidence == .estimated)
        #expect(window.durationSeconds == 7 * 24 * 3600)
        #expect(window.usedPercentage == 57)
        #expect(window.usageSnapshotID == snapshotID)
        #expect(window.startAt.timeIntervalSince1970 == 1_778_288_400)
        #expect(window.endAt.timeIntervalSince1970 == 1_778_893_200)
    }

    @Test("Seven day ActualWindow7d returns nil when seven_day absent")
    func sevenDayActualWindowReturnsNilWhenAbsent() throws {
        let status = try ClaudeUsageStatus.parsePayload("""
        {"rate_limits":{"five_hour":{"used_percentage":20,"resets_at":1778373600}}}
        """)

        #expect(status.sevenDay == nil)
        #expect(status.sevenDayStartAt == nil)
        #expect(status.sevenDayActualWindow() == nil)
    }
}
