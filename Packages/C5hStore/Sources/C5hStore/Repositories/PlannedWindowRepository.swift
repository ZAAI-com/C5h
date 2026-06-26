import Foundation
import GRDB
import C5hCore

public protocol PlannedWindowRepository: Sendable {
    func fetchAll() async throws -> [PlannedWindow]
    func fetchWindows(for interval: DateInterval) async throws -> [PlannedWindow]
    func fetch(id: UUID) async throws -> PlannedWindow?
    func create(_ window: PlannedWindow) async throws
    func update(_ window: PlannedWindow) async throws
    func delete(id: UUID) async throws
    /// Cancels pending prompts and deletes the planned window in one transaction.
    func deleteWithPendingPromptCleanup(id: UUID) async throws
}

public struct GRDBPlannedWindowRepository: PlannedWindowRepository {
    let writer: any DatabaseWriter

    public init(database: Database) {
        self.writer = database.writer
    }

    public func fetchAll() async throws -> [PlannedWindow] {
        let records = try await writer.read { db in
            try PlannedWindowRecord.fetchAll(db)
        }
        return try records.map { try $0.toPlannedWindow() }
    }

    public func fetchWindows(for interval: DateInterval) async throws -> [PlannedWindow] {
        let startStr = DateTimeService.formatUTC(interval.start)
        let endStr = DateTimeService.formatUTC(interval.end)
        // Match every window that overlaps the interval, not just those whose
        // start_at falls inside it. A 5h window starting at 22:00 should still
        // appear on the following day's view.
        let records = try await writer.read { db in
            try PlannedWindowRecord
                .filter(sql: """
                    datetime(start_at) < datetime(?) AND
                    datetime(start_at, '+' || duration_seconds || ' seconds') > datetime(?)
                    """, arguments: [endStr, startStr])
                .order(Column("start_at"))
                .fetchAll(db)
        }
        return try records.map { try $0.toPlannedWindow() }
    }

    public func fetch(id: UUID) async throws -> PlannedWindow? {
        let record = try await writer.read { db in
            try PlannedWindowRecord.fetchOne(db, key: id.uuidString)
        }
        return try record?.toPlannedWindow()
    }

    public func create(_ window: PlannedWindow) async throws {
        let record = PlannedWindowRecord(from: window)
        try await writer.write { db in
            try Self.assertNoOverlap(window, db: db)
            try record.insert(db)
        }
    }

    public func update(_ window: PlannedWindow) async throws {
        var next = window
        next.updatedAt = .now
        let updated = next
        let record = PlannedWindowRecord(from: updated)
        try await writer.write { db in
            try Self.assertNoOverlap(updated, db: db)
            try record.update(db)
        }
    }

    public func delete(id: UUID) async throws {
        try await writer.write { db in
            _ = try PlannedWindowRecord.deleteOne(db, key: id.uuidString)
        }
    }

    public func deleteWithPendingPromptCleanup(id: UUID) async throws {
        try await writer.write { db in
            try db.execute(
                sql: """
                UPDATE scheduled_prompts
                SET status = CASE
                        WHEN status IN (?, ?) THEN ?
                        ELSE status
                    END,
                    planned_window_id = NULL,
                    updated_at = ?
                WHERE planned_window_id = ?
                """,
                arguments: [
                    ScheduledPromptStatus.scheduled.rawValue,
                    ScheduledPromptStatus.due.rawValue,
                    ScheduledPromptStatus.cancelled.rawValue,
                    DateTimeService.formatUTC(.now),
                    id.uuidString
                ]
            )
            _ = try PlannedWindowRecord.deleteOne(db, key: id.uuidString)
        }
    }

    private static func assertNoOverlap(
        _ window: PlannedWindow,
        db: GRDB.Database
    ) throws {
        let startStr = DateTimeService.formatUTC(window.startAt)
        let endStr = DateTimeService.formatUTC(window.endAt)
        let nowStr = DateTimeService.formatUTC(.now)
        let conflict = try PlannedWindowRecord
            .filter(Column("provider_id") == window.providerID.rawValue)
            .filter(Column("id") != window.id.uuidString)
            .filter(sql: """
                datetime(start_at) < datetime(?) AND
                datetime(start_at, '+' || duration_seconds || ' seconds') > datetime(?)
                """, arguments: [endStr, startStr])
            .fetchOne(db)

        if conflict != nil {
            throw C5hError.schedulerError(
                "\(window.providerID.displayName) planned windows cannot overlap"
            )
        }

        let activeActualConflict = try ActualWindow5hRecord
            .filter(Column("provider_id") == window.providerID.rawValue)
            .filter(sql: """
                datetime(start_at) <= datetime(?) AND
                datetime(start_at, '+' || duration_seconds || ' seconds') > datetime(?) AND
                datetime(start_at) < datetime(?) AND
                datetime(start_at, '+' || duration_seconds || ' seconds') > datetime(?)
                """, arguments: [nowStr, nowStr, endStr, startStr])
            .fetchOne(db)

        if activeActualConflict != nil {
            throw C5hError.schedulerError(
                "\(window.providerID.displayName) planned windows cannot overlap an active actual window"
            )
        }
    }
}
