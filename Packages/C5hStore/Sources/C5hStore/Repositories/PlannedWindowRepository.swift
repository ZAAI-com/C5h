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
            try record.insert(db)
        }
    }

    public func update(_ window: PlannedWindow) async throws {
        var updated = window
        updated.updatedAt = .now
        let record = PlannedWindowRecord(from: updated)
        try await writer.write { db in
            try record.update(db)
        }
    }

    public func delete(id: UUID) async throws {
        try await writer.write { db in
            _ = try PlannedWindowRecord.deleteOne(db, key: id.uuidString)
        }
    }
}
