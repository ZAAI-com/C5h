import Foundation
import GRDB
import C5hCore

public protocol ScheduledPromptRepository: Sendable {
    func create(_ prompt: ScheduledPrompt) async throws
    func fetch(id: UUID) async throws -> ScheduledPrompt?
    func fetchDuePrompts(now: Date) async throws -> [ScheduledPrompt]
    func reschedulePendingPrompts(
        plannedWindowID: UUID,
        providerID: ProviderID,
        projectPath: String?,
        runAt: Date
    ) async throws
    func cancelPendingAndDetachPrompts(plannedWindowID: UUID) async throws
    func tryClaimAsRunning(id: UUID) async throws -> Bool
    func markSucceeded(id: UUID) async throws
    func markFailed(id: UUID, error: String) async throws
    func markMissed(id: UUID) async throws
    func cancel(id: UUID) async throws
    func reconcileLinkedPlannedWindowStatuses() async throws -> Int
}

public struct GRDBScheduledPromptRepository: ScheduledPromptRepository {
    let writer: any DatabaseWriter

    public init(database: Database) {
        self.writer = database.writer
    }

    public func create(_ prompt: ScheduledPrompt) async throws {
        let record = ScheduledPromptRecord(from: prompt)
        try await writer.write { db in
            try record.insert(db)
        }
    }

    public func fetch(id: UUID) async throws -> ScheduledPrompt? {
        let record = try await writer.read { db in
            try ScheduledPromptRecord.fetchOne(db, key: id.uuidString)
        }
        return try record?.toScheduledPrompt()
    }

    public func fetchDuePrompts(now: Date) async throws -> [ScheduledPrompt] {
        let nowStr = DateTimeService.formatUTC(now)
        let records = try await writer.read { db in
            try ScheduledPromptRecord
                .filter(Column("status") == ScheduledPromptStatus.scheduled.rawValue)
                .filter(Column("run_at") <= nowStr)
                .order(Column("run_at"))
                .fetchAll(db)
        }
        return try records.map { try $0.toScheduledPrompt() }
    }

    public func reschedulePendingPrompts(
        plannedWindowID: UUID,
        providerID: ProviderID,
        projectPath: String?,
        runAt: Date
    ) async throws {
        try await writer.write { db in
            try db.execute(
                sql: """
                UPDATE scheduled_prompts
                SET provider_id = ?, project_path = ?, run_at = ?, updated_at = ?
                WHERE planned_window_id = ?
                  AND status IN (?, ?)
                """,
                arguments: [
                    providerID.rawValue,
                    projectPath,
                    DateTimeService.formatUTC(runAt),
                    DateTimeService.formatUTC(.now),
                    plannedWindowID.uuidString,
                    ScheduledPromptStatus.scheduled.rawValue,
                    ScheduledPromptStatus.due.rawValue
                ]
            )
        }
    }

    public func cancelPendingAndDetachPrompts(plannedWindowID: UUID) async throws {
        try await writer.write { db in
            try db.execute(
                sql: """
                UPDATE scheduled_prompts
                SET status = CASE
                        WHEN status IN (?, ?) THEN ?
                        ELSE status
                    END,
                    planned_window_id = NULL,
                    updated_at = ?
                WHERE planned_window_id = ?
                """,
                arguments: [
                    ScheduledPromptStatus.scheduled.rawValue,
                    ScheduledPromptStatus.due.rawValue,
                    ScheduledPromptStatus.cancelled.rawValue,
                    DateTimeService.formatUTC(.now),
                    plannedWindowID.uuidString
                ]
            )
        }
    }

    public func tryClaimAsRunning(id: UUID) async throws -> Bool {
        try await writer.write { db in
            let count = try Int.fetchOne(
                db,
                sql: """
                UPDATE scheduled_prompts
                SET status = ?, attempts = attempts + 1, updated_at = ?
                WHERE id = ? AND status = ?
                RETURNING 1
                """,
                arguments: [
                    ScheduledPromptStatus.running.rawValue,
                    DateTimeService.formatUTC(.now),
                    id.uuidString,
                    ScheduledPromptStatus.scheduled.rawValue
                ]
            ) ?? 0
            return count > 0
        }
    }

    public func markSucceeded(id: UUID) async throws {
        try await transitionStatus(id: id, to: .succeeded, error: nil)
    }

    public func markFailed(id: UUID, error: String) async throws {
        try await transitionStatus(id: id, to: .failed, error: error)
    }

    public func markMissed(id: UUID) async throws {
        try await transitionStatus(id: id, to: .missed, error: nil)
    }

    public func cancel(id: UUID) async throws {
        try await transitionStatus(id: id, to: .cancelled, error: nil)
    }

    public func reconcileLinkedPlannedWindowStatuses() async throws -> Int {
        let now = DateTimeService.formatUTC(.now)
        let succeeded = ScheduledPromptStatus.succeeded.rawValue
        let missed = ScheduledPromptStatus.missed.rawValue
        let failed = ScheduledPromptStatus.failed.rawValue
        let cancelled = ScheduledPromptStatus.cancelled.rawValue
        let triggeredWindow = PlannedWindowStatus.triggered.rawValue
        let missedWindow = PlannedWindowStatus.missed.rawValue
        let cancelledWindow = PlannedWindowStatus.cancelled.rawValue

        return try await writer.write { db in
            try db.execute(
                sql: """
                UPDATE planned_windows
                SET status = CASE (
                        SELECT sp.status
                        FROM scheduled_prompts sp
                        WHERE sp.planned_window_id = planned_windows.id
                          AND sp.status IN (?, ?, ?, ?)
                        ORDER BY datetime(sp.updated_at) DESC, datetime(sp.run_at) DESC
                        LIMIT 1
                    )
                    WHEN ? THEN ?
                    WHEN ? THEN ?
                    WHEN ? THEN ?
                    WHEN ? THEN ?
                    ELSE status
                    END,
                    updated_at = ?
                WHERE status NOT IN (?, ?, ?)
                  AND EXISTS (
                    SELECT 1
                    FROM scheduled_prompts sp
                    WHERE sp.planned_window_id = planned_windows.id
                      AND sp.status IN (?, ?, ?, ?)
                  )
                """,
                arguments: [
                    succeeded,
                    missed,
                    failed,
                    cancelled,
                    succeeded,
                    triggeredWindow,
                    missed,
                    missedWindow,
                    failed,
                    missedWindow,
                    cancelled,
                    cancelledWindow,
                    now,
                    triggeredWindow,
                    missedWindow,
                    cancelledWindow,
                    succeeded,
                    missed,
                    failed,
                    cancelled
                ]
            )
            return db.changesCount
        }
    }

    private func transitionStatus(
        id: UUID,
        to status: ScheduledPromptStatus,
        error: String?
    ) async throws {
        let now = DateTimeService.formatUTC(.now)
        try await writer.write { db in
            try db.execute(
                sql: """
                UPDATE scheduled_prompts
                SET status = ?, last_error = ?, updated_at = ?
                WHERE id = ?
                """,
                arguments: [
                    status.rawValue,
                    error,
                    now,
                    id.uuidString
                ]
            )
            guard let plannedStatus = Self.plannedWindowStatus(for: status) else {
                return
            }
            try db.execute(
                sql: """
                UPDATE planned_windows
                SET status = ?, updated_at = ?
                WHERE id = (
                    SELECT planned_window_id
                    FROM scheduled_prompts
                    WHERE id = ?
                )
                  AND status NOT IN (?, ?, ?)
                """,
                arguments: [
                    plannedStatus.rawValue,
                    now,
                    id.uuidString,
                    PlannedWindowStatus.triggered.rawValue,
                    PlannedWindowStatus.missed.rawValue,
                    PlannedWindowStatus.cancelled.rawValue
                ]
            )
        }
    }

    private static func plannedWindowStatus(for status: ScheduledPromptStatus) -> PlannedWindowStatus? {
        switch status {
        case .succeeded:
            return .triggered
        case .missed, .failed:
            return .missed
        case .cancelled:
            return .cancelled
        case .scheduled, .due, .running:
            return nil
        }
    }
}
