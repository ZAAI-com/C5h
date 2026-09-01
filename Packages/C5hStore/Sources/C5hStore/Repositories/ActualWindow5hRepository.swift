import Foundation
import GRDB
import C5hCore

public protocol ActualWindow5hRepository: Sendable {
    /// All read APIs expose only 5h-class rows. Legacy Codex releases could
    /// persist a weekly limit in this table; those rows remain available to the
    /// compatibility migration but must never participate in 5h UI or scheduling.
    func fetchAll() async throws -> [ActualWindow5h]
    func fetchWindows(for interval: DateInterval) async throws -> [ActualWindow5h]
    func fetchActiveWindow(providerID: ProviderID, at referenceTime: Date) async throws -> ActualWindow5h?
    func create(_ window: ActualWindow5h) async throws
    func update(_ window: ActualWindow5h) async throws

    /// Inserts the window, or updates an existing window for the same provider
    /// whose `endAt` is within `tolerance` of the new window's `endAt`. Used to
    /// collapse repeated polling snapshots of the same 5h limit window into a
    /// single row, so "last N windows" lists distinct actual windows instead of
    /// poll-time noise.
    func upsertByEndAt(_ window: ActualWindow5h, tolerance: TimeInterval) async throws
}

public extension ActualWindow5hRepository {
    /// Returns the latest same-provider window whose half-open interval covers
    /// `referenceTime`.
    ///
    /// The default implementation keeps test doubles and alternate stores
    /// source-compatible. GRDB overrides it below with a point lookup that does
    /// the provider and interval filtering in SQLite.
    func fetchActiveWindow(
        providerID: ProviderID,
        at referenceTime: Date
    ) async throws -> ActualWindow5h? {
        let candidates = try await fetchWindows(
            for: DateInterval(start: referenceTime, duration: 1)
        )
        return candidates
            .filter {
                $0.providerID == providerID
                    && $0.durationSeconds < CodexUsageStatus.weeklyClassThresholdSeconds
                    && $0.startAt <= referenceTime
                    && referenceTime < $0.endAt
            }
            .max { $0.startAt < $1.startAt }
    }

    /// Waits for another database client to persist the actual window covering
    /// `referenceTime`.
    ///
    /// A usage probe and a scheduled prompt can race for the shared probe lock.
    /// When the prompt loses that race, the winning probe will shortly persist
    /// the provider-reported window through another repository (and, in the
    /// helper/app case, another database connection). This method checks once
    /// immediately, then polls without launching another quota-consuming probe.
    ///
    /// Cancellation is propagated as `CancellationError`. A timeout is an
    /// expected "no matching row arrived" result and returns `nil`.
    func awaitActiveWindow(
        providerID: ProviderID,
        at referenceTime: Date,
        timeout: Duration = .seconds(35),
        pollInterval: Duration = .milliseconds(250)
    ) async throws -> ActualWindow5h? {
        try Task.checkCancellation()
        if let active = try await fetchActiveWindow(
            providerID: providerID,
            at: referenceTime
        ) {
            return active
        }

        guard timeout > .zero else { return nil }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        // Avoid a caller-supplied zero/negative interval spinning a database
        // read loop while still allowing very short intervals in tests.
        let effectivePollInterval = max(pollInterval, .milliseconds(1))

        while true {
            try Task.checkCancellation()
            let remaining = clock.now.duration(to: deadline)
            guard remaining > .zero else { return nil }

            try await Task.sleep(for: min(effectivePollInterval, remaining))
            try Task.checkCancellation()

            if let active = try await fetchActiveWindow(
                providerID: providerID,
                at: referenceTime
            ) {
                return active
            }
        }
    }
}

public struct GRDBActualWindow5hRepository: ActualWindow5hRepository {
    let writer: any DatabaseWriter

    public init(database: Database) {
        self.writer = database.writer
    }

    public func fetchAll() async throws -> [ActualWindow5h] {
        let records = try await writer.read { db in
            try ActualWindow5hRecord
                .filter(
                    Column("duration_seconds")
                        < CodexUsageStatus.weeklyClassThresholdSeconds
                )
                .fetchAll(db)
        }
        return try records.map { try $0.toActualWindow() }
    }

    public func fetchWindows(for interval: DateInterval) async throws -> [ActualWindow5h] {
        let startStr = DateTimeService.formatUTC(interval.start)
        let endStr = DateTimeService.formatUTC(interval.end)
        // Overlap match (see PlannedWindowRepository.fetchWindows for rationale).
        let records = try await writer.read { db in
            try ActualWindow5hRecord
                .filter(
                    Column("duration_seconds")
                        < CodexUsageStatus.weeklyClassThresholdSeconds
                )
                .filter(sql: """
                    datetime(start_at) < datetime(?) AND
                    datetime(start_at, '+' || duration_seconds || ' seconds') > datetime(?)
                    """, arguments: [endStr, startStr])
                .order(Column("start_at"))
                .fetchAll(db)
        }
        return try records.map { try $0.toActualWindow() }
    }

    public func fetchActiveWindow(
        providerID: ProviderID,
        at referenceTime: Date
    ) async throws -> ActualWindow5h? {
        let reference = DateTimeService.formatUTC(referenceTime)
        let record = try await writer.read { db in
            try ActualWindow5hRecord
                .filter(Column("provider_id") == providerID.rawValue)
                .filter(
                    Column("duration_seconds")
                        < CodexUsageStatus.weeklyClassThresholdSeconds
                )
                .filter(sql: """
                    julianday(start_at) <= julianday(?) AND
                    julianday(start_at) + (duration_seconds / 86400.0) > julianday(?)
                    """, arguments: [reference, reference])
                .order(Column("start_at").desc)
                .fetchOne(db)
        }
        return try record?.toActualWindow()
    }

    public func create(_ window: ActualWindow5h) async throws {
        let record = ActualWindow5hRecord(from: window)
        try await writer.write { db in
            try record.insert(db)
        }
    }

    public func update(_ window: ActualWindow5h) async throws {
        var updated = window
        updated.updatedAt = .now
        let record = ActualWindow5hRecord(from: updated)
        try await writer.write { db in
            try record.update(db)
        }
    }

    public func upsertByEndAt(_ window: ActualWindow5h, tolerance: TimeInterval = 60) async throws {
        // Defensive boundary: duration classification belongs upstream, but a
        // weekly-class row must never be newly persisted through the 5h upsert.
        guard window.durationSeconds < CodexUsageStatus.weeklyClassThresholdSeconds else {
            return
        }
        let targetEndAt = window.endAt
        let providerValue = window.providerID.rawValue
        let lowerStr = DateTimeService.formatUTC(targetEndAt.addingTimeInterval(-tolerance))
        let upperStr = DateTimeService.formatUTC(targetEndAt.addingTimeInterval(tolerance))
        let newStartStr = DateTimeService.formatUTC(window.startAt)
        let newEndStr = DateTimeService.formatUTC(window.endAt)

        try await writer.write { db in
            let endAtMatch = try ActualWindow5hRecord
                .filter(Column("provider_id") == providerValue)
                .filter(
                    Column("duration_seconds")
                        < CodexUsageStatus.weeklyClassThresholdSeconds
                )
                .filter(sql: """
                    datetime(start_at, '+' || duration_seconds || ' seconds') BETWEEN datetime(?) AND datetime(?)
                    """, arguments: [lowerStr, upperStr])
                .order(Column("start_at").desc)
                .fetchOne(db)

            // Fallback: when no row matches by endAt±tolerance, look for a stale
            // same-provider `c5hTriggered` placeholder whose interval overlaps the
            // incoming row. This collapses `[now, +5h, c5hTriggered]` placeholders
            // (written before we knew the real `resetsAt`) onto the corrected
            // window detected from upstream usage. The fallback is deliberately
            // limited to that case: two overlapping `detectedFromUsage` windows
            // with different reset/end times are distinct reset-derived windows
            // (e.g. a Claude tier change resets the 5h quota early), so they must
            // stay as separate rows instead of being merged away.
            let existing: ActualWindow5hRecord?
            if let endAtMatch {
                existing = endAtMatch
            } else if window.source == .detectedFromUsage {
                existing = try ActualWindow5hRecord
                    .filter(Column("provider_id") == providerValue)
                    .filter(Column("source") == ActualWindowSource.c5hTriggered.rawValue)
                    .filter(
                        Column("duration_seconds")
                            < CodexUsageStatus.weeklyClassThresholdSeconds
                    )
                    .filter(sql: """
                        datetime(start_at) < datetime(?) AND
                        datetime(start_at, '+' || duration_seconds || ' seconds') > datetime(?)
                        """, arguments: [newEndStr, newStartStr])
                    .order(Column("start_at").desc)
                    .fetchOne(db)
            } else {
                existing = nil
            }

            if let existing {
                var updated = try existing.toActualWindow()
                updated.startAt = window.startAt
                updated.durationSeconds = window.durationSeconds
                updated.timeZoneIdentifier = window.timeZoneIdentifier
                updated.localDate = window.localDate
                // Keep the stronger user-visible `c5hTriggered` tag through a
                // routine `detectedFromUsage` refresh, correcting only the times.
                // A triggered window that started life as a reused `estimated`
                // row (the trigger's fresh poll could not confirm the start, e.g.
                // a Codex synthetic "fresh slot") now gets confirmed by this real
                // anchored poll, so upgrade its confidence to `exact`. A
                // `detectedFromUsage` window reaching here is always a real,
                // anchored window: slots the provider has not opened yet are
                // dropped upstream by `UsageFetcher.derived5h`
                // (`CodexUsageStatus.hasActiveFiveHourWindow` for Codex,
                // `ClaudeUsageStatus.isProspectiveFiveHourSlot` for Claude).
                if updated.source == .c5hTriggered, window.source == .detectedFromUsage {
                    updated.confidence = .exact
                    // keep updated.source / updated.commandRunID
                } else {
                    updated.source = window.source
                    updated.confidence = window.confidence
                }
                updated.usageEndSnapshotID = window.usageEndSnapshotID ?? updated.usageEndSnapshotID
                if updated.usageStartSnapshotID == nil {
                    updated.usageStartSnapshotID = window.usageStartSnapshotID
                }
                if updated.commandRunID == nil {
                    updated.commandRunID = window.commandRunID
                }
                updated.updatedAt = .now
                try ActualWindow5hRecord(from: updated).update(db)
            } else {
                try ActualWindow5hRecord(from: window).insert(db)
            }
        }
    }
}
