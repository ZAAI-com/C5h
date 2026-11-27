import Foundation
import GRDB
import C5hCore

public protocol UsageSnapshotRepository: Sendable {
    func create(_ snapshot: UsageSnapshot) async throws
    func fetchLatest(providerID: ProviderID) async throws -> UsageSnapshot?
    func fetchInRange(providerID: ProviderID, interval: DateInterval) async throws -> [UsageSnapshot]
}

public extension UsageSnapshotRepository {
    /// Whether the calendar draws this provider's 7d windows as blocks. Codex
    /// always does: it resets its weekly limit early and at irregular times,
    /// so the 7d boundaries are worth seeing even next to its 5h blocks.
    /// Other providers only when weekly-only, since otherwise their 7d usage
    /// already rides on the 5h blocks.
    func showsWeeklyWindowBlocks(providerID: ProviderID) async -> Bool {
        if providerID == .codex { return true }
        return await isWeeklyOnly(providerID: providerID)
    }

    /// True when the provider's latest usage snapshot reports a weekly limit but
    /// no 5h limit. Unknown (no snapshot / unparseable) is treated as not
    /// weekly-only, so 7d blocks stay hidden rather than shown speculatively.
    func isWeeklyOnly(providerID: ProviderID) async -> Bool {
        guard let snapshot = try? await fetchLatest(providerID: providerID),
              let limits = ProviderUsageLimits.from(snapshot: snapshot) else {
            return false
        }
        return limits.isWeeklyOnly
    }
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
