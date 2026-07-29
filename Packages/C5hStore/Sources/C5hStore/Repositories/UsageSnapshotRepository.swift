import Foundation
import GRDB
import C5hCore

public protocol UsageSnapshotRepository: Sendable {
    func create(_ snapshot: UsageSnapshot) async throws
    func fetchLatest(providerID: ProviderID) async throws -> UsageSnapshot?
    func fetchInRange(providerID: ProviderID, interval: DateInterval) async throws -> [UsageSnapshot]
}

public extension UsageSnapshotRepository {
    /// Builds the lookup `UsageFetcher` uses to tell a fresh 0%-usage window
    /// from a chained idle boundary: the end of the most recent snapshot whose
    /// reported window differs from the one starting at `currentWindowStart`.
    /// Scans a bounded lookback and skips re-readings of the current window, so
    /// a repeated poll of the same window (already persisted) does not shadow
    /// the genuinely previous window.
    func previousWindowEndLookup(
        lookback: TimeInterval = 24 * 60 * 60
    ) -> UsageFetcher.PreviousWindowEndLookup {
        { providerID, currentWindowStart in
            let interval = DateInterval(
                start: currentWindowStart.addingTimeInterval(-lookback),
                end: currentWindowStart.addingTimeInterval(UsageFetcher.dedupTolerance)
            )
            let snapshots = try await fetchInRange(providerID: providerID, interval: interval)
            for snapshot in snapshots.reversed() {
                guard let normalized = UsageNormalizer.decode(snapshot.normalizedJSON) else {
                    continue
                }
                // Skip re-readings of the current window; we want the window
                // that preceded it.
                if let start = normalized.windowStartedAt,
                   abs(start.timeIntervalSince(currentWindowStart)) <= UsageFetcher.dedupTolerance {
                    continue
                }
                if let end = normalized.windowEndsAt {
                    return end
                }
            }
            return nil
        }
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
