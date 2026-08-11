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

    @Test("A valid upsert does not reuse a legacy weekly-class row with the same end")
    func validUpsertIgnoresLegacyWeeklyEndMatch() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let repo = GRDBActualWindow5hRepository(database: db)
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        let legacy = ActualWindow5h(
            providerID: .codex,
            startAt: end.addingTimeInterval(-7 * 24 * 3600),
            durationSeconds: 7 * 24 * 3600,
            source: .detectedFromUsage,
            confidence: .estimated
        )
        try await repo.create(legacy)

        let valid = ActualWindow5h(
            providerID: .codex,
            startAt: end.addingTimeInterval(-5 * 3600),
            source: .detectedFromUsage,
            confidence: .estimated
        )
        try await repo.upsertByEndAt(valid, tolerance: 60)

        let visible = try await repo.fetchAll()
        #expect(visible.map(\.id) == [valid.id])
        let physicalCount = try await db.writer.read { db in
            try ActualWindow5hRecord.fetchCount(db)
        }
        #expect(physicalCount == 2)
    }

    @Test("Weekly-class input is ignored by the 5h upsert boundary")
    func weeklyClassUpsertIsIgnored() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let repo = GRDBActualWindow5hRepository(database: db)

        try await repo.upsertByEndAt(ActualWindow5h(
            providerID: .codex,
            startAt: Date(timeIntervalSince1970: 1_800_000_000),
            durationSeconds: CodexUsageStatus.weeklyClassThresholdSeconds,
            source: .detectedFromUsage,
            confidence: .estimated
        ), tolerance: 60)

        let physicalCount = try await db.writer.read { db in
            try ActualWindow5hRecord.fetchCount(db)
        }
        #expect(physicalCount == 0)
    }
}

@Suite("ActualWindow5hRepository legacy duration filtering")
struct ActualWindow5hRepositoryLegacyDurationTests {
    @Test("Every read path hides retained weekly-class rows")
    func readPathsHideLegacyWeeklyRows() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let repo = GRDBActualWindow5hRepository(database: db)
        let reference = Date(timeIntervalSince1970: 1_800_000_000)
        let legacy = ActualWindow5h(
            providerID: .codex,
            startAt: reference.addingTimeInterval(-24 * 3600),
            durationSeconds: 7 * 24 * 3600,
            source: .detectedFromUsage,
            confidence: .estimated
        )
        let valid = ActualWindow5h(
            providerID: .codex,
            startAt: reference.addingTimeInterval(-60),
            source: .detectedFromUsage,
            confidence: .estimated
        )
        try await repo.create(legacy)
        try await repo.create(valid)

        #expect(try await repo.fetchAll().map(\.id) == [valid.id])
        #expect(try await repo.fetchWindows(
            for: DateInterval(start: reference, duration: 1)
        ).map(\.id) == [valid.id])
        #expect(try await repo.fetchActiveWindow(
            providerID: .codex,
            at: reference
        )?.id == valid.id)

        let physicalCount = try await db.writer.read { db in
            try ActualWindow5hRecord.fetchCount(db)
        }
        #expect(physicalCount == 2, "unmatched legacy data is retained for recovery")
    }
}

@Suite("ActualWindow5hRepository active-window wait")
struct ActualWindow5hRepositoryActiveWindowWaitTests {
    @Test("Point lookup returns only the latest same-provider window covering the reference time")
    func pointLookupFiltersProviderAndCoverage() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let repo = GRDBActualWindow5hRepository(database: db)

        let reference = Date(timeIntervalSince1970: 1_730_100_000)
        let expired = ActualWindow5h(
            providerID: .claude,
            startAt: reference.addingTimeInterval(-300),
            durationSeconds: 300,
            source: .detectedFromUsage,
            confidence: .estimated
        )
        let otherProvider = ActualWindow5h(
            providerID: .codex,
            startAt: reference.addingTimeInterval(-10),
            durationSeconds: 600,
            source: .detectedFromUsage,
            confidence: .estimated
        )
        let olderMatch = ActualWindow5h(
            providerID: .claude,
            startAt: reference.addingTimeInterval(-200),
            durationSeconds: 600,
            source: .detectedFromUsage,
            confidence: .estimated
        )
        let latestMatch = ActualWindow5h(
            providerID: .claude,
            startAt: reference.addingTimeInterval(-100),
            durationSeconds: 600,
            source: .detectedFromUsage,
            confidence: .estimated
        )
        // This sorts after every real match and starts in the same wall-clock
        // second as `reference`. The SQL lookup must preserve fractional-second
        // precision rather than truncating both values to an equal second.
        let sameSecondFuture = ActualWindow5h(
            providerID: .claude,
            startAt: reference.addingTimeInterval(0.5),
            durationSeconds: 600,
            source: .detectedFromUsage,
            confidence: .estimated
        )
        for window in [expired, otherProvider, olderMatch, latestMatch, sameSecondFuture] {
            try await repo.create(window)
        }

        let active = try #require(try await repo.fetchActiveWindow(
            providerID: .claude,
            at: reference
        ))

        #expect(active.id == latestMatch.id)
        #expect(active.providerID == .claude)
        #expect(active.startAt <= reference)
        #expect(reference < active.endAt)
    }

    @Test("Waiter immediately returns an already-persisted active window")
    func waiterReturnsImmediateMatch() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let repo = GRDBActualWindow5hRepository(database: db)

        let reference = Date(timeIntervalSince1970: 1_730_200_000)
        let window = ActualWindow5h(
            providerID: .claude,
            startAt: reference.addingTimeInterval(-60),
            durationSeconds: 5 * 3600,
            source: .detectedFromUsage,
            confidence: .estimated
        )
        try await repo.create(window)

        let active = try await repo.awaitActiveWindow(
            providerID: .claude,
            at: reference,
            timeout: .zero,
            pollInterval: .milliseconds(1)
        )

        #expect(active?.id == window.id)
    }

    @Test("Waiter sees a delayed insert made through another database handle")
    func waiterSeesCrossConnectionInsert() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("c5h-active-window-wait-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("test.sqlite")
        let readerDatabase = try Database.open(
            at: databaseURL,
            notificationName: "com.zaai.c5h.active-window-wait.reader.\(UUID().uuidString)"
        )
        let writerDatabase = try Database.open(
            at: databaseURL,
            notificationName: "com.zaai.c5h.active-window-wait.writer.\(UUID().uuidString)"
        )
        try await Seed.runIfNeeded(database: readerDatabase)

        let reader = GRDBActualWindow5hRepository(database: readerDatabase)
        let writer = GRDBActualWindow5hRepository(database: writerDatabase)
        let reference = Date(timeIntervalSince1970: 1_730_300_000)
        let window = ActualWindow5h(
            providerID: .claude,
            startAt: reference.addingTimeInterval(-60),
            durationSeconds: 5 * 3600,
            source: .detectedFromUsage,
            confidence: .estimated
        )

        let delayedInsert = Task {
            try await Task.sleep(for: .milliseconds(50))
            try await writer.create(window)
        }
        defer { delayedInsert.cancel() }

        let active = try await reader.awaitActiveWindow(
            providerID: .claude,
            at: reference,
            timeout: .seconds(1),
            pollInterval: .milliseconds(10)
        )
        try await delayedInsert.value

        #expect(active?.id == window.id)
    }

    @Test("Waiter times out when rows have the wrong provider or do not cover the reference time")
    func waiterTimesOutForNonMatchingRows() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let repo = GRDBActualWindow5hRepository(database: db)

        let reference = Date(timeIntervalSince1970: 1_730_400_000)
        try await repo.create(ActualWindow5h(
            providerID: .codex,
            startAt: reference.addingTimeInterval(-60),
            durationSeconds: 5 * 3600,
            source: .detectedFromUsage,
            confidence: .estimated
        ))
        try await repo.create(ActualWindow5h(
            providerID: .claude,
            startAt: reference.addingTimeInterval(-5 * 3600),
            durationSeconds: 5 * 3600,
            source: .detectedFromUsage,
            confidence: .estimated
        ))

        let active = try await repo.awaitActiveWindow(
            providerID: .claude,
            at: reference,
            timeout: .milliseconds(25),
            pollInterval: .milliseconds(5)
        )

        #expect(active == nil)
    }

    @Test("Waiter propagates task cancellation")
    func waiterPropagatesCancellation() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let repo = GRDBActualWindow5hRepository(database: db)
        let reference = Date(timeIntervalSince1970: 1_730_500_000)

        let waitTask = Task {
            try await repo.awaitActiveWindow(
                providerID: .claude,
                at: reference,
                timeout: .seconds(35),
                pollInterval: .seconds(5)
            )
        }
        waitTask.cancel()

        do {
            _ = try await waitTask.value
            Issue.record("A cancelled wait should throw CancellationError")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }
    }
}
