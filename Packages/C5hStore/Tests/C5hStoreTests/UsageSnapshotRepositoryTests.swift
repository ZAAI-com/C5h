import Foundation
import Testing
@testable import C5hCore
@testable import C5hStore

@Suite("UsageFetcher Claude timer integration")
struct UsageFetcherClaudeTimerIntegrationTests {
    @Test("A 0% Claude timer is persisted and returned for its Berlin Today interval")
    func zeroUsageTimerAppearsInBerlinTodayInterval() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let snapshotRepo = GRDBUsageSnapshotRepository(database: db)
        let actual5hRepo = GRDBActualWindow5hRepository(database: db)
        let actual7dRepo = GRDBActualWindow7dRepository(database: db)
        let fetcher = UsageFetcher(
            persistSnapshot: { try await snapshotRepo.create($0) },
            upsertActualWindow5h: { try await actual5hRepo.upsertByEndAt($0, tolerance: $1) },
            upsertActualWindow7d: { try await actual7dRepo.upsertByEndAt($0, tolerance: $1) }
        )

        // Claude's live reported countdown is authoritative even when usage is
        // below the percentage reporting resolution. These are the exact bounds
        // from the reported incident: 09:40–14:40 local time in Berlin.
        let capturedAt = try parseISO8601("2026-07-18T08:09:01Z")
        let windowStart = try parseISO8601("2026-07-18T07:40:00Z")
        let windowEnd = try parseISO8601("2026-07-18T12:40:00Z")
        let adapter = StubUsageAdapter(id: .claude, snapshot: makeClaudeSnapshot(
            capturedAt: capturedAt,
            windowStartedAt: windowStart,
            usedPercentage: 0
        ))
        _ = try await fetcher.fetchAndPersist(adapter: adapter, now: capturedAt)

        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let today = try #require(berlin.dateInterval(of: .day, for: capturedAt))
        let windows = try await actual5hRepo.fetchWindows(for: today)
        let window = try #require(windows.first { $0.providerID == .claude })

        #expect(windows.filter { $0.providerID == .claude }.count == 1)
        #expect(window.startAt == windowStart)
        #expect(window.endAt == windowEnd)
        #expect(window.source == .detectedFromUsage)
        #expect(window.durationSeconds == 5 * 3600)

        let start = berlin.dateComponents([.hour, .minute], from: window.startAt)
        let end = berlin.dateComponents([.hour, .minute], from: window.endAt)
        #expect(start.hour == 9)
        #expect(start.minute == 40)
        #expect(end.hour == 14)
        #expect(end.minute == 40)
    }

    private func makeClaudeSnapshot(
        capturedAt: Date,
        windowStartedAt: Date,
        usedPercentage: Double
    ) -> UsageSnapshot {
        let resetsAt = windowStartedAt.addingTimeInterval(5 * 3600)
        let normalized = NormalizedUsage(
            providerID: .claude,
            capturedAt: capturedAt,
            windowStartedAt: windowStartedAt,
            windowEndsAt: resetsAt,
            usedPercentage: usedPercentage
        )
        return UsageSnapshot(
            providerID: .claude,
            capturedAt: capturedAt,
            rawJSON: """
            {"rate_limits":{"five_hour":{"used_percentage":\(usedPercentage),"resets_at":\(Int(resetsAt.timeIntervalSince1970))}}}
            """,
            normalizedJSON: UsageNormalizer.encode(normalized)
        )
    }

    private func parseISO8601(_ value: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: value))
    }
}

private struct StubUsageAdapter: ProviderAdapter {
    let id: ProviderID
    let snapshot: UsageSnapshot
    var displayName: String { id.displayName }

    func runVersion() async -> ProviderStatus { fatalError("unused") }
    func runAuthStatus() async -> ProviderStatus { fatalError("unused") }
    func runUsage() async throws -> UsageSnapshot { snapshot }
    func runPrompt(_ input: TriggerPromptInput, runID: UUID) async throws -> CommandRun {
        fatalError("unused")
    }
}
