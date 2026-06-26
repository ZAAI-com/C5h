import Foundation
import Testing
@testable import C5hStore
@testable import C5hCore

@Suite("ActualWindow5hRepository.upsertByEndAt")
struct ActualWindow5hRepositoryUpsertTests {
    @Test("Matching endAt within tolerance updates existing row in place")
    func endAtMatchUpserts() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let repo = GRDBActualWindow5hRepository(database: db)

        let start = Date(timeIntervalSince1970: 1_730_000_000)
        let first = ActualWindow5h(
            providerID: .codex,
            startAt: start,
            durationSeconds: 5 * 3600,
            source: .detectedFromUsage,
            confidence: .estimated
        )
        try await repo.upsertByEndAt(first, tolerance: 60)

        let nearby = ActualWindow5h(
            providerID: .codex,
            startAt: start.addingTimeInterval(10),
            durationSeconds: 5 * 3600,
            source: .detectedFromUsage,
            confidence: .estimated
        )
        try await repo.upsertByEndAt(nearby, tolerance: 60)

        let all = try await repo.fetchAll().filter { $0.providerID == .codex }
        #expect(all.count == 1)
        #expect(all.first?.startAt == nearby.startAt)
    }

    @Test("Stale c5hTriggered placeholder is replaced when a detectedFromUsage row overlaps it (the Codex 13:00-18:00 vs 09:07-14:07 bug)")
    func overlappingFallbackReplacesStaleTriggered() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let repo = GRDBActualWindow5hRepository(database: db)

        // Stale placeholder written by legacy trigger code: window claims to
        // start at 13:00 and end at 18:00, but the upstream's true rolling
        // window is 09:07–14:07.
        let staleStart = Date(timeIntervalSince1970: 1_730_000_000)
        let stale = ActualWindow5h(
            providerID: .codex,
            startAt: staleStart,
            durationSeconds: 5 * 3600,
            source: .c5hTriggered,
            confidence: .exact,
            commandRunID: UUID()
        )
        try await repo.create(stale)

        // Real window from a usage refresh: starts ~4h earlier, same duration.
        let realStart = staleStart.addingTimeInterval(-4 * 3600 - 7 * 60)
        let real = ActualWindow5h(
            providerID: .codex,
            startAt: realStart,
            durationSeconds: 5 * 3600,
            source: .detectedFromUsage,
            confidence: .estimated
        )
        try await repo.upsertByEndAt(real, tolerance: 60)

        let all = try await repo.fetchAll().filter { $0.providerID == .codex }
        #expect(all.count == 1, "stale [13:00–18:00] should be collapsed onto the corrected [09:07–14:07] row")
        let row = try #require(all.first)
        #expect(row.startAt == realStart, "times should be updated to upstream truth")
        #expect(row.endAt == realStart.addingTimeInterval(5 * 3600))
        #expect(row.source == .c5hTriggered, "user-visible 'triggered' tag should be preserved through a routine usage refresh")
        #expect(row.confidence == .exact, "stronger 'exact' confidence should not be downgraded by a detectedFromUsage refresh")
        #expect(row.commandRunID == stale.commandRunID, "command-run link should be preserved")
    }

    @Test("Overlapping detectedFromUsage 5h windows with different reset times stay distinct")
    func overlappingDetectedWindowsWithDifferentResetsStayDistinct() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let repo = GRDBActualWindow5hRepository(database: db)

        // A Claude tier change can reset the 5h quota before the prior window has
        // elapsed, so the new reset-derived window overlaps the old one but ends
        // at a different time. Both are real, distinct windows and must coexist.
        let base = Date(timeIntervalSince1970: 1_730_000_000)
        let first = ActualWindow5h(
            providerID: .claude,
            startAt: base,
            durationSeconds: 5 * 3600,
            source: .detectedFromUsage,
            confidence: .estimated
        )
        try await repo.upsertByEndAt(first, tolerance: 60)

        // Reset window: starts ~1h later, overlaps the first, different end time.
        let resetWindow = ActualWindow5h(
            providerID: .claude,
            startAt: base.addingTimeInterval(3600),
            durationSeconds: 5 * 3600,
            source: .detectedFromUsage,
            confidence: .estimated
        )
        try await repo.upsertByEndAt(resetWindow, tolerance: 60)

        let all = try await repo.fetchAll().filter { $0.providerID == .claude }
        #expect(all.count == 2, "overlapping reset-derived windows with different reset times must stay distinct")
    }

    @Test("Non-overlapping windows for the same provider stay distinct")
    func nonOverlappingInserts() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let repo = GRDBActualWindow5hRepository(database: db)

        let base = Date(timeIntervalSince1970: 1_730_000_000)
        let earlier = ActualWindow5h(
            providerID: .claude,
            startAt: base,
            durationSeconds: 5 * 3600,
            source: .detectedFromUsage,
            confidence: .estimated
        )
        try await repo.upsertByEndAt(earlier, tolerance: 60)

        // 6 hours later, no overlap with the first window.
        let later = ActualWindow5h(
            providerID: .claude,
            startAt: base.addingTimeInterval(6 * 3600),
            durationSeconds: 5 * 3600,
            source: .detectedFromUsage,
            confidence: .estimated
        )
        try await repo.upsertByEndAt(later, tolerance: 60)

        let all = try await repo.fetchAll().filter { $0.providerID == .claude }
        #expect(all.count == 2)
    }
}

@Suite("ActualWindow5hRepository.delete")
struct ActualWindow5hRepositoryDeleteTests {
    @Test("Deletes the row by id and leaves others intact")
    func deletesByID() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let repo = GRDBActualWindow5hRepository(database: db)

        let base = Date(timeIntervalSince1970: 1_730_000_000)
        let keep = ActualWindow5h(
            providerID: .claude,
            startAt: base,
            source: .detectedFromUsage,
            confidence: .estimated
        )
        let drop = ActualWindow5h(
            providerID: .claude,
            startAt: base.addingTimeInterval(6 * 3600),
            source: .c5hTriggered,
            confidence: .estimated
        )
        try await repo.create(keep)
        try await repo.create(drop)

        try await repo.delete(drop.id)

        let remaining = try await repo.fetchAll().filter { $0.providerID == .claude }
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == keep.id)
    }

    @Test("Deleting a missing id is a no-op")
    func deleteMissingIsNoOp() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let repo = GRDBActualWindow5hRepository(database: db)

        let existing = ActualWindow5h(
            providerID: .claude,
            startAt: Date(timeIntervalSince1970: 1_730_000_000),
            source: .detectedFromUsage,
            confidence: .estimated
        )
        try await repo.create(existing)

        // A different, unknown id leaves the stored row intact.
        try await repo.delete(UUID())

        let remaining = try await repo.fetchAll().filter { $0.providerID == .claude }
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == existing.id)
    }
}
