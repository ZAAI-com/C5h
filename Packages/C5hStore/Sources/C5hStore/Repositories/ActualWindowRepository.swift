import Foundation
import GRDB
import C5hCore

public protocol ActualWindowRepository: Sendable {
    func fetchAll() async throws -> [ActualWindow]
    func fetchWindows(for interval: DateInterval) async throws -> [ActualWindow]
    func create(_ window: ActualWindow) async throws
    func update(_ window: ActualWindow) async throws
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
}
