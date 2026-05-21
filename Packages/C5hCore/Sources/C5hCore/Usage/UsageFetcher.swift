import Foundation

/// Shared between the main app (`DashboardViewModel`) and the helper background
/// loop. Wraps a single `runUsageCommand()` call: persists the resulting raw
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

    /// Calls `adapter.runUsageCommand()`, persists the snapshot, then derives
    /// and upserts the primary 5h + (when reported) weekly quota rows.
    /// Returns the snapshot that was persisted.
    @discardableResult
    public func fetchAndPersist(
        adapter: any ProviderAdapter,
        now: Date = .now
    ) async throws -> UsageSnapshot {
        let snapshot = try await adapter.runUsageCommand()
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
    public func derived5h(
        from snapshot: UsageSnapshot,
        now: Date = .now
    ) throws -> ActualWindow5h? {
        switch snapshot.providerID {
        case .claude:
            let status = try ClaudeUsageStatus.parsePayload(snapshot.rawJSON)
            let window = status.actualWindow(providerID: .claude, createdAt: snapshot.capturedAt)
            return window.endAt > now ? window : nil
        case .codex:
            let status = try CodexUsageStatus.parseAny(snapshot.rawJSON, capturedAt: snapshot.capturedAt)
            let window = status.actualWindow(providerID: .codex, createdAt: snapshot.capturedAt)
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
