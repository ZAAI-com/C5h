import Foundation
import Darwin
import GRDB
import C5hCore

public struct CommandRunFilter: Sendable {
    public var providerID: ProviderID?
    public var status: CommandRunStatus?
    public var commandName: CommandName?
    public var since: Date?

    public init(
        providerID: ProviderID? = nil,
        status: CommandRunStatus? = nil,
        commandName: CommandName? = nil,
        since: Date? = nil
    ) {
        self.providerID = providerID
        self.status = status
        self.commandName = commandName
        self.since = since
    }
}

public protocol CommandRunRepository: Sendable {
    func create(_ run: CommandRun) async throws
    func update(_ run: CommandRun) async throws
    func fetch(id: UUID) async throws -> CommandRun?
    func fetchRecent(limit: Int, filter: CommandRunFilter) async throws -> [CommandRun]
    func sweepStaleRunning(message: String, isAlive: @Sendable (Int32) -> Bool) async throws -> Int
}

public extension CommandRunRepository {
    func sweepStaleRunning(message: String) async throws -> Int {
        try await sweepStaleRunning(message: message, isAlive: ProcessLiveness.isAlive)
    }
}

public enum ProcessLiveness {
    /// Returns true if `pid` names a process this user can observe.
    /// `kill(pid, 0)` returns 0 if the process exists and is signalable, -1
    /// with `errno == ESRCH` if it doesn't exist, or `errno == EPERM` if it
    /// exists but we cannot signal it (treat as alive).
    public static func isAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }
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
            if let name = filter.commandName {
                request = request.filter(Column("run_type") == name.rawValue)
            }
            if let since = filter.since {
                request = request.filter(Column("started_at") >= DateTimeService.formatUTC(since))
            }
            return try request.limit(limit).fetchAll(db)
        }
        return try records.map { try $0.toCommandRun() }
    }

    public func sweepStaleRunning(
        message: String,
        isAlive: @Sendable (Int32) -> Bool
    ) async throws -> Int {
        try await writer.write { db in
            let runningRows = try Row.fetchAll(
                db,
                sql: "SELECT id, owner_pid FROM command_runs WHERE status = ?",
                arguments: [CommandRunStatus.running.rawValue]
            )

            // Legacy rows (owner_pid NULL) and rows whose owner is no longer
            // alive are eligible. Rows owned by a live process — possibly this
            // process itself or a sibling app/helper — stay running.
            let staleIDs: [String] = runningRows.compactMap { row in
                guard let id: String = row["id"] else { return nil }
                let ownerPid: Int? = row["owner_pid"]
                if let ownerPid {
                    return isAlive(Int32(ownerPid)) ? nil : id
                }
                return id
            }

            guard !staleIDs.isEmpty else { return 0 }

            let placeholders = Array(repeating: "?", count: staleIDs.count).joined(separator: ",")
            var arguments: [DatabaseValueConvertible?] = [
                CommandRunStatus.cancelled.rawValue,
                DateTimeService.formatUTC(.now),
                message
            ]
            arguments.append(contentsOf: staleIDs.map { $0 as DatabaseValueConvertible? })
            try db.execute(
                sql: """
                UPDATE command_runs
                SET status = ?, ended_at = ?, error = ?
                WHERE id IN (\(placeholders))
                """,
                arguments: StatementArguments(arguments)
            )
            return db.changesCount
        }
    }
}
