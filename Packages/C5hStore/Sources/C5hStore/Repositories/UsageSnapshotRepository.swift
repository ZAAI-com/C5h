import Foundation
import GRDB
import C5hCore

public protocol UsageSnapshotRepository: Sendable {
    func create(_ snapshot: UsageSnapshot) async throws
    func fetchLatest(providerID: ProviderID) async throws -> UsageSnapshot?
    func fetchInRange(providerID: ProviderID, interval: DateInterval) async throws -> [UsageSnapshot]
}

public struct GRDBUsageSnapshotRepository: UsageSnapshotRepository {
    let writer: any DatabaseWriter

    public init(database: Database) {
        self.writer = database.writer
    }

    public func create(_ snapshot: UsageSnapshot) async throws {
        let record = UsageSnapshotRecord(from: snapshot)
        try await writer.write { db in
            try record.insert(db)
        }
    }

    public func fetchLatest(providerID: ProviderID) async throws -> UsageSnapshot? {
        let record = try await writer.read { db in
            try UsageSnapshotRecord
                .filter(Column("provider_id") == providerID.rawValue)
                .order(Column("captured_at").desc)
                .fetchOne(db)
        }
        return try record?.toUsageSnapshot()
    }

    public func fetchInRange(
        providerID: ProviderID,
        interval: DateInterval
    ) async throws -> [UsageSnapshot] {
        let startStr = DateTimeService.formatUTC(interval.start)
        let endStr = DateTimeService.formatUTC(interval.end)
        let records = try await writer.read { db in
            try UsageSnapshotRecord
                .filter(Column("provider_id") == providerID.rawValue)
                .filter(Column("captured_at") >= startStr)
                .filter(Column("captured_at") < endStr)
                .order(Column("captured_at"))
                .fetchAll(db)
        }
        return try records.map { try $0.toUsageSnapshot() }
    }
}
