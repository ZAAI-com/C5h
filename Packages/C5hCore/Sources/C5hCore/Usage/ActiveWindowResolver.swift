import Foundation

/// Anchors the trigger's rolling 5h window. It prefers the provider's *real*
/// current window (fetched from the upstream CLI, persisted, and promoted to
/// `c5hTriggered` / `exact` with `commandRunID` so the calendar shows a single,
/// accurate row). When upstream usage cannot supply a window (unauthenticated,
/// CLI failure, or a synthetic Codex "fresh slot"), it anchors an `estimated`
/// `[trigger, +5h]` window pinned to the trigger time so a real trigger always
/// leaves a row. Because that fallback is written once per trigger and never
/// slides, it does not reintroduce the per-poll phantom window the passive
/// usage path guards against.
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

    /// Anchors the trigger's 5h window. A real command just executed, so a usage
    /// window genuinely started at `now`. First tries to anchor the provider's
    /// true rolling window from upstream usage and promote it to
    /// `c5hTriggered`/`exact`. When upstream usage is unavailable (a synthetic
    /// Codex slot, an unauthenticated provider, or an app-server failure), falls
    /// back to an `estimated` window pinned to `now` so the calendar always
    /// reflects that something ran. Returns the anchored window, or `nil` only
    /// when even the fallback write fails.
    public func resolveTriggeredWindow(
        providerID: ProviderID,
        commandRunID: UUID,
        now: Date = .now
    ) async -> ActualWindow5h? {
        // Prefer the provider's real current window from a fresh usage snapshot.
        if let snapshot = try? await snapshotFetch(providerID) {
            if let promoted = try? await promoteFromSnapshot(
                snapshot,
                providerID: providerID,
                commandRunID: commandRunID,
                now: now
            ) {
                NSLog("ActiveWindowResolver: promoted real \(providerID.rawValue) window [\(promoted.startAt) … \(promoted.endAt)] for command \(commandRunID)")
                return promoted
            }
            // The fresh snapshot reported no active 5h window, so there is
            // genuinely none to anchor to: fall through to the pinned fallback.
        } else if let reused = try? await reuseActiveWindow(
            providerID: providerID,
            commandRunID: commandRunID,
            now: now
        ) {
            // Usage was unavailable (e.g. the usage CLI timed out). Attach the
            // trigger to the existing active window that already covers `now`
            // instead of pinning a `[now, +5h]` estimate. The run happened
            // inside that window, so an offset estimate would never merge (its
            // end is shifted by however far into the window the trigger landed,
            // beyond the dedup tolerance) and would linger as a duplicate row.
            NSLog("ActiveWindowResolver: reused active \(providerID.rawValue) window [\(reused.startAt) … \(reused.endAt)] for command \(commandRunID) (usage unavailable)")
            return reused
        }

        // No real 5h window could be derived or reused. Anchor an estimated
        // window pinned to the trigger time. It is written once per trigger and
        // does not slide, so it does not reintroduce the phantom-window behavior
        // the passive polling path guards against; a later detected-from-usage
        // poll merges/upgrades it to the real bounds via the upsert dedup
        // tolerance.
        let fallback = ActualWindow5h(
            providerID: providerID,
            startAt: now,
            source: .c5hTriggered,
            confidence: .estimated,
            commandRunID: commandRunID,
            createdAt: now,
            updatedAt: now
        )
        do {
            try await fetcher.upsertActualWindow5h(fallback, UsageFetcher.dedupTolerance)
            NSLog("ActiveWindowResolver: pinned estimated \(providerID.rawValue) fallback window [\(fallback.startAt) … \(fallback.endAt)] for command \(commandRunID) (no real window from usage)")
            return fallback
        } catch {
            NSLog("ActiveWindowResolver: FAILED to pin \(providerID.rawValue) fallback window for command \(commandRunID): \(error)")
            return nil
        }
    }

    /// Persists the snapshot and derived windows, then promotes the active row
    /// to `c5hTriggered`/`exact` linked to `commandRunID`. Returns the promoted
    /// (or already-upserted) real window, or `nil` when the snapshot reports no
    /// active 5h window (so the caller writes a pinned fallback instead).
    private func promoteFromSnapshot(
        _ snapshot: UsageSnapshot,
        providerID: ProviderID,
        commandRunID: UUID,
        now: Date
    ) async throws -> ActualWindow5h? {
        try await fetcher.persistSnapshot(snapshot)
        let derived5h = try fetcher.derived5h(from: snapshot, now: now)
        if let window = derived5h {
            try await fetcher.upsertActualWindow5h(window, UsageFetcher.dedupTolerance)
        }
        if let window = try fetcher.derived7d(from: snapshot) {
            try await fetcher.upsertActualWindow7d(window, UsageFetcher.dedupTolerance)
        }
        // No active 5h window in this snapshot: let the caller pin a fallback
        // rather than promoting a stale row from a previous poll.
        guard let derived5h else { return nil }
        guard var active = try await activeWindowFetch(providerID, now) else {
            // The real window was already upserted; report it so the caller does
            // not also write a duplicate fallback row.
            return derived5h
        }
        active.source = .c5hTriggered
        active.confidence = .exact
        active.commandRunID = commandRunID
        active.updatedAt = now
        try await updateActualWindow(active)
        return active
    }

    /// When upstream usage is unavailable, attach the trigger to an existing
    /// active window (persisted by an earlier poll) that already covers `now`,
    /// rather than pinning a fresh `[now, +5h]` estimate. The triggered run
    /// happened inside that window, so promoting it to `c5hTriggered` keeps the
    /// calendar to one accurate row and avoids a phantom whose bounds are offset
    /// from the real window's (and therefore never merge). Confidence is left
    /// untouched: with no fresh snapshot we cannot upgrade it to `exact`. Returns
    /// `nil` when no active window covers `now`, so the caller pins the estimated
    /// fallback instead.
    private func reuseActiveWindow(
        providerID: ProviderID,
        commandRunID: UUID,
        now: Date
    ) async throws -> ActualWindow5h? {
        guard var active = try await activeWindowFetch(providerID, now) else {
            return nil
        }
        active.source = .c5hTriggered
        active.commandRunID = commandRunID
        active.updatedAt = now
        try await updateActualWindow(active)
        return active
    }
}
