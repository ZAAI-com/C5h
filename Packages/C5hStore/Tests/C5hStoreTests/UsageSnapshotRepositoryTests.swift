import Foundation
import Testing
@testable import C5hCore
@testable import C5hStore

@Suite("UsageSnapshotRepository previousWindowEndLookup")
struct UsageSnapshotRepositoryPreviousWindowTests {
    private let currentWindowStart = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Returns the previous different window's end")
    func returnsPreviousDifferentWindowEnd() async throws {
        let repo = try await makeRepo()
        // A previous window that ended 10 minutes before the current one started.
        try await repo.create(makeSnapshot(
            capturedAt: currentWindowStart.addingTimeInterval(-1200),
            windowEndsAt: currentWindowStart.addingTimeInterval(-600)
        ))

        let end = try await repo.previousWindowEndLookup()(.claude, currentWindowStart)
        #expect(end?.timeIntervalSince1970 == currentWindowStart.addingTimeInterval(-600).timeIntervalSince1970)
    }

    @Test("Skips re-readings of the current window and returns the earlier different window")
    func skipsSameWindowReadings() async throws {
        let repo = try await makeRepo()
        // Previous, different window.
        try await repo.create(makeSnapshot(
            capturedAt: currentWindowStart.addingTimeInterval(-1200),
            windowEndsAt: currentWindowStart.addingTimeInterval(-600)
        ))
        // A re-reading of the current window that falls in the lookup's tail
        // (captured just after the window opened). It must be skipped so it does
        // not shadow the genuinely previous window.
        try await repo.create(makeSnapshot(
            capturedAt: currentWindowStart.addingTimeInterval(30),
            windowEndsAt: currentWindowStart.addingTimeInterval(5 * 3600)
        ))

        let end = try await repo.previousWindowEndLookup()(.claude, currentWindowStart)
        #expect(end?.timeIntervalSince1970 == currentWindowStart.addingTimeInterval(-600).timeIntervalSince1970)
    }

    @Test("Returns nil when only the current window has been recorded")
    func returnsNilWithoutPriorWindow() async throws {
        let repo = try await makeRepo()
        try await repo.create(makeSnapshot(
            capturedAt: currentWindowStart.addingTimeInterval(30),
            windowEndsAt: currentWindowStart.addingTimeInterval(5 * 3600)
        ))

        let end = try await repo.previousWindowEndLookup()(.claude, currentWindowStart)
        #expect(end == nil)
    }

    private func makeRepo() async throws -> GRDBUsageSnapshotRepository {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        return GRDBUsageSnapshotRepository(database: db)
    }

    private func makeSnapshot(capturedAt: Date, windowEndsAt: Date) -> UsageSnapshot {
        let normalized = NormalizedUsage(
            providerID: .claude,
            capturedAt: capturedAt,
            windowStartedAt: windowEndsAt.addingTimeInterval(-5 * 3600),
            windowEndsAt: windowEndsAt,
            usedPercentage: 0
        )
        return UsageSnapshot(
            providerID: .claude,
            capturedAt: capturedAt,
            rawJSON: "{}",
            normalizedJSON: UsageNormalizer.encode(normalized)
        )
    }
}

@Suite("UsageFetcher fresh 0% window integration")
struct UsageFetcherFreshWindowIntegrationTests {
    private let currentWindowStart = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("fetchAndPersist stores a fresh 0% Claude window through the wired path")
    func fetchAndPersistStoresFreshZeroUsageWindow() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let snapshotRepo = GRDBUsageSnapshotRepository(database: db)
        let actual5hRepo = GRDBActualWindow5hRepository(database: db)
        let actual7dRepo = GRDBActualWindow7dRepository(database: db)
        let fetcher = UsageFetcher(
            persistSnapshot: { try await snapshotRepo.create($0) },
            upsertActualWindow5h: { try await actual5hRepo.upsertByEndAt($0, tolerance: $1) },
            upsertActualWindow7d: { try await actual7dRepo.upsertByEndAt($0, tolerance: $1) },
            previousWindowEndLookup: snapshotRepo.previousWindowEndLookup()
        )

        // A previous, different window that ended 10 minutes before the current
        // one started (so the current window is a fresh anchor, not chained).
        try await snapshotRepo.create(makeClaudeSnapshot(
            capturedAt: currentWindowStart.addingTimeInterval(-1200),
            windowStartedAt: currentWindowStart.addingTimeInterval(-600 - 5 * 3600),
            usedPercentage: 0
        ))

        // Poll a live window used below Claude's reporting resolution (0%).
        let now = currentWindowStart.addingTimeInterval(60)
        let adapter = StubUsageAdapter(id: .claude, snapshot: makeClaudeSnapshot(
            capturedAt: now,
            windowStartedAt: currentWindowStart,
            usedPercentage: 0
        ))
        _ = try await fetcher.fetchAndPersist(adapter: adapter, now: now)

        let windows = try await actual5hRepo.fetchWindows(for: DateInterval(
            start: currentWindowStart.addingTimeInterval(-3600),
            end: currentWindowStart.addingTimeInterval(6 * 3600)
        ))
        let stored = windows.first { abs($0.startAt.timeIntervalSince(currentWindowStart)) < 1 }
        let window = try #require(stored)
        #expect(window.source == .detectedFromUsage)
        #expect(window.durationSeconds == 5 * 3600)
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
