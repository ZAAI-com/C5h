import Foundation

/// Resolves the provider's *real* current rolling 5h window at trigger time by
/// fetching usage from the upstream CLI, persists the derived snapshot, and
/// promotes the resulting `ActualWindow5h` row to `c5hTriggered` / `exact`,
/// stamping `commandRunID` so the calendar shows a single, accurate row.
///
/// Returns `nil` when the provider isn't authenticated, the CLI call fails, or
/// no active window is reported — in which case the caller writes no
/// `ActualWindow5h`. This avoids the legacy behavior of persisting a fictitious
/// `[now, +5h]` block that doesn't match the upstream `resetsAt`.
public struct ActiveWindowResolver: Sendable {
    public typealias FetchSnapshot = @Sendable (ProviderID) async throws -> UsageSnapshot
    public typealias FetchActiveWindow = @Sendable (ProviderID, Date) async throws -> ActualWindow5h?

    public let fetcher: UsageFetcher
    public let snapshotFetch: FetchSnapshot
    public let activeWindowFetch: FetchActiveWindow
    public let updateActualWindow: @Sendable (ActualWindow5h) async throws -> Void

    public init(
        fetcher: UsageFetcher,
        snapshotFetch: @escaping FetchSnapshot,
        activeWindowFetch: @escaping FetchActiveWindow,
        updateActualWindow: @escaping @Sendable (ActualWindow5h) async throws -> Void
    ) {
        self.fetcher = fetcher
        self.snapshotFetch = snapshotFetch
        self.activeWindowFetch = activeWindowFetch
        self.updateActualWindow = updateActualWindow
    }

    /// Fetches the provider's current rolling window, persists the snapshot and
    /// derived windows, then promotes the active row to `c5hTriggered`/`exact`
    /// linked to `commandRunID`. Returns the promoted window, or `nil` if no
    /// active window could be resolved.
    public func resolveTriggeredWindow(
        providerID: ProviderID,
        commandRunID: UUID,
        now: Date = .now
    ) async -> ActualWindow5h? {
        let snapshot: UsageSnapshot
        do {
            snapshot = try await snapshotFetch(providerID)
        } catch {
            return nil
        }

        do {
            try await fetcher.persistSnapshot(snapshot)
            let derived5h = try fetcher.derived5h(from: snapshot, now: now)
            if let window = derived5h {
                try await fetcher.upsertActualWindow5h(window, UsageFetcher.dedupTolerance)
            }
            if let window = try fetcher.derived7d(from: snapshot) {
                try await fetcher.upsertActualWindow7d(window, UsageFetcher.dedupTolerance)
            }
            // Don't promote a stale active row from a previous poll when this
            // snapshot has no 5h window — that would re-introduce the fictitious
            // window behavior the resolver is meant to avoid.
            guard derived5h != nil else { return nil }
            guard var active = try await activeWindowFetch(providerID, now) else {
                return nil
            }
            active.source = .c5hTriggered
            active.confidence = .exact
            active.commandRunID = commandRunID
            active.updatedAt = now
            try await updateActualWindow(active)
            return active
        } catch {
            return nil
        }
    }
}
