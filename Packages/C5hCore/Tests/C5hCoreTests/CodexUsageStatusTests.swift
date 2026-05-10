import Foundation
import Testing
@testable import C5hCore

@Suite("CodexUsageStatus")
struct CodexUsageStatusTests {
    @Test("Parses current Codex rate-limit payload")
    func parsesCurrentPayload() throws {
        let status = try CodexUsageStatus.parsePayload("""
        {"timestamp":"2026-05-09T20:19:03.777Z","rate_limits":{"primary":{"used_percent":82,"window_minutes":300,"resets_at":1778364750}}}
        """)

        #expect(status.eventTimestamp.timeIntervalSince1970 == 1_778_357_943.777)
        #expect(status.primary.usedPercentage == 82)
        #expect(status.primary.resetsAt.timeIntervalSince1970 == 1_778_364_750)
        #expect(status.primaryWindowMinutes == 300)
    }

    @Test("Derives reset timestamp from older resets_in_seconds payload")
    func parsesOlderPayload() throws {
        let status = try CodexUsageStatus.parsePayload("""
        {"timestamp":"2026-05-09T20:00:00.000Z","rate_limits":{"primary":{"used_percent":"3","window_minutes":299,"resets_in_seconds":3600}}}
        """)

        #expect(status.primary.usedPercentage == 3)
        #expect(status.primary.resetsAt.timeIntervalSince1970 == 1_778_360_400)
        #expect(status.primaryWindowMinutes == 299)
    }

    @Test("Builds estimated ActualWindow from primary reset timestamp")
    func buildsActualWindow() throws {
        let status = try CodexUsageStatus.parsePayload("""
        {"timestamp":"2026-05-09T20:19:03.777Z","rate_limits":{"primary":{"used_percent":82,"window_minutes":300,"resets_at":1778364750}}}
        """)
        let window = status.actualWindow(createdAt: Date(timeIntervalSince1970: 100))

        #expect(window.providerID == .codex)
        #expect(window.source == .detectedFromUsage)
        #expect(window.confidence == .estimated)
        #expect(window.durationSeconds == 5 * 3600)
        #expect(window.startAt.timeIntervalSince1970 == 1_778_346_750)
        #expect(window.endAt.timeIntervalSince1970 == 1_778_364_750)
    }

    @Test("Normalizer stores Codex reset window and percentage")
    func normalizerUsesCodexPayload() {
        let normalized = UsageNormalizer.normalize(
            rawJSON: #"{"timestamp":"2026-05-09T20:19:03.777Z","rate_limits":{"primary":{"used_percent":82,"window_minutes":300,"resets_at":1778364750}}}"#,
            providerID: .codex,
            capturedAt: Date(timeIntervalSince1970: 50)
        )

        #expect(normalized.windowStartedAt?.timeIntervalSince1970 == 1_778_346_750)
        #expect(normalized.windowEndsAt?.timeIntervalSince1970 == 1_778_364_750)
        #expect(normalized.usedPercentage == 82)
    }
}
