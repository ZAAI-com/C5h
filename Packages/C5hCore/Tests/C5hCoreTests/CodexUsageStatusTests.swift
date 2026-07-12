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
        #expect(status.primary?.usedPercentage == 82)
        #expect(status.primary?.resetsAt.timeIntervalSince1970 == 1_778_364_750)
        #expect(status.primaryWindowMinutes == 300)
    }

    @Test("Derives reset timestamp from older resets_in_seconds payload")
    func parsesOlderPayload() throws {
        let status = try CodexUsageStatus.parsePayload("""
        {"timestamp":"2026-05-09T20:00:00.000Z","rate_limits":{"primary":{"used_percent":"3","window_minutes":299,"resets_in_seconds":3600}}}
        """)

        #expect(status.primary?.usedPercentage == 3)
        #expect(status.primary?.resetsAt.timeIntervalSince1970 == 1_778_360_400)
        #expect(status.primaryWindowMinutes == 299)
    }

    @Test("Builds estimated ActualWindow5h from primary reset timestamp")
    func buildsActualWindow() throws {
        let status = try CodexUsageStatus.parsePayload("""
        {"timestamp":"2026-05-09T20:19:03.777Z","rate_limits":{"primary":{"used_percent":82,"window_minutes":300,"resets_at":1778364750}}}
        """)
        let window = try #require(status.actualWindow(createdAt: Date(timeIntervalSince1970: 100)))

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

    @Test("Builds secondary ActualWindow7d honoring window_minutes")
    func buildsSecondaryActualWindow() throws {
        let status = try CodexUsageStatus.parsePayload("""
        {"timestamp":"2026-05-09T20:19:03.777Z","rate_limits":{"primary":{"used_percent":82,"window_minutes":300,"resets_at":1778364750},"secondary":{"used_percent":45,"window_minutes":10080,"resets_at":1778968800}}}
        """)
        let snapshotID = UUID()
        let window = try #require(status.secondaryActualWindow(
            usageSnapshotID: snapshotID,
            createdAt: Date(timeIntervalSince1970: 100)
        ))

        #expect(window.providerID == .codex)
        #expect(window.source == .detectedFromUsage)
        #expect(window.confidence == .estimated)
        #expect(window.durationSeconds == 10080 * 60)
        #expect(window.usedPercentage == 45)
        #expect(window.usageSnapshotID == snapshotID)
        #expect(window.endAt.timeIntervalSince1970 == 1_778_968_800)
        #expect(window.startAt.timeIntervalSince1970 == 1_778_968_800 - Double(10080 * 60))
    }

    @Test("Secondary ActualWindow7d defaults to seven days when window_minutes missing")
    func secondaryActualWindowDefaultsToSevenDays() throws {
        let status = try CodexUsageStatus.parsePayload("""
        {"timestamp":"2026-05-09T20:19:03.777Z","rate_limits":{"primary":{"used_percent":82,"window_minutes":300,"resets_at":1778364750},"secondary":{"used_percent":45,"resets_at":1778968800}}}
        """)
        let window = try #require(status.secondaryActualWindow())

        #expect(window.durationSeconds == 7 * 24 * 3600)
        #expect(window.endAt.timeIntervalSince1970 == 1_778_968_800)
    }

    @Test("isStale returns true for events older than 5h")
    func isStaleReturnsTrueWhenEventIsOld() throws {
        let status = try CodexUsageStatus.parsePayload("""
        {"timestamp":"2026-05-09T20:19:03.777Z","rate_limits":{"primary":{"used_percent":82,"window_minutes":300,"resets_at":1778364750}}}
        """)
        let sixHoursLater = status.eventTimestamp.addingTimeInterval(6 * 60 * 60)

        #expect(status.isStale(now: sixHoursLater) == true)
    }

    @Test("isStale returns false for recent events")
    func isStaleReturnsFalseWhenEventIsRecent() throws {
        let status = try CodexUsageStatus.parsePayload("""
        {"timestamp":"2026-05-09T20:19:03.777Z","rate_limits":{"primary":{"used_percent":82,"window_minutes":300,"resets_at":1778364750}}}
        """)
        let oneHourLater = status.eventTimestamp.addingTimeInterval(60 * 60)

        #expect(status.isStale(now: oneHourLater) == false)
    }

    @Test("Parses codex app-server account/rateLimits/read result payload")
    func parsesAppServerResponse() throws {
        let result = """
        {"rateLimits":{"limitId":"codex","limitName":null,"primary":{"usedPercent":2,"windowDurationMins":300,"resetsAt":1779365844},"secondary":{"usedPercent":12,"windowDurationMins":10080,"resetsAt":1779838110},"credits":{"hasCredits":false,"unlimited":false,"balance":"0"},"planType":"plus","rateLimitReachedType":null}}
        """
        let capturedAt = Date(timeIntervalSince1970: 1_779_300_000)
        let status = try CodexUsageStatus.parseAppServerResponse(result, capturedAt: capturedAt)

        #expect(status.eventTimestamp == capturedAt)
        #expect(status.primary?.usedPercentage == 2)
        #expect(status.primary?.resetsAt.timeIntervalSince1970 == 1_779_365_844)
        #expect(status.primaryWindowMinutes == 300)
        #expect(status.secondary?.usedPercentage == 12)
        #expect(status.secondary?.resetsAt.timeIntervalSince1970 == 1_779_838_110)
        #expect(status.secondaryWindowMinutes == 10080)
        #expect(status.planType == "plus")
    }

    @Test("App-server response uses CLI-provided duration (no 5h assumption)")
    func appServerResponseDurationIsCLIProvided() throws {
        let result = """
        {"rateLimits":{"primary":{"usedPercent":50,"windowDurationMins":240,"resetsAt":1779365844},"secondary":{"usedPercent":1,"windowDurationMins":10080,"resetsAt":1779838110}}}
        """
        let status = try CodexUsageStatus.parseAppServerResponse(result)

        #expect(status.primaryDurationSeconds == 240 * 60)
        #expect(status.secondaryDurationSeconds == 10080 * 60)
    }

    @Test("App-server response parses secondary-only payload")
    func appServerResponseSecondaryOnly() throws {
        let result = #"{"rateLimits":{"secondary":{"usedPercent":1,"windowDurationMins":10080,"resetsAt":1779838110}}}"#
        let status = try CodexUsageStatus.parseAppServerResponse(result)

        #expect(status.primary == nil)
        #expect(status.secondary?.usedPercentage == 1)
        #expect(status.secondaryWindowMinutes == 10080)
    }

    @Test("Legacy payload parses secondary-only shape")
    func legacyPayloadSecondaryOnly() throws {
        let status = try CodexUsageStatus.parsePayload("""
        {"timestamp":"2026-05-09T20:19:03.777Z","rate_limits":{"secondary":{"used_percent":45,"window_minutes":10080,"resets_at":1778968800}}}
        """)

        #expect(status.primary == nil)
        #expect(status.secondary?.usedPercentage == 45)
        #expect(status.hasActivePrimaryWindow == false)
        #expect(status.actualWindow() == nil)
        let weekly = try #require(status.secondaryActualWindow())
        #expect(weekly.usedPercentage == 45)
    }

    @Test("Rejects payloads with neither primary nor secondary limit")
    func rejectsPayloadWithNoLimits() {
        let result = #"{"rateLimits":{"planType":"plus"}}"#
        #expect(throws: CodexUsageStatusParseError.self) {
            _ = try CodexUsageStatus.parseAppServerResponse(result)
        }
    }

    @Test("App-server response raises on missing primary when secondary also missing")
    func appServerResponseMissingLimits() {
        let result = #"{"rateLimits":{"planType":"plus"}}"#
        #expect(throws: CodexUsageStatusParseError.self) {
            _ = try CodexUsageStatus.parseAppServerResponse(result)
        }
    }
}
