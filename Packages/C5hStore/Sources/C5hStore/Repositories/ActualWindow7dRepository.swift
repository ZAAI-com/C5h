import Foundation
import GRDB
import C5hCore

public protocol ActualWindow7dRepository: Sendable {
    func fetchAll() async throws -> [ActualWindow7d]
    func fetchLatest(providerID: ProviderID) async throws -> ActualWindow7d?
    func create(_ window: ActualWindow7d) async throws
    func update(_ window: ActualWindow7d) async throws
    func upsertByEndAt(_ window: ActualWindow7d, tolerance: TimeInterval) async throws
}

public struct GRDBActualWindow7dRepository: ActualWindow7dRepository {
    let writer: any DatabaseWriter

    public init(database: Database) {
        self.writer = database.writer
    }

    public func fetchAll() async throws -> [ActualWindow7d] {
        let records = try await writer.read { db in
            try ActualWindow7dRecord
                .order(Column("start_at"))
                .fetchAll(db)
        }
        return try records.map { try $0.toActualWindow7d() }
    }

    public func fetchLatest(providerID: ProviderID) async throws -> ActualWindow7d? {
        let record = try await writer.read { db in
            try ActualWindow7dRecord
                .filter(Column("provider_id") == providerID.rawValue)
                .order(Column("start_at").desc)
                .fetchOne(db)
        }
        return try record?.toActualWindow7d()
    }

    public func create(_ window: ActualWindow7d) async throws {
        let record = ActualWindow7dRecord(from: window)
        try await writer.write { db in
            try record.insert(db)
        }
    }

    public func update(_ window: ActualWindow7d) async throws {
        var updated = window
        updated.updatedAt = .now
        let record = ActualWindow7dRecord(from: updated)
        try await writer.write { db in
            try record.update(db)
        }
    }

    public func upsertByEndAt(_ window: ActualWindow7d, tolerance: TimeInterval = 60) async throws {
        let targetEndAt = window.endAt
        let providerValue = window.providerID.rawValue
        let lowerStr = DateTimeService.formatUTC(targetEndAt.addingTimeInterval(-tolerance))
        let upperStr = DateTimeService.formatUTC(targetEndAt.addingTimeInterval(tolerance))

        try await writer.write { db in
            let existing = try ActualWindow7dRecord
                .filter(Column("provider_id") == providerValue)
                .filter(sql: """
                    datetime(start_at, '+' || duration_seconds || ' seconds') BETWEEN datetime(?) AND datetime(?)
                    """, arguments: [lowerStr, upperStr])
                .order(Column("start_at").desc)
                .fetchOne(db)

            if let existing {
                var updated = try existing.toActualWindow7d()
                updated.startAt = window.startAt
                updated.durationSeconds = window.durationSeconds
                updated.usedPercentage = window.usedPercentage
                updated.source = window.source
                updated.confidence = window.confidence
                updated.usageSnapshotID = window.usageSnapshotID ?? updated.usageSnapshotID
                updated.updatedAt = .now
                try ActualWindow7dRecord(from: updated).update(db)
            } else {
                try ActualWindow7dRecord(from: window).insert(db)
            }
        }
    }
}
