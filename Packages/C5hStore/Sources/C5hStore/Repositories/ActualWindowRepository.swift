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
        let records = try await writer.read { db in
            try ActualWindowRecord
                .filter(Column("start_at") >= startStr && Column("start_at") < endStr)
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
