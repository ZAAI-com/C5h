import Foundation
import Testing
import GRDB
@testable import C5hStore
@testable import C5hCore

@Suite("Migrations")
struct MigrationsTests {
    @Test("In-memory database creates all expected tables and indexes")
    func allTablesExist() async throws {
        let db = try Database.inMemory()
        let names: Set<String> = try await db.writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT name FROM sqlite_master
                WHERE type IN ('table','index')
                """)
            return Set(rows.compactMap { $0["name"] as String? })
        }

        let expectedTables: Set<String> = [
            "providers",
            "planned_windows",
            "actual_windows_5h",
            "actual_windows_7d",
            "scheduled_prompts",
            "command_runs",
            "usage_snapshots",
            "prompt_templates",
            "app_settings",
            "helper_heartbeats"
        ]
        #expect(expectedTables.isSubset(of: names))

        let expectedIndexes: Set<String> = [
            "idx_planned_windows_provider_start",
            "idx_actual_windows_5h_provider_start",
            "idx_actual_windows_7d_provider_start",
            "idx_scheduled_prompts_status_run_at",
            "idx_command_runs_provider_started",
            "idx_command_runs_status_started",
            "idx_usage_snapshots_provider_captured"
        ]
        #expect(expectedIndexes.isSubset(of: names))
    }

    @Test("v3 converts a legacy Codex weekly row from the latest strict snapshot match")
    func v3ConvertsLegacyWeeklyRowFromLatestEvidence() throws {
        let queue = try makePreV3Database()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let legacyCreatedAt = start.addingTimeInterval(-24 * 3600)
        let legacyUpdatedAt = start.addingTimeInterval(8000)
        let legacy = ActualWindow5h(
            providerID: .codex,
            startAt: start,
            durationSeconds: 7 * 24 * 3600,
            timeZoneIdentifier: "America/Los_Angeles",
            source: .detectedFromUsage,
            confidence: .estimated,
            createdAt: legacyCreatedAt,
            updatedAt: legacyUpdatedAt
        )
        let older = makeWeeklySnapshot(
            capturedAt: start.addingTimeInterval(3600),
            windowEnd: legacy.endAt,
            usedPercentage: 12
        )
        let latest = makeWeeklySnapshot(
            capturedAt: start.addingTimeInterval(7200),
            windowEnd: legacy.endAt,
            usedPercentage: 34
        )
        try queue.write { db in
            try ActualWindow5hRecord(from: legacy).insert(db)
            try UsageSnapshotRecord(from: older).insert(db)
            try UsageSnapshotRecord(from: latest).insert(db)
        }

        try Migrator.shared.migrate(queue)

        let result = try queue.read { db in
            (
                try ActualWindow5hRecord.fetchCount(db),
                try ActualWindow7dRecord.fetchAll(db)
            )
        }
        #expect(result.0 == 0)
        #expect(result.1.count == 1)
        let convertedRecord = try #require(result.1.first)
        let converted = try convertedRecord.toActualWindow7d()
        #expect(converted.startAt == legacy.startAt)
        #expect(converted.endAt == legacy.endAt)
        #expect(converted.usedPercentage == 34)
        #expect(converted.usageSnapshotID == latest.id)
        #expect(converted.timeZoneIdentifier == legacy.timeZoneIdentifier)
        #expect(converted.createdAt == legacyCreatedAt)
        #expect(converted.updatedAt == legacyUpdatedAt)
    }

    @Test("v3 preserves an existing weekly row and removes its proven legacy duplicate")
    func v3KeepsExistingWeeklyRow() throws {
        let queue = try makePreV3Database()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let legacy = ActualWindow5h(
            providerID: .codex,
            startAt: start,
            durationSeconds: 7 * 24 * 3600,
            source: .detectedFromUsage,
            confidence: .estimated
        )
        let snapshot = makeWeeklySnapshot(
            capturedAt: start.addingTimeInterval(3600),
            windowEnd: legacy.endAt,
            usedPercentage: 25
        )
        let existing = ActualWindow7d(
            providerID: .codex,
            startAt: start.addingTimeInterval(30),
            durationSeconds: 7 * 24 * 3600,
            usedPercentage: 77,
            source: .manual,
            confidence: .exact
        )
        try queue.write { db in
            try ActualWindow5hRecord(from: legacy).insert(db)
            try UsageSnapshotRecord(from: snapshot).insert(db)
            try ActualWindow7dRecord(from: existing).insert(db)
        }

        try Migrator.shared.migrate(queue)

        let result = try queue.read { db in
            (
                try ActualWindow5hRecord.fetchCount(db),
                try ActualWindow7dRecord.fetchAll(db)
            )
        }
        #expect(result.0 == 0)
        #expect(result.1.count == 1)
        let retainedRecord = try #require(result.1.first)
        let retained = try retainedRecord.toActualWindow7d()
        #expect(retained.id == existing.id)
        #expect(retained.usedPercentage == 77)
        #expect(retained.source == .manual)
    }

    @Test("v3 retains a legacy row when no snapshot proves the same interval")
    func v3RetainsUnmatchedLegacyWeeklyRow() throws {
        let queue = try makePreV3Database()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let legacy = ActualWindow5h(
            providerID: .codex,
            startAt: start,
            durationSeconds: 7 * 24 * 3600,
            source: .detectedFromUsage,
            confidence: .estimated
        )
        // Exact window evidence captured at the half-open end is outside the
        // legacy interval. The in-range snapshot derives a window 61s away.
        let outside = makeWeeklySnapshot(
            capturedAt: legacy.endAt,
            windowEnd: legacy.endAt,
            usedPercentage: 10
        )
        let mismatched = makeWeeklySnapshot(
            capturedAt: start.addingTimeInterval(3600),
            windowEnd: legacy.endAt.addingTimeInterval(61),
            usedPercentage: 20
        )
        try queue.write { db in
            try ActualWindow5hRecord(from: legacy).insert(db)
            try UsageSnapshotRecord(from: outside).insert(db)
            try UsageSnapshotRecord(from: mismatched).insert(db)
        }

        try Migrator.shared.migrate(queue)

        let counts = try queue.read { db in
            (
                try ActualWindow5hRecord.fetchCount(db),
                try ActualWindow7dRecord.fetchCount(db)
            )
        }
        #expect(counts.0 == 1)
        #expect(counts.1 == 0)
    }

    @Test("v3 leaves valid Codex 5h and non-Codex weekly-duration rows untouched")
    func v3ScopesLegacyCandidatesToWeeklyCodexRows() throws {
        let queue = try makePreV3Database()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let validCodex = ActualWindow5h(
            providerID: .codex,
            startAt: start,
            source: .detectedFromUsage,
            confidence: .estimated
        )
        let nonCodexWeekly = ActualWindow5h(
            providerID: .claude,
            startAt: start,
            durationSeconds: 7 * 24 * 3600,
            source: .manual,
            confidence: .exact
        )
        try queue.write { db in
            try ActualWindow5hRecord(from: validCodex).insert(db)
            try ActualWindow5hRecord(from: nonCodexWeekly).insert(db)
        }

        try Migrator.shared.migrate(queue)

        let result = try queue.read { db in
            (
                try ActualWindow5hRecord.fetchAll(db).map(\.id),
                try ActualWindow7dRecord.fetchCount(db)
            )
        }
        #expect(Set(result.0) == Set([validCodex.id.uuidString, nonCodexWeekly.id.uuidString]))
        #expect(result.1 == 0)
    }

    @Test("Seed inserts providers and templates")
    func seedInserts() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)

        let providers = try await GRDBProviderRepository(database: db).fetchAll()
        #expect(providers.count == 2)
        #expect(providers.contains(where: { $0.id == .claude }))
        #expect(providers.contains(where: { $0.id == .codex }))

        let templates = try await GRDBPromptTemplateRepository(database: db).fetchAll()
        #expect(templates.count == 3)
    }

    @Test("Seed is idempotent")
    func seedIdempotent() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        try await Seed.runIfNeeded(database: db)
        let providers = try await GRDBProviderRepository(database: db).fetchAll()
        #expect(providers.count == 2)
    }

    // MARK: - v4: prospective quota windows

    @Test("v4 deletes a Claude sliding-slot cascade proved by its snapshots")
    func v4DeletesProvenClaudeSlideCascade() throws {
        let queue = try makePreV3Database()
        let firstSlotStart = Date(timeIntervalSince1970: 1_800_000_000)

        try queue.write { db in
            // Six polls, each reporting the next 10-minute grid step at 0%: the
            // shape that inserted one row per poll.
            for step in 0..<6 {
                let slotStart = firstSlotStart.addingTimeInterval(TimeInterval(step * 600))
                let capturedAt = slotStart.addingTimeInterval(108)
                try ActualWindow5hRecord(from: makeClaudeSlot(start: slotStart)).insert(db)
                try UsageSnapshotRecord(from: makeClaudeFiveHourSnapshot(
                    capturedAt: capturedAt,
                    windowStart: slotStart,
                    usedPercentage: 0
                )).insert(db)
            }
        }

        try Migrator.shared.migrate(queue)

        let remaining = try queue.read { try ActualWindow5hRecord.fetchCount($0) }
        #expect(remaining == 0)
    }

    @Test("v4 keeps a Claude window a snapshot proves carried usage")
    func v4KeepsClaudeWindowWithRecordedUsage() throws {
        let queue = try makePreV3Database()
        let firstSlotStart = Date(timeIntervalSince1970: 1_800_000_000)
        let anchoredStart = firstSlotStart.addingTimeInterval(600)

        try queue.write { db in
            for step in 0..<2 {
                let slotStart = firstSlotStart.addingTimeInterval(TimeInterval(step * 600))
                try ActualWindow5hRecord(from: makeClaudeSlot(start: slotStart)).insert(db)
            }
            // The first slot stays prospective; the second one accumulated usage
            // and is a real window.
            try UsageSnapshotRecord(from: makeClaudeFiveHourSnapshot(
                capturedAt: firstSlotStart.addingTimeInterval(108),
                windowStart: firstSlotStart,
                usedPercentage: 0
            )).insert(db)
            try UsageSnapshotRecord(from: makeClaudeFiveHourSnapshot(
                capturedAt: anchoredStart.addingTimeInterval(1_800),
                windowStart: anchoredStart,
                usedPercentage: 12
            )).insert(db)
        }

        try Migrator.shared.migrate(queue)

        let survivors = try queue.read { try ActualWindow5hRecord.fetchAll($0) }
        #expect(survivors.count == 1)
        #expect(survivors.first?.startAt == DateTimeService.formatUTC(anchoredStart))
    }

    @Test("v4 keeps an isolated 0% Claude window with no cascade sibling")
    func v4KeepsIsolatedZeroUsageClaudeWindow() throws {
        let queue = try makePreV3Database()
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        try queue.write { db in
            try ActualWindow5hRecord(from: makeClaudeSlot(start: start)).insert(db)
            try UsageSnapshotRecord(from: makeClaudeFiveHourSnapshot(
                capturedAt: start.addingTimeInterval(108),
                windowStart: start,
                usedPercentage: 0
            )).insert(db)
        }

        try Migrator.shared.migrate(queue)

        #expect(try queue.read { try ActualWindow5hRecord.fetchCount($0) } == 1)
    }

    @Test("v4 keeps a Claude window with no snapshot evidence at all")
    func v4KeepsUnprovenClaudeWindow() throws {
        let queue = try makePreV3Database()
        let firstSlotStart = Date(timeIntervalSince1970: 1_800_000_000)

        try queue.write { db in
            // A full cascade shape, but retention swept the snapshots, so nothing
            // proves what these rows were.
            for step in 0..<3 {
                let slotStart = firstSlotStart.addingTimeInterval(TimeInterval(step * 600))
                try ActualWindow5hRecord(from: makeClaudeSlot(start: slotStart)).insert(db)
            }
        }

        try Migrator.shared.migrate(queue)

        #expect(try queue.read { try ActualWindow5hRecord.fetchCount($0) } == 3)
    }

    @Test("v4 keeps a triggered Claude window inside a cascade")
    func v4KeepsTriggeredClaudeWindow() throws {
        let queue = try makePreV3Database()
        let firstSlotStart = Date(timeIntervalSince1970: 1_800_000_000)
        let triggeredStart = firstSlotStart.addingTimeInterval(600)

        try queue.write { db in
            for step in 0..<3 {
                let slotStart = firstSlotStart.addingTimeInterval(TimeInterval(step * 600))
                var window = makeClaudeSlot(start: slotStart)
                if slotStart == triggeredStart {
                    window.source = .c5hTriggered
                    window.confidence = .exact
                }
                try ActualWindow5hRecord(from: window).insert(db)
                try UsageSnapshotRecord(from: makeClaudeFiveHourSnapshot(
                    capturedAt: slotStart.addingTimeInterval(108),
                    windowStart: slotStart,
                    usedPercentage: 0
                )).insert(db)
            }
        }

        try Migrator.shared.migrate(queue)

        let survivors = try queue.read { try ActualWindow5hRecord.fetchAll($0) }
        #expect(survivors.count == 1)
        #expect(survivors.first?.source == ActualWindowSource.c5hTriggered.rawValue)
    }

    @Test("v4 deletes synthetic weekly rows and keeps the anchored one")
    func v4DeletesSyntheticWeeklyRows() throws {
        let queue = try makePreV3Database()
        let firstCapture = Date(timeIntervalSince1970: 1_800_000_000)
        let weekSeconds = TimeInterval(CodexUsageStatus.defaultSecondaryDurationSeconds)
        let anchoredEnd = firstCapture.addingTimeInterval(weekSeconds + 3_600)

        try queue.write { db in
            // Three idle polls, each reporting `captured + 7d` at 0%.
            for step in 0..<3 {
                let capturedAt = firstCapture.addingTimeInterval(TimeInterval(step * 330))
                let snapshot = makeWeeklySnapshot(
                    capturedAt: capturedAt,
                    windowEnd: capturedAt.addingTimeInterval(weekSeconds),
                    usedPercentage: 0
                )
                try UsageSnapshotRecord(from: snapshot).insert(db)
                try ActualWindow7dRecord(from: makeWeeklyWindow(
                    end: capturedAt.addingTimeInterval(weekSeconds),
                    usedPercentage: 0,
                    snapshotID: snapshot.id,
                    createdAt: capturedAt
                )).insert(db)
            }
            // Then usage anchors the window: the reset stops tracking the clock.
            let anchoredCapture = firstCapture.addingTimeInterval(1_200)
            let anchoredSnapshot = makeWeeklySnapshot(
                capturedAt: anchoredCapture,
                windowEnd: anchoredEnd,
                usedPercentage: 0
            )
            try UsageSnapshotRecord(from: anchoredSnapshot).insert(db)
            try ActualWindow7dRecord(from: makeWeeklyWindow(
                end: anchoredEnd,
                usedPercentage: 0,
                snapshotID: anchoredSnapshot.id,
                createdAt: anchoredCapture
            )).insert(db)
        }

        try Migrator.shared.migrate(queue)

        let survivors = try queue.read { try ActualWindow7dRecord.fetchAll($0) }
        #expect(survivors.count == 1)
        #expect(survivors.first?.startAt == DateTimeService.formatUTC(
            anchoredEnd.addingTimeInterval(-weekSeconds)
        ))
    }

    @Test("v4 keeps a weekly row that reports usage despite synthetic timing")
    func v4KeepsWeeklyRowWithUsage() throws {
        let queue = try makePreV3Database()
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let weekSeconds = TimeInterval(CodexUsageStatus.defaultSecondaryDurationSeconds)
        let end = capturedAt.addingTimeInterval(weekSeconds)

        try queue.write { db in
            let snapshot = makeWeeklySnapshot(
                capturedAt: capturedAt,
                windowEnd: end,
                usedPercentage: 97
            )
            try UsageSnapshotRecord(from: snapshot).insert(db)
            try ActualWindow7dRecord(from: makeWeeklyWindow(
                end: end,
                usedPercentage: 97,
                snapshotID: snapshot.id,
                createdAt: capturedAt
            )).insert(db)
        }

        try Migrator.shared.migrate(queue)

        #expect(try queue.read { try ActualWindow7dRecord.fetchCount($0) } == 1)
    }

    private func makeClaudeSlot(start: Date) -> ActualWindow5h {
        ActualWindow5h(
            providerID: .claude,
            startAt: start,
            durationSeconds: ClaudeUsageStatus.fiveHourDurationSeconds,
            source: .detectedFromUsage,
            confidence: .estimated,
            createdAt: start,
            updatedAt: start
        )
    }

    private func makeWeeklyWindow(
        end: Date,
        usedPercentage: Double,
        snapshotID: UUID,
        createdAt: Date
    ) -> ActualWindow7d {
        let duration = CodexUsageStatus.defaultSecondaryDurationSeconds
        return ActualWindow7d(
            providerID: .codex,
            startAt: end.addingTimeInterval(-TimeInterval(duration)),
            durationSeconds: duration,
            usedPercentage: usedPercentage,
            source: .detectedFromUsage,
            confidence: .estimated,
            usageSnapshotID: snapshotID,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    private func makeClaudeFiveHourSnapshot(
        capturedAt: Date,
        windowStart: Date,
        usedPercentage: Double
    ) -> UsageSnapshot {
        let resetsAt = windowStart
            .addingTimeInterval(TimeInterval(ClaudeUsageStatus.fiveHourDurationSeconds))
        return UsageSnapshot(
            providerID: .claude,
            capturedAt: capturedAt,
            rawJSON: """
            {"rate_limits":{"five_hour":{"used_percentage":\(usedPercentage),"resets_at":\(Int(resetsAt.timeIntervalSince1970))}}}
            """,
            normalizedJSON: "{}"
        )
    }

    private func makePreV3Database() throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let queue = try DatabaseQueue(configuration: configuration)
        try Migrator.shared.migrate(queue, upTo: "v2_command_run_owner")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try queue.write { db in
            try ProviderRecord(from: Provider(
                id: .claude,
                displayName: ProviderID.claude.displayName,
                isEnabled: true,
                brandColorHex: "#D96E40",
                createdAt: now,
                updatedAt: now
            )).insert(db)
            try ProviderRecord(from: Provider(
                id: .codex,
                displayName: ProviderID.codex.displayName,
                isEnabled: true,
                brandColorHex: "#2664EB",
                createdAt: now,
                updatedAt: now
            )).insert(db)
        }
        return queue
    }

    private func makeWeeklySnapshot(
        capturedAt: Date,
        windowEnd: Date,
        usedPercentage: Double
    ) -> UsageSnapshot {
        let status = CodexUsageStatus(
            eventTimestamp: capturedAt,
            primary: RateLimitWindow(
                usedPercentage: usedPercentage,
                resetsAt: windowEnd
            ),
            primaryWindowMinutes: 7 * 24 * 60
        )
        return UsageSnapshot(
            providerID: .codex,
            capturedAt: capturedAt,
            rawJSON: status.encodedPayload(),
            normalizedJSON: "{}"
        )
    }
}
