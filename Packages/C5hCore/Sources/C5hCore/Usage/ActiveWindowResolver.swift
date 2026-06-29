import Foundation

/// Anchors the trigger's rolling 5h window to a *real* provider window, never a
/// fabricated one. It prefers the provider's current window fetched fresh from
/// the upstream CLI, persisted, and promoted to `c5hTriggered` / `exact` with
/// `commandRunID` so the calendar shows a single, accurate row. When a fresh
/// snapshot cannot supply a window (unauthenticated, CLI failure, or a synthetic
/// Codex "fresh slot"), it attaches the run to an existing real window that
/// already covers the trigger time. When no real window exists at all, it
/// records nothing and returns `nil`: the run is already captured as a
/// `CommandRun`, and a later usage poll persists the real window once the
/// provider reports it. The resolver never pins a synthetic `[trigger, +5h]`
/// block, so it cannot create a phantom window that overlaps the real one.
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

    /// Anchors the trigger's 5h window to a real provider window, or records
    /// nothing. First tries to anchor the provider's true rolling window from a
    /// fresh upstream snapshot and promote it to `c5hTriggered`/`exact`. When the
    /// snapshot is unavailable or reports no active window (a thrown usage CLI, a
    /// synthetic Codex slot, an unauthenticated provider), attaches the run to an
    /// existing real window that already covers `now`. When neither yields a real
    /// window, returns `nil` and writes nothing: the run is already captured as a
    /// `CommandRun`, and a later usage poll persists the real window once the
    /// provider reports it. The resolver never pins a synthetic `[now, +5h]`
    /// block, so a trigger can no longer create a phantom window that overlaps
    /// the real one.
    public func resolveTriggeredWindow(
        providerID: ProviderID,
        commandRunID: UUID,
        now: Date = .now
    ) async -> ActualWindow5h? {
        // 1. Prefer the provider's real current window from a fresh usage
        //    snapshot, promoted to `c5hTriggered`/`exact`. A thrown error here
        //    (usage CLI failure, decode error, DB write failure) is logged and
        //    falls through to reuse, so a hard failure stays distinguishable from
        //    a genuine no-active-window result (`promoteFromSnapshot` -> nil,
        //    which stays quiet and also falls through).
        do {
            let snapshot = try await snapshotFetch(providerID)
            if let promoted = try await promoteFromSnapshot(
                snapshot,
                providerID: providerID,
                commandRunID: commandRunID,
                now: now
            ) {
                NSLog("ActiveWindowResolver: promoted real \(providerID.rawValue) window [\(promoted.startAt) … \(promoted.endAt)] for command \(commandRunID)")
                return promoted
            }
        } catch {
            NSLog("ActiveWindowResolver: snapshot/promote failed for \(providerID.rawValue) command \(commandRunID): \(error)")
        }

        // 2. No usable fresh window (the snapshot threw, or reported no active 5h
        //    window). Attach the trigger to an existing real window that already
        //    covers `now` instead of fabricating one. The run happened inside
        //    that window, so a pinned `[now, +5h]` estimate would only ever
        //    linger as an overlapping duplicate (its end is offset from the real
        //    window's, beyond the dedup tolerance). A thrown error here is logged
        //    and falls through to recording nothing.
        do {
            if let reused = try await reuseActiveWindow(
                providerID: providerID,
                commandRunID: commandRunID,
                now: now
            ) {
                NSLog("ActiveWindowResolver: reused active \(providerID.rawValue) window [\(reused.startAt) … \(reused.endAt)] for command \(commandRunID) (no fresh window from usage)")
                return reused
            }
        } catch {
            NSLog("ActiveWindowResolver: reuse failed for \(providerID.rawValue) command \(commandRunID): \(error)")
        }

        // 3. No real 5h window exists to anchor to. Record nothing: the
        //    CommandRun already captures that the trigger ran, and a later
        //    detected-from-usage poll persists the real window once the provider
        //    reports it. Fabricating a `[now, +5h]` block here would draw a fake
        //    window with the wrong bounds.
        NSLog("ActiveWindowResolver: no real \(providerID.rawValue) window to anchor command \(commandRunID); leaving the CommandRun as the only record")
        return nil
    }

    /// Persists the snapshot and derived windows, then promotes the active row
    /// to `c5hTriggered`/`exact` linked to `commandRunID`. Returns the promoted
    /// (or already-upserted) real window, or `nil` when the snapshot reports no
    /// active 5h window (so the caller falls back to reusing an existing real
    /// window instead).
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
        // No active 5h window in this snapshot: report nil rather than promoting
        // a stale row from a previous poll, so the caller falls back to reuse.
        guard let derived5h else { return nil }
        guard var active = try await activeWindowFetch(providerID, now) else {
            // The real window was already upserted; report it so the caller does
            // not also write a duplicate row.
            return derived5h
        }
        active.source = .c5hTriggered
        active.confidence = .exact
        active.commandRunID = commandRunID
        active.updatedAt = now
        try await updateActualWindow(active)
        return active
    }

    /// When a fresh snapshot cannot supply a real window (the usage CLI failed,
    /// or reported no active window), attach the trigger to an existing active
    /// window (persisted by an earlier poll) that already covers `now`, rather
    /// than fabricating a fresh `[now, +5h]` estimate. The triggered run happened
    /// inside that window, so promoting it to `c5hTriggered` keeps the calendar to
    /// one accurate row and avoids a phantom whose bounds are offset from the real
    /// window's (and therefore never merge). Confidence is left untouched: with no
    /// fresh snapshot we cannot upgrade it to `exact`. Returns `nil` when no active
    /// window covers `now`, so the caller records nothing for this trigger.
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
