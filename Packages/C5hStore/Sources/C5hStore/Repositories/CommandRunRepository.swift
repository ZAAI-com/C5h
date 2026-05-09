import Foundation
import GRDB
import C5hCore

public struct CommandRunFilter: Sendable {
    public var providerID: ProviderID?
    public var status: CommandRunStatus?
    public var runType: CommandRunType?
    public var since: Date?

    public init(
        providerID: ProviderID? = nil,
        status: CommandRunStatus? = nil,
        runType: CommandRunType? = nil,
        since: Date? = nil
    ) {
        self.providerID = providerID
        self.status = status
        self.runType = runType
        self.since = since
    }
}

public protocol CommandRunRepository: Sendable {
    func create(_ run: CommandRun) async throws
    func update(_ run: CommandRun) async throws
    func fetch(id: UUID) async throws -> CommandRun?
    func fetchRecent(limit: Int, filter: CommandRunFilter) async throws -> [CommandRun]
    func sweepStaleRunning(message: String) async throws -> Int
}

public struct GRDBCommandRunRepository: CommandRunRepository {
    let writer: any DatabaseWriter

    public init(database: Database) {
        self.writer = database.writer
    }

    public func create(_ run: CommandRun) async throws {
        let record = CommandRunRecord(from: run)
        try await writer.write { db in
            try record.insert(db)
        }
    }

    public func update(_ run: CommandRun) async throws {
        let record = CommandRunRecord(from: run)
        try await writer.write { db in
            try record.update(db)
        }
    }

    public func fetch(id: UUID) async throws -> CommandRun? {
        let record = try await writer.read { db in
            try CommandRunRecord.fetchOne(db, key: id.uuidString)
        }
        return try record?.toCommandRun()
    }

    public func fetchRecent(limit: Int, filter: CommandRunFilter) async throws -> [CommandRun] {
        let records = try await writer.read { db in
            var request = CommandRunRecord.all().order(Column("started_at").desc)
            if let pid = filter.providerID {
                request = request.filter(Column("provider_id") == pid.rawValue)
            }
            if let st = filter.status {
                request = request.filter(Column("status") == st.rawValue)
            }
            if let rt = filter.runType {
                request = request.filter(Column("run_type") == rt.rawValue)
            }
            if let since = filter.since {
                request = request.filter(Column("started_at") >= DateTimeService.formatUTC(since))
            }
            return try request.limit(limit).fetchAll(db)
        }
        return try records.map { try $0.toCommandRun() }
    }

    public func sweepStaleRunning(message: String) async throws -> Int {
        try await writer.write { db in
            try db.execute(
                sql: """
                UPDATE command_runs
                SET status = ?, ended_at = ?, error = ?
                WHERE status = ?
                """,
                arguments: [
                    CommandRunStatus.cancelled.rawValue,
                    DateTimeService.formatUTC(.now),
                    message,
                    CommandRunStatus.running.rawValue
                ]
            )
            return db.changesCount
        }
    }
}
