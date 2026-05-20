import Foundation
import GRDB
import C5hCore

public struct HelperHeartbeat: Sendable, Hashable {
    public let id: String
    public let helperVersion: String
    public let startedAt: Date
    public let lastSeenAt: Date
    public let pid: Int?
}

public protocol HelperHeartbeatRepository: Sendable {
    func writeHeartbeat(version: String, pid: Int?) async throws
    func latest() async throws -> HelperHeartbeat?
}

public struct GRDBHelperHeartbeatRepository: HelperHeartbeatRepository {
    let writer: any DatabaseWriter
    private static let singletonID = "singleton"

    public init(database: Database) {
        self.writer = database.writer
    }

    public func writeHeartbeat(version: String, pid: Int?) async throws {
        let nowStr = DateTimeService.formatUTC(.now)
        try await writer.write { db in
            let existing = try HelperHeartbeatRecord.fetchOne(db, key: Self.singletonID)
            // Reset startedAt when a new helper process is writing (pid
            // differs from the row's pid, or no prior row exists). Otherwise
            // preserve it so plain heartbeats from the same process keep
            // their original boot time.
            let isNewProcess = existing == nil || existing?.pid != pid
            let record = HelperHeartbeatRecord(
                id: Self.singletonID,
                helperVersion: version,
                startedAt: isNewProcess ? nowStr : (existing?.startedAt ?? nowStr),
                lastSeenAt: nowStr,
                pid: pid
            )
            try record.upsert(db)
        }
    }

    public func latest() async throws -> HelperHeartbeat? {
        let record = try await writer.read { db in
            try HelperHeartbeatRecord.fetchOne(db, key: Self.singletonID)
        }
        guard let r = record else { return nil }
        guard
            let started = DateTimeService.parseUTC(r.startedAt),
            let last = DateTimeService.parseUTC(r.lastSeenAt)
        else {
            return nil
        }
        return HelperHeartbeat(
            id: r.id,
            helperVersion: r.helperVersion,
            startedAt: started,
            lastSeenAt: last,
            pid: r.pid
        )
    }
}
