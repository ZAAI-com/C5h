import Foundation

/// Shared between the main app (`DashboardViewModel`) and the helper background
/// loop. Wraps a single `runUsage()` call: persists the resulting raw
/// `UsageSnapshot` and upserts the derived rolling 5h + weekly quota rows so
/// repeated polling collapses to one row per real provider window.
public struct UsageFetcher: Sendable {
    public static let dedupTolerance: TimeInterval = 60

    public typealias PersistSnapshot = @Sendable (UsageSnapshot) async throws -> Void
    public typealias UpsertActualWindow5h = @Sendable (ActualWindow5h, TimeInterval) async throws -> Void
    public typealias UpsertActualWindow7d = @Sendable (ActualWindow7d, TimeInterval) async throws -> Void
    /// Returns the end of the most recent *different* window reported for the
    /// provider before the window starting at `currentWindowStart`, or nil when
    /// no prior window is on record. Used to distinguish a genuine fresh
    /// 0%-usage window from the provider's idle boundary chained onto the
    /// previous window's end.
    public typealias PreviousWindowEndLookup =
        @Sendable (_ providerID: ProviderID, _ currentWindowStart: Date) async throws -> Date?

    public let persistSnapshot: PersistSnapshot
    public let upsertActualWindow5h: UpsertActualWindow5h
    public let upsertActualWindow7d: UpsertActualWindow7d
    public let previousWindowEndLookup: PreviousWindowEndLookup

    public init(
        persistSnapshot: @escaping PersistSnapshot,
        upsertActualWindow5h: @escaping UpsertActualWindow5h,
        upsertActualWindow7d: @escaping UpsertActualWindow7d,
        previousWindowEndLookup: @escaping PreviousWindowEndLookup = { _, _ in nil }
    ) {
        self.persistSnapshot = persistSnapshot
        self.upsertActualWindow5h = upsertActualWindow5h
        self.upsertActualWindow7d = upsertActualWindow7d
        self.previousWindowEndLookup = previousWindowEndLookup
    }

    /// The end of the window that preceded the one `snapshot` reports, resolved
    /// via `previousWindowEndLookup`. Call before persisting `snapshot` so a
    /// repeated poll of the same window does not shadow the genuinely previous
    /// window. Returns nil when the snapshot has no normalized window start or
    /// the provider has no prior window on record.
    public func previousWindowEnd(for snapshot: UsageSnapshot) async throws -> Date? {
        guard let currentStart = UsageNormalizer.decode(snapshot.normalizedJSON)?.windowStartedAt else {
            return nil
        }
        return try await previousWindowEndLookup(snapshot.providerID, currentStart)
    }

    /// Calls `adapter.runUsage()`, persists the snapshot, then derives
    /// and upserts the primary 5h + (when reported) weekly quota rows.
    /// Returns the snapshot that was persisted.
    @discardableResult
    public func fetchAndPersist(
        adapter: any ProviderAdapter,
        now: Date = .now
    ) async throws -> UsageSnapshot {
        let snapshot = try await adapter.runUsage()
        let previousEnd = try await previousWindowEnd(for: snapshot)
        try await persistSnapshot(snapshot)

        if let window = try derived5h(from: snapshot, now: now, previousWindowEnd: previousEnd) {
            try await upsertActualWindow5h(window, Self.dedupTolerance)
        }
        if let window = try derived7d(from: snapshot) {
            try await upsertActualWindow7d(window, Self.dedupTolerance)
        }
        return snapshot
    }

    /// Derives the rolling 5h row from a freshly-captured snapshot. Exposed for
    /// unit tests; callers should normally use `fetchAndPersist`.
    ///
    /// `requireActiveWindow` (default true) drops reports that don't reflect a
    /// genuinely active window, so idle polls don't fabricate phantom 5h windows.
    /// The trigger-anchoring path passes false: a wake prompt just opened the
    /// window on purpose, so it should anchor even before usage registers.
    ///
    /// `previousWindowEnd` is the end of the window that preceded this report
    /// (see `previousWindowEnd(for:)`). It rescues a genuine Claude window used
    /// below Claude's ~1% reporting resolution: such a window reports 0% yet is
    /// a real, live window. It is kept when its start is a *fresh anchor* and
    /// dropped only when it is the idle boundary chained onto `previousWindowEnd`
    /// (the mis-gated-probe phantom `requireActiveWindow` guards against).
    public func derived5h(
        from snapshot: UsageSnapshot,
        now: Date = .now,
        requireActiveWindow: Bool = true,
        previousWindowEnd: Date? = nil
    ) throws -> ActualWindow5h? {
        switch snapshot.providerID {
        case .claude:
            let status = try ClaudeUsageStatus.parsePayload(snapshot.rawJSON)
            if requireActiveWindow,
               !status.hasActiveFiveHourWindow,
               !status.isFreshFiveHourAnchor(
                   previousWindowEnd: previousWindowEnd,
                   tolerance: Self.dedupTolerance
               ) {
                return nil
            }
            let window = status.actualWindow(providerID: .claude, createdAt: snapshot.capturedAt)
            return window.endAt > now ? window : nil
        case .codex:
            let status = try CodexUsageStatus.parseAny(snapshot.rawJSON, capturedAt: snapshot.capturedAt)
            if requireActiveWindow, !status.hasActiveFiveHourWindow { return nil }
            guard let window = status.actualWindow(providerID: .codex, createdAt: snapshot.capturedAt) else {
                return nil
            }
            return window.endAt > now ? window : nil
        }
    }

    /// Derives the weekly quota row from a freshly-captured snapshot. Exposed
    /// for unit tests; callers should normally use `fetchAndPersist`.
    public func derived7d(from snapshot: UsageSnapshot) throws -> ActualWindow7d? {
        switch snapshot.providerID {
        case .claude:
            let status = try ClaudeUsageStatus.parsePayload(snapshot.rawJSON)
            return status.sevenDayActualWindow(
                providerID: .claude,
                usageSnapshotID: snapshot.id,
                createdAt: snapshot.capturedAt
            )
        case .codex:
            let status = try CodexUsageStatus.parseAny(snapshot.rawJSON, capturedAt: snapshot.capturedAt)
            return status.secondaryActualWindow(
                providerID: .codex,
                usageSnapshotID: snapshot.id,
                createdAt: snapshot.capturedAt
            )
        }
    }
}
