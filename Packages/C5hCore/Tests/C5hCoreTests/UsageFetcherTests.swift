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

    private func makeFetcher() -> UsageFetcher {
        UsageFetcher(
            persistSnapshot: { _ in },
            upsertActualWindow5h: { _, _ in },
            upsertActualWindow7d: { _, _ in }
        )
    }
}
