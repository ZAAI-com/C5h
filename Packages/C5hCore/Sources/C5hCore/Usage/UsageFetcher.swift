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

    public let persistSnapshot: PersistSnapshot
    public let upsertActualWindow5h: UpsertActualWindow5h
    public let upsertActualWindow7d: UpsertActualWindow7d

    public init(
        persistSnapshot: @escaping PersistSnapshot,
        upsertActualWindow5h: @escaping UpsertActualWindow5h,
        upsertActualWindow7d: @escaping UpsertActualWindow7d
    ) {
        self.persistSnapshot = persistSnapshot
        self.upsertActualWindow5h = upsertActualWindow5h
        self.upsertActualWindow7d = upsertActualWindow7d
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
        try await persistSnapshot(snapshot)

        if let window = try derived5h(from: snapshot, now: now) {
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
    /// Claude's reported countdown is authoritative regardless of percentage,
    /// provided it is live and no farther away than one 5h window plus clock
    /// tolerance at capture time.
    ///
    /// `requireActiveWindow` drops reports that describe a window the provider
    /// has not actually opened: Codex's synthetic full-duration slot, and the
    /// prospective slot Claude slides forward every 10 minutes while idle.
    /// Both re-issue a different reset end on every poll, so persisting them
    /// inserts a row per poll rather than tracking one window. The
    /// trigger-anchoring path passes false for Claude on purpose (a wake prompt
    /// just opened the window, so it should anchor before usage registers); see
    /// `ActiveWindowResolver.promoteFromSnapshot`.
    public func derived5h(
        from snapshot: UsageSnapshot,
        now: Date = .now,
        requireActiveWindow: Bool = true
    ) throws -> ActualWindow5h? {
        switch snapshot.providerID {
        case .claude:
            let status = try ClaudeUsageStatus.parsePayload(snapshot.rawJSON)
            if !status.hasLiveFiveHourTimer(capturedAt: snapshot.capturedAt) {
                return nil
            }
            if requireActiveWindow,
               status.isProspectiveFiveHourSlot(capturedAt: snapshot.capturedAt) {
                return nil
            }
            // The snapshot proves this was a real window at capture time. Keep
            // it as history even if persistence is delayed until after reset.
            return status.actualWindow(providerID: .claude, createdAt: snapshot.capturedAt)
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
    ///
    /// Mirrors `derived5h`: a weekly slot the provider has not opened yet (0%
    /// used, resetting almost exactly one duration from the capture) is issued
    /// afresh on every poll, so it is dropped rather than persisted. The guard
    /// lives here and not in `secondaryActualWindow` / `sevenDayActualWindow`
    /// because the legacy-reclassification migration derives its recovery
    /// evidence through those methods and needs them to stay permissive.
    public func derived7d(from snapshot: UsageSnapshot) throws -> ActualWindow7d? {
        switch snapshot.providerID {
        case .claude:
            let status = try ClaudeUsageStatus.parsePayload(snapshot.rawJSON)
            if status.isProspectiveSevenDaySlot(capturedAt: snapshot.capturedAt) {
                return nil
            }
            return status.sevenDayActualWindow(
                providerID: .claude,
                usageSnapshotID: snapshot.id,
                createdAt: snapshot.capturedAt
            )
        case .codex:
            let status = try CodexUsageStatus.parseAny(snapshot.rawJSON, capturedAt: snapshot.capturedAt)
            if status.isSyntheticFreshWeeklySlot { return nil }
            return status.secondaryActualWindow(
                providerID: .codex,
                usageSnapshotID: snapshot.id,
                createdAt: snapshot.capturedAt
            )
        }
    }
}
