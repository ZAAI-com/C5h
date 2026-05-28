import Foundation
import Testing
@testable import C5hStore
@testable import C5hCore

@Suite("ActualWindow7dRepository")
struct ActualWindow7dRepositoryTests {
    @Test("Creates and fetches latest weekly window")
    func createsAndFetchesLatest() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let repo = GRDBActualWindow7dRepository(database: db)

        let base = Date(timeIntervalSince1970: 1_730_000_000)
        let earlier = ActualWindow7d(
            providerID: .claude,
            startAt: base,
            usedPercentage: 12,
            source: .detectedFromUsage,
            confidence: .estimated
        )
        let later = ActualWindow7d(
            providerID: .claude,
            startAt: base.addingTimeInterval(86_400),
            usedPercentage: 34,
            source: .detectedFromUsage,
            confidence: .estimated
        )

        try await repo.create(earlier)
        try await repo.create(later)

        let latest = try #require(await repo.fetchLatest(providerID: .claude))
        #expect(latest.id == later.id)
        #expect(latest.usedPercentage == 34)
    }

    @Test("Matching endAt within tolerance updates weekly row in place")
    func endAtMatchUpserts() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let repo = GRDBActualWindow7dRepository(database: db)

        let snapshotID = UUID()
        let start = Date(timeIntervalSince1970: 1_730_000_000)
        let first = ActualWindow7d(
            providerID: .codex,
            startAt: start,
            usedPercentage: 45,
            source: .detectedFromUsage,
            confidence: .estimated
        )
        try await repo.upsertByEndAt(first, tolerance: 60)

        let nearby = ActualWindow7d(
            providerID: .codex,
            startAt: start.addingTimeInterval(10),
            usedPercentage: 51,
            source: .manual,
            confidence: .exact,
            usageSnapshotID: snapshotID
        )
        try await repo.upsertByEndAt(nearby, tolerance: 60)

        let all = try await repo.fetchAll().filter { $0.providerID == .codex }
        #expect(all.count == 1)
        let row = try #require(all.first)
        #expect(row.startAt == nearby.startAt)
        #expect(row.usedPercentage == 51)
        #expect(row.source == .manual)
        #expect(row.confidence == .exact)
        #expect(row.usageSnapshotID == snapshotID)
    }

    @Test("Overlapping weekly windows with different reset times stay distinct")
    func overlappingFallbackIsNotUsed() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let repo = GRDBActualWindow7dRepository(database: db)

        let base = Date(timeIntervalSince1970: 1_730_000_000)
        let first = ActualWindow7d(
            providerID: .claude,
            startAt: base,
            durationSeconds: 7 * 24 * 3600,
            usedPercentage: 20,
            source: .detectedFromUsage,
            confidence: .estimated
        )
        let overlappingDifferentReset = ActualWindow7d(
            providerID: .claude,
            startAt: base.addingTimeInterval(3600),
            durationSeconds: 7 * 24 * 3600,
            usedPercentage: 21,
            source: .detectedFromUsage,
            confidence: .estimated
        )

        try await repo.upsertByEndAt(first, tolerance: 60)
        try await repo.upsertByEndAt(overlappingDifferentReset, tolerance: 60)

        let all = try await repo.fetchAll().filter { $0.providerID == .claude }
        #expect(all.count == 2)
    }
}
