import Foundation
import GRDB
import C5hCore

enum Migrations {
    static func register(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1_initial_schema") { db in
            try db.create(table: "providers") { t in
                t.column("id", .text).primaryKey()
                t.column("display_name", .text).notNull()
                t.column("cli_path", .text)
                t.column("enabled", .integer).notNull()
                t.column("brand_color", .text).notNull()
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }

            try db.create(table: "planned_windows") { t in
                t.column("id", .text).primaryKey()
                t.column("provider_id", .text).notNull().references("providers")
                t.column("start_at", .text).notNull()
                t.column("duration_seconds", .integer).notNull()
                t.column("time_zone_id", .text).notNull()
                t.column("local_date", .text).notNull()
                t.column("prompt_template_id", .text)
                t.column("project_path", .text)
                t.column("status", .text).notNull()
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }
            try db.create(
                index: "idx_planned_windows_provider_start",
                on: "planned_windows",
                columns: ["provider_id", "start_at"]
            )

            try db.create(table: "actual_windows_5h") { t in
                t.column("id", .text).primaryKey()
                t.column("provider_id", .text).notNull().references("providers")
                t.column("start_at", .text).notNull()
                t.column("duration_seconds", .integer).notNull()
                t.column("time_zone_id", .text).notNull()
                t.column("local_date", .text).notNull()
                t.column("source", .text).notNull()
                t.column("confidence", .text).notNull()
                t.column("command_run_id", .text)
                t.column("usage_start_snapshot_id", .text)
                t.column("usage_end_snapshot_id", .text)
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }
            try db.create(
                index: "idx_actual_windows_5h_provider_start",
                on: "actual_windows_5h",
                columns: ["provider_id", "start_at"]
            )

            try db.create(table: "actual_windows_7d") { t in
                t.column("id", .text).primaryKey()
                t.column("provider_id", .text).notNull().references("providers")
                t.column("start_at", .text).notNull()
                t.column("duration_seconds", .integer).notNull()
                t.column("time_zone_id", .text).notNull()
                t.column("used_percentage", .double).notNull()
                t.column("source", .text).notNull()
                t.column("confidence", .text).notNull()
                t.column("usage_snapshot_id", .text)
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }
            try db.create(
                index: "idx_actual_windows_7d_provider_start",
                on: "actual_windows_7d",
                columns: ["provider_id", "start_at"]
            )

            try db.create(table: "scheduled_prompts") { t in
                t.column("id", .text).primaryKey()
                t.column("provider_id", .text).notNull().references("providers")
                t.column("planned_window_id", .text).references("planned_windows")
                t.column("prompt", .text).notNull()
                t.column("project_path", .text)
                t.column("run_at", .text).notNull()
                t.column("status", .text).notNull()
                t.column("attempts", .integer).notNull().defaults(to: 0)
                t.column("last_error", .text)
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }
            try db.create(
                index: "idx_scheduled_prompts_status_run_at",
                on: "scheduled_prompts",
                columns: ["status", "run_at"]
            )

            try db.create(table: "command_runs") { t in
                t.column("id", .text).primaryKey()
                t.column("provider_id", .text).notNull().references("providers")
                t.column("run_type", .text).notNull()
                t.column("command", .text).notNull()
                t.column("arguments_json", .text).notNull()
                t.column("cwd", .text)
                t.column("started_at", .text).notNull()
                t.column("ended_at", .text)
                t.column("exit_code", .integer)
                t.column("status", .text).notNull()
                t.column("stdout_path", .text)
                t.column("stderr_path", .text)
                t.column("parsed_events_json", .text)
                t.column("error", .text)
                t.column("tool_version", .text)
            }
            try db.create(
                index: "idx_command_runs_provider_started",
                on: "command_runs",
                columns: ["provider_id", "started_at"]
            )
            try db.create(
                index: "idx_command_runs_status_started",
                on: "command_runs",
                columns: ["status", "started_at"]
            )

            try db.create(table: "usage_snapshots") { t in
                t.column("id", .text).primaryKey()
                t.column("provider_id", .text).notNull().references("providers")
                t.column("captured_at", .text).notNull()
                t.column("raw_json", .text).notNull()
                t.column("normalized_json", .text).notNull()
            }
            try db.create(
                index: "idx_usage_snapshots_provider_captured",
                on: "usage_snapshots",
                columns: ["provider_id", "captured_at"]
            )

            try db.create(table: "prompt_templates") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("provider_id", .text).references("providers")
                t.column("body", .text).notNull()
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }

            try db.create(table: "app_settings") { t in
                t.column("key", .text).primaryKey()
                t.column("value_json", .text).notNull()
                t.column("updated_at", .text).notNull()
            }

            try db.create(table: "helper_heartbeats") { t in
                t.column("id", .text).primaryKey()
                t.column("helper_version", .text).notNull()
                t.column("started_at", .text).notNull()
                t.column("last_seen_at", .text).notNull()
                t.column("pid", .integer)
            }
        }

        migrator.registerMigration("v2_command_run_owner") { db in
            try db.alter(table: "command_runs") { t in
                t.add(column: "owner_pid", .integer)
            }
        }

        migrator.registerMigration("v3_reclassify_codex_weekly_windows") { db in
            try reclassifyLegacyCodexWeeklyWindows(db)
        }

        migrator.registerMigration("v4_drop_prospective_usage_windows") { db in
            try dropProspectiveFiveHourWindows(db)
            try dropProspectiveWeeklyWindows(db)
        }
    }

    /// Both providers report a *prospective* quota window while an account is
    /// idle: the window you would get by starting now, re-issued with a fresh
    /// reset end on every poll. Until `UsageFetcher` learned to drop those, each
    /// poll inserted a new row, burying the real windows under hundreds of
    /// one-poll duplicates. Delete the rows that historical snapshots prove were
    /// only ever prospective and, following `reclassifyLegacyCodexWeeklyWindows`,
    /// leave anything unprovable in place.
    private static func dropProspectiveFiveHourWindows(_ db: GRDB.Database) throws {
        // Claude is the only provider that reached this table with a sliding
        // slot; Codex's synthetic slot was already dropped by
        // `hasActiveFiveHourWindow`. Structural filters first: a row carrying a
        // command link or a snapshot link was corroborated by something other
        // than a bare poll and is never a candidate.
        let candidates = try ActualWindow5hRecord
            .filter(Column("provider_id") == ProviderID.claude.rawValue)
            .filter(Column("duration_seconds") == ClaudeUsageStatus.fiveHourDurationSeconds)
            .filter(Column("source") == ActualWindowSource.detectedFromUsage.rawValue)
            .filter(Column("confidence") == WindowConfidence.estimated.rawValue)
            .filter(Column("command_run_id") == nil)
            .filter(Column("usage_start_snapshot_id") == nil)
            .filter(Column("usage_end_snapshot_id") == nil)
            .order(Column("start_at"))
            .fetchAll(db)

        // Decide against the original data, then delete. Removing rows while
        // iterating would strip the last slot of a cascade of its only surviving
        // neighbour and leave it behind.
        var doomed: [String] = []
        for record in candidates {
            guard let window = try? record.toActualWindow() else { continue }
            // Cascade membership: a sliding slot always has a neighbour exactly
            // one slide step away. Requiring one preserves an isolated real
            // window that happened to be observed only at 0%.
            guard try hasSlideCascadeSibling(window, db) else { continue }
            guard try snapshotsProveProspectiveFiveHourSlot(window, db) else { continue }
            doomed.append(record.id)
        }
        for id in doomed {
            try ActualWindow5hRecord.deleteOne(db, key: id)
        }
    }

    /// True when another 5h row for the same provider starts exactly one slide
    /// step before or after `window` (within the dedup tolerance), i.e. `window`
    /// is one link in a chain of poll-generated slots.
    private static func hasSlideCascadeSibling(
        _ window: ActualWindow5h,
        _ db: GRDB.Database
    ) throws -> Bool {
        let step = TimeInterval(ClaudeUsageStatus.prospectiveSlotSlideSeconds)
        for offset in [-step, step] {
            let neighbour = window.startAt.addingTimeInterval(offset)
            let lower = DateTimeService.formatUTC(
                neighbour.addingTimeInterval(-UsageFetcher.dedupTolerance)
            )
            let upper = DateTimeService.formatUTC(
                neighbour.addingTimeInterval(UsageFetcher.dedupTolerance)
            )
            let sibling = try ActualWindow5hRecord
                .filter(Column("provider_id") == window.providerID.rawValue)
                .filter(Column("id") != window.id.uuidString)
                .filter(
                    Column("duration_seconds")
                        < CodexUsageStatus.weeklyClassThresholdSeconds
                )
                .filter(
                    sql: "datetime(start_at) BETWEEN datetime(?) AND datetime(?)",
                    arguments: [lower, upper]
                )
                .fetchOne(db)
            if sibling != nil { return true }
        }
        return false
    }

    /// True when every historical snapshot that reported this window's reset end
    /// describes a prospective slot, by the same predicate the live poll path
    /// uses, and none of them predates the window's start (a boundary reported
    /// before the window began is a chained window, not a slide). A window with
    /// no snapshot evidence at all is not provable and returns false.
    private static func snapshotsProveProspectiveFiveHourSlot(
        _ window: ActualWindow5h,
        _ db: GRDB.Database
    ) throws -> Bool {
        // A snapshot reporting this reset end was captured inside the window, or
        // at most one slide step before it opened. Bounding the scan this way
        // keeps the migration from re-parsing the whole snapshot history per row.
        let slack = TimeInterval(
            ClaudeUsageStatus.prospectiveSlotSlideSeconds
                + ClaudeUsageStatus.prospectiveSlotSkewSeconds
        )
        let lower = DateTimeService.formatUTC(window.startAt.addingTimeInterval(-slack))
        let upper = DateTimeService.formatUTC(window.endAt)
        let records = try UsageSnapshotRecord
            .filter(Column("provider_id") == window.providerID.rawValue)
            .filter(
                sql: """
                    julianday(captured_at) >= julianday(?) AND
                    julianday(captured_at) <= julianday(?)
                    """,
                arguments: [lower, upper]
            )
            .order(Column("captured_at"))
            .fetchAll(db)

        var sawConfirmingSnapshot = false
        for record in records {
            guard let snapshot = try? record.toUsageSnapshot(),
                  let status = try? ClaudeUsageStatus.parsePayload(snapshot.rawJSON),
                  abs(status.fiveHour.resetsAt.timeIntervalSince(window.endAt))
                      <= UsageFetcher.dedupTolerance else {
                continue
            }
            guard snapshot.capturedAt >= window.startAt,
                  status.isProspectiveFiveHourSlot(capturedAt: snapshot.capturedAt) else {
                return false
            }
            sawConfirmingSnapshot = true
        }
        return sawConfirmingSnapshot
    }

    /// Weekly rows all carry the snapshot they were derived from, so proof is a
    /// direct lookup: re-parse that snapshot and delete the row only when it
    /// still reads as a prospective slot under the live predicate. A missing or
    /// unparseable snapshot leaves the row in place.
    private static func dropProspectiveWeeklyWindows(_ db: GRDB.Database) throws {
        let candidates = try ActualWindow7dRecord
            .filter(Column("used_percentage") <= 0)
            .filter(Column("source") == ActualWindowSource.detectedFromUsage.rawValue)
            .filter(Column("confidence") == WindowConfidence.estimated.rawValue)
            .filter(Column("usage_snapshot_id") != nil)
            .order(Column("start_at"))
            .fetchAll(db)

        for record in candidates {
            guard let window = try? record.toActualWindow7d(),
                  let snapshotID = record.usageSnapshotId,
                  let snapshotRecord = try UsageSnapshotRecord.fetchOne(db, key: snapshotID),
                  let snapshot = try? snapshotRecord.toUsageSnapshot(),
                  snapshot.providerID == window.providerID,
                  isProspectiveWeeklySlot(snapshot) else {
                continue
            }
            try ActualWindow7dRecord.deleteOne(db, key: record.id)
        }
    }

    private static func isProspectiveWeeklySlot(_ snapshot: UsageSnapshot) -> Bool {
        switch snapshot.providerID {
        case .claude:
            guard let status = try? ClaudeUsageStatus.parsePayload(snapshot.rawJSON) else {
                return false
            }
            return status.isProspectiveSevenDaySlot(capturedAt: snapshot.capturedAt)
        case .codex:
            guard let status = try? CodexUsageStatus.parseAny(
                snapshot.rawJSON,
                capturedAt: snapshot.capturedAt
            ) else {
                return false
            }
            return status.isSyntheticFreshWeeklySlot
        }
    }

    /// Older Codex parsing treated the primary slot as a 5h limit even when its
    /// reported duration was weekly. Recover those rows only when a historical
    /// snapshot supplies unambiguous evidence for the same window. Anything we
    /// cannot prove remains in place and is hidden by the 5h repository filters.
    private static func reclassifyLegacyCodexWeeklyWindows(_ db: GRDB.Database) throws {
        let legacyRecords = try ActualWindow5hRecord
            .filter(Column("provider_id") == ProviderID.codex.rawValue)
            .filter(
                Column("duration_seconds")
                    >= CodexUsageStatus.weeklyClassThresholdSeconds
            )
            .order(Column("start_at"))
            .fetchAll(db)

        for legacyRecord in legacyRecords {
            guard let legacyWindow = try? legacyRecord.toActualWindow() else {
                continue
            }
            let start = DateTimeService.formatUTC(legacyWindow.startAt)
            let end = DateTimeService.formatUTC(legacyWindow.endAt)
            let snapshots = try UsageSnapshotRecord
                .filter(Column("provider_id") == ProviderID.codex.rawValue)
                // Usage windows are half-open. A snapshot at the reset instant
                // belongs to the next interval and cannot prove this legacy row.
                .filter(sql: """
                    julianday(captured_at) >= julianday(?) AND
                    julianday(captured_at) < julianday(?)
                    """, arguments: [start, end])
                .order(Column("captured_at").desc)
                .fetchAll(db)

            guard let evidence = snapshots.lazy.compactMap({ record -> ActualWindow7d? in
                guard let snapshot = try? record.toUsageSnapshot(),
                      let status = try? CodexUsageStatus.parseAny(
                          snapshot.rawJSON,
                          capturedAt: snapshot.capturedAt
                      ),
                      let weeklyWindow = status.secondaryActualWindow(
                          providerID: .codex,
                          usageSnapshotID: snapshot.id,
                          createdAt: snapshot.capturedAt
                      ),
                      abs(weeklyWindow.startAt.timeIntervalSince(legacyWindow.startAt))
                          <= UsageFetcher.dedupTolerance,
                      abs(weeklyWindow.endAt.timeIntervalSince(legacyWindow.endAt))
                          <= UsageFetcher.dedupTolerance else {
                    return nil
                }
                return weeklyWindow
            }).first else {
                continue
            }

            // Usage evidence supplies quota semantics; the legacy row retains
            // the user's historical timezone and creation provenance.
            let converted = ActualWindow7d(
                providerID: .codex,
                startAt: evidence.startAt,
                durationSeconds: evidence.durationSeconds,
                timeZoneIdentifier: legacyWindow.timeZoneIdentifier,
                usedPercentage: evidence.usedPercentage,
                source: evidence.source,
                confidence: evidence.confidence,
                usageSnapshotID: evidence.usageSnapshotID,
                createdAt: legacyWindow.createdAt,
                updatedAt: max(legacyWindow.updatedAt, evidence.updatedAt)
            )

            let lowerEnd = DateTimeService.formatUTC(
                converted.endAt.addingTimeInterval(-UsageFetcher.dedupTolerance)
            )
            let upperEnd = DateTimeService.formatUTC(
                converted.endAt.addingTimeInterval(UsageFetcher.dedupTolerance)
            )
            let existingWeekly = try ActualWindow7dRecord
                .filter(Column("provider_id") == ProviderID.codex.rawValue)
                .filter(sql: """
                    datetime(start_at, '+' || duration_seconds || ' seconds')
                        BETWEEN datetime(?) AND datetime(?)
                    """, arguments: [lowerEnd, upperEnd])
                .fetchOne(db)

            if existingWeekly == nil {
                try ActualWindow7dRecord(from: converted).insert(db)
            }
            try ActualWindow5hRecord.deleteOne(db, key: legacyRecord.id)
        }
    }
}
