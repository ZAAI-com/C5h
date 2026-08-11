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
