import Foundation
import GRDB
import C5hCore

public protocol ActualWindowRepository: Sendable {
    func fetchAll() async throws -> [ActualWindow]
    func fetchWindows(for interval: DateInterval) async throws -> [ActualWindow]
    func create(_ window: ActualWindow) async throws
    func update(_ window: ActualWindow) async throws

    /// Inserts the window, or updates an existing window for the same provider
    /// whose `endAt` is within `tolerance` of the new window's `endAt`. Used to
    /// collapse repeated polling snapshots of the same 5h limit window into a
    /// single row, so "last N windows" lists distinct actual windows instead of
    /// poll-time noise.
    func upsertByEndAt(_ window: ActualWindow, tolerance: TimeInterval) async throws
}

public struct GRDBActualWindowRepository: ActualWindowRepository {
    let writer: any DatabaseWriter

    public init(database: Database) {
        self.writer = database.writer
    }

    public func fetchAll() async throws -> [ActualWindow] {
        let records = try await writer.read { db in
            try ActualWindowRecord.fetchAll(db)
        }
        return try records.map { try $0.toActualWindow() }
    }

    public func fetchWindows(for interval: DateInterval) async throws -> [ActualWindow] {
        let startStr = DateTimeService.formatUTC(interval.start)
        let endStr = DateTimeService.formatUTC(interval.end)
        // Overlap match — see PlannedWindowRepository.fetchWindows for rationale.
        let records = try await writer.read { db in
            try ActualWindowRecord
                .filter(sql: """
                    datetime(start_at) < datetime(?) AND
                    datetime(start_at, '+' || duration_seconds || ' seconds') > datetime(?)
                    """, arguments: [endStr, startStr])
                .order(Column("start_at"))
                .fetchAll(db)
        }
        return try records.map { try $0.toActualWindow() }
    }

    public func create(_ window: ActualWindow) async throws {
        let record = ActualWindowRecord(from: window)
        try await writer.write { db in
            try record.insert(db)
        }
    }

    public func update(_ window: ActualWindow) async throws {
        var updated = window
        updated.updatedAt = .now
        let record = ActualWindowRecord(from: updated)
        try await writer.write { db in
            try record.update(db)
        }
    }

    public func upsertByEndAt(_ window: ActualWindow, tolerance: TimeInterval = 60) async throws {
        let targetEndAt = window.endAt
        let providerValue = window.providerID.rawValue
        let lowerStr = DateTimeService.formatUTC(targetEndAt.addingTimeInterval(-tolerance))
        let upperStr = DateTimeService.formatUTC(targetEndAt.addingTimeInterval(tolerance))
        let newStartStr = DateTimeService.formatUTC(window.startAt)
        let newEndStr = DateTimeService.formatUTC(window.endAt)

        try await writer.write { db in
            let endAtMatch = try ActualWindowRecord
                .filter(Column("provider_id") == providerValue)
                .filter(sql: """
                    datetime(start_at, '+' || duration_seconds || ' seconds') BETWEEN datetime(?) AND datetime(?)
                    """, arguments: [lowerStr, upperStr])
                .order(Column("start_at").desc)
                .fetchOne(db)

            // Fallback: when no row matches by endAt±tolerance, look for any
            // same-provider window whose interval overlaps the incoming one.
            // This collapses stale `[now, +5h, c5hTriggered]` placeholder rows
            // (written before we knew the real `resetsAt`) onto the corrected
            // window detected from upstream usage, instead of letting both
            // coexist.
            let existing: ActualWindowRecord?
            if let endAtMatch {
                existing = endAtMatch
            } else {
                existing = try ActualWindowRecord
                    .filter(Column("provider_id") == providerValue)
                    .filter(sql: """
                        datetime(start_at) < datetime(?) AND
                        datetime(start_at, '+' || duration_seconds || ' seconds') > datetime(?)
                        """, arguments: [newEndStr, newStartStr])
                    .order(Column("start_at").desc)
                    .fetchOne(db)
            }

            if let existing {
                var updated = try existing.toActualWindow()
                updated.startAt = window.startAt
                updated.durationSeconds = window.durationSeconds
                // Preserve a stronger user-visible tag: if the row was already
                // promoted to `c5hTriggered`/`exact` (e.g. by a manual Start
                // Now), a routine `detectedFromUsage`/`estimated` refresh
                // shouldn't downgrade the labels — only correct the times.
                if updated.source == .c5hTriggered, window.source == .detectedFromUsage {
                    // keep updated.source / updated.confidence / updated.commandRunID
                } else {
                    updated.source = window.source
                    updated.confidence = window.confidence
                }
                updated.usageEndSnapshotID = window.usageEndSnapshotID ?? updated.usageEndSnapshotID
                if updated.usageStartSnapshotID == nil {
                    updated.usageStartSnapshotID = window.usageStartSnapshotID
                }
                if updated.commandRunID == nil {
                    updated.commandRunID = window.commandRunID
                }
                updated.updatedAt = .now
                try ActualWindowRecord(from: updated).update(db)
            } else {
                try ActualWindowRecord(from: window).insert(db)
            }
        }
    }
}
