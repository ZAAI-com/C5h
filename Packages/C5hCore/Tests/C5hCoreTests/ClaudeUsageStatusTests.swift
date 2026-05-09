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

    @Test("Builds estimated ActualWindow from reset timestamp")
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

    @Test("Extracts latest parseable sentinel payload from PTY output")
    func parsesSentinelOutput() throws {
        let output = """
        noise
        C5H_RATE_LIMITS:{"rate_limits":{"five_hour":null}}
        prompt C5H_RATE_LIMITS:{"rate_limits":{"five_hour":{"used_percentage":"20","resets_at":"1778373600000"}}}
        """

        let status = try ClaudeUsageStatus.parseFirstSentinel(in: output)

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
}
