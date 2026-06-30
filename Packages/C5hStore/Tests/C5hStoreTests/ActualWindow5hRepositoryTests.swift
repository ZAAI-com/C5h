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

    @Test("A reused c5hTriggered/estimated window settles to exact once a real usage poll confirms its start")
    func reusedTriggeredEstimatedSettlesToExact() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let repo = GRDBActualWindow5hRepository(database: db)

        // A Codex trigger whose fresh poll could not confirm the start (synthetic
        // "fresh slot"): the resolver reused an existing window, tagged it
        // c5hTriggered, and linked the command run, but left it `estimated`.
        let reusedStart = Date(timeIntervalSince1970: 1_730_000_000)
        let triggered = ActualWindow5h(
            providerID: .codex,
            startAt: reusedStart,
            durationSeconds: 5 * 3600,
            source: .c5hTriggered,
            confidence: .estimated,
            commandRunID: UUID()
        )
        try await repo.create(triggered)

        // The next background poll sees the real anchored window (~13 min later),
        // overlapping the reused row but ending at a different time.
        let realStart = reusedStart.addingTimeInterval(13 * 60)
        let real = ActualWindow5h(
            providerID: .codex,
            startAt: realStart,
            durationSeconds: 5 * 3600,
            source: .detectedFromUsage,
            confidence: .estimated
        )
        try await repo.upsertByEndAt(real, tolerance: 60)

        let all = try await repo.fetchAll().filter { $0.providerID == .codex }
        #expect(all.count == 1, "the confirming poll should merge onto the triggered row, not add a second row")
        let row = try #require(all.first)
        #expect(row.startAt == realStart, "times should be corrected to upstream truth")
        #expect(row.endAt == realStart.addingTimeInterval(5 * 3600))
        #expect(row.source == .c5hTriggered, "triggered tag should be preserved")
        #expect(row.confidence == .exact, "a real anchored poll confirms the start, so confidence should settle to exact")
        #expect(row.commandRunID == triggered.commandRunID, "command-run link should be preserved")
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
