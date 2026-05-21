import Foundation

/// Shared between the main app (`DashboardViewModel`) and the helper background
/// loop. Wraps a single `runUsageCommand()` call: persists the resulting raw
/// `UsageSnapshot` and upserts the derived `ActualWindow` rows so repeated
/// polling collapses to one row per real 5h-limit window.
public struct UsageFetcher: Sendable {
    public static let dedupTolerance: TimeInterval = 60

    public typealias PersistSnapshot = @Sendable (UsageSnapshot) async throws -> Void
    public typealias UpsertActualWindow = @Sendable (ActualWindow, TimeInterval) async throws -> Void

    public let persistSnapshot: PersistSnapshot
    public let upsertActualWindow: UpsertActualWindow

    public init(
        persistSnapshot: @escaping PersistSnapshot,
        upsertActualWindow: @escaping UpsertActualWindow
    ) {
        self.persistSnapshot = persistSnapshot
        self.upsertActualWindow = upsertActualWindow
    }

    /// Calls `adapter.runUsageCommand()`, persists the snapshot, then derives
    /// and upserts the primary + (when reported) secondary ActualWindow rows.
    /// Returns the snapshot that was persisted.
    @discardableResult
    public func fetchAndPersist(
        adapter: any ProviderAdapter,
        now: Date = .now
    ) async throws -> UsageSnapshot {
        let snapshot = try await adapter.runUsageCommand()
        try await persistSnapshot(snapshot)

        for window in try derivedActualWindows(from: snapshot, now: now) {
            try await upsertActualWindow(window, Self.dedupTolerance)
        }
        return snapshot
    }

    /// Derives ActualWindow rows from a freshly-captured snapshot. Exposed for
    /// unit tests; callers should normally use `fetchAndPersist`.
    public func derivedActualWindows(
        from snapshot: UsageSnapshot,
        now: Date = .now
    ) throws -> [ActualWindow] {
        switch snapshot.providerID {
        case .claude:
            let status = try ClaudeUsageStatus.parsePayload(snapshot.rawJSON)
            var result = [status.actualWindow(providerID: .claude, createdAt: snapshot.capturedAt)]
            if let weekly = status.sevenDayActualWindow(providerID: .claude, createdAt: snapshot.capturedAt) {
                result.append(weekly)
            }
            return result.filter { $0.endAt > now }
        case .codex:
            let status = try CodexUsageStatus.parseAny(snapshot.rawJSON, capturedAt: snapshot.capturedAt)
            var result = [status.actualWindow(providerID: .codex, createdAt: snapshot.capturedAt)]
            if let weekly = status.secondaryActualWindow(providerID: .codex, createdAt: snapshot.capturedAt) {
                result.append(weekly)
            }
            return result.filter { $0.endAt > now }
        }
    }
}
