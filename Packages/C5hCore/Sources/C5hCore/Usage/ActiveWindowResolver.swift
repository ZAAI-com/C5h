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
///
/// The resolver's `snapshotFetch` deliberately bypasses `UsageCheckGate`
/// (including its pre-window quiet period): a prompt just ran, so the account
/// is active and this probe only anchors the window that run landed in.
public struct ActiveWindowResolver: Sendable {
    public typealias FetchSnapshot = @Sendable (ProviderID) async throws -> UsageSnapshot
    public typealias FetchActiveWindow = @Sendable (ProviderID, Date) async throws -> ActualWindow5h?
    public typealias AwaitActiveWindow = @Sendable (ProviderID, Date) async throws -> ActualWindow5h?
    public typealias FetchTriggerAttribution =
        @Sendable (UUID) async throws -> TriggerAttributionEvidence?
    /// Returns the provider's most recently persisted usage snapshot, or nil when
    /// none is on record. Used to anchor a trigger from the snapshot a concurrent
    /// probe just captured, when that probe itself persisted no window row.
    public typealias FetchLatestSnapshot = @Sendable (ProviderID) async throws -> UsageSnapshot?

    /// How far before the trigger a provider-reported window start may lie and
    /// still be credited to the trigger. Measured from the top of the UTC hour
    /// containing the trigger time because Claude anchors fresh windows to the
    /// hour: a wake prompt at 02:30 legitimately opens a window reported as
    /// starting 02:00. The tolerance absorbs scheduler tick latency, the
    /// post-trigger probe's runtime, and minute-level rounding of the
    /// provider's reported reset time.
    public static let triggerAnchorTolerance: TimeInterval = 10 * 60

    /// How recent a persisted snapshot must be to anchor a trigger from it. The
    /// concurrent probe that beat us to the lock runs for seconds and the waiter
    /// gives it a further half-minute, so anything older than this is a different
    /// poll whose reported boundary may already have moved on.
    public static let latestSnapshotAnchorHorizon: TimeInterval = 2 * 60

    public let fetcher: UsageFetcher
    public let snapshotFetch: FetchSnapshot
    public let activeWindowFetch: FetchActiveWindow
    public let updateActualWindow: @Sendable (ActualWindow5h) async throws -> Void
    public let awaitActiveWindow: AwaitActiveWindow
    public let triggerAttributionFetch: FetchTriggerAttribution
    public let latestSnapshotFetch: FetchLatestSnapshot

    /// Whether a window starting at `startAt` could have been opened by a
    /// trigger that ran at `now`. A start earlier than the hour floor of `now`
    /// minus `tolerance` means the window predates the trigger: it is the
    /// provider's boundary chained onto a previous window's end, not a window
    /// this trigger opened.
    public static func isPlausiblyTriggerAnchored(
        startAt: Date,
        now: Date,
        tolerance: TimeInterval = triggerAnchorTolerance
    ) -> Bool {
        let hourFloor = Date(
            timeIntervalSince1970: (now.timeIntervalSince1970 / 3600).rounded(.down) * 3600
        )
        return startAt >= hourFloor.addingTimeInterval(-tolerance)
    }

    public init(
        fetcher: UsageFetcher,
        snapshotFetch: @escaping FetchSnapshot,
        activeWindowFetch: @escaping FetchActiveWindow,
        updateActualWindow: @escaping @Sendable (ActualWindow5h) async throws -> Void,
        awaitActiveWindow: @escaping AwaitActiveWindow = { _, _ in nil },
        triggerAttributionFetch: @escaping FetchTriggerAttribution = { _ in nil },
        latestSnapshotFetch: @escaping FetchLatestSnapshot = { _ in nil }
    ) {
        self.fetcher = fetcher
        self.snapshotFetch = snapshotFetch
        self.activeWindowFetch = activeWindowFetch
        self.updateActualWindow = updateActualWindow
        self.awaitActiveWindow = awaitActiveWindow
        self.triggerAttributionFetch = triggerAttributionFetch
        self.latestSnapshotFetch = latestSnapshotFetch
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
                NSLog("ActiveWindowResolver: anchored real \(providerID.rawValue) window [\(promoted.startAt) … \(promoted.endAt)] for command \(commandRunID)")
                return promoted
            }
        } catch {
            if let c5hError = error as? C5hError,
               case .usageRefreshAlreadyRunning(let refreshingProviderID) = c5hError,
               refreshingProviderID == providerID {
                if providerID == .claude {
                    return await resolveAfterConcurrentClaudeRefresh(
                        providerID: providerID,
                        commandRunID: commandRunID,
                        now: now
                    )
                }
                return await resolveFromExistingWindow(
                    providerID: providerID,
                    commandRunID: commandRunID,
                    now: now
                )
            }
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

    /// A concurrent Claude usage probe owns the cross-process lock and will
    /// persist the authoritative provider window when it completes. Reuse an
    /// already-persisted row immediately when possible; otherwise wait for that
    /// probe's row rather than launching a second quota-consuming probe or
    /// fabricating a window. A final repository lookup closes races where the
    /// row lands just as the waiter times out, is cancelled, or fails.
    private func resolveAfterConcurrentClaudeRefresh(
        providerID: ProviderID,
        commandRunID: UUID,
        now: Date
    ) async -> ActualWindow5h? {
        do {
            if let reused = try await reuseActiveWindow(
                providerID: providerID,
                commandRunID: commandRunID,
                now: now
            ) {
                NSLog("ActiveWindowResolver: reused active \(providerID.rawValue) window [\(reused.startAt) … \(reused.endAt)] for command \(commandRunID) (usage refresh already running)")
                return reused
            }
        } catch {
            NSLog("ActiveWindowResolver: immediate reuse failed for \(providerID.rawValue) command \(commandRunID) while usage refresh was running: \(error)")
        }

        do {
            if let awaited = try await awaitActiveWindow(providerID, now),
               let reused = try await reuseActiveWindow(
                   awaited,
                   providerID: providerID,
                   commandRunID: commandRunID,
                   now: now
               ) {
                NSLog("ActiveWindowResolver: reused awaited \(providerID.rawValue) window [\(reused.startAt) … \(reused.endAt)] for command \(commandRunID) after concurrent usage refresh")
                return reused
            }
        } catch {
            NSLog("ActiveWindowResolver: waiting for concurrent \(providerID.rawValue) usage refresh failed for command \(commandRunID): \(error)")
        }

        // The concurrent poll may have captured a snapshot without persisting a
        // window row: on an idle account the provider reports a slot it has not
        // opened, which the routine poll path deliberately drops. The prompt we
        // just ran does open that window, so anchor it from the snapshot rather
        // than losing the record.
        if let anchored = await anchorFromLatestSnapshot(
            providerID: providerID,
            commandRunID: commandRunID,
            now: now
        ) {
            NSLog("ActiveWindowResolver: anchored \(providerID.rawValue) window [\(anchored.startAt) … \(anchored.endAt)] for command \(commandRunID) from the concurrent refresh's snapshot")
            return anchored
        }

        // Always check once more. The concurrent poll can commit between the
        // waiter's last check and its timeout/cancellation/error being observed.
        do {
            if let reused = try await reuseActiveWindow(
                providerID: providerID,
                commandRunID: commandRunID,
                now: now
            ) {
                NSLog("ActiveWindowResolver: reused active \(providerID.rawValue) window [\(reused.startAt) … \(reused.endAt)] for command \(commandRunID) after final concurrent-refresh lookup")
                return reused
            }
        } catch {
            NSLog("ActiveWindowResolver: final reuse failed for \(providerID.rawValue) command \(commandRunID) after concurrent usage refresh: \(error)")
        }

        NSLog("ActiveWindowResolver: no real \(providerID.rawValue) window to anchor command \(commandRunID) after concurrent usage refresh; leaving the CommandRun as the only record")
        return nil
    }

    private func resolveFromExistingWindow(
        providerID: ProviderID,
        commandRunID: UUID,
        now: Date
    ) async -> ActualWindow5h? {
        do {
            if let reused = try await reuseActiveWindow(
                providerID: providerID,
                commandRunID: commandRunID,
                now: now
            ) {
                NSLog("ActiveWindowResolver: reused active \(providerID.rawValue) window [\(reused.startAt) … \(reused.endAt)] for command \(commandRunID) (usage refresh already running)")
                return reused
            }
        } catch {
            NSLog("ActiveWindowResolver: reuse failed for \(providerID.rawValue) command \(commandRunID): \(error)")
        }
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
        // Claude can anchor a wake prompt before usage registers. Codex cannot:
        // its idle response is a synthetic sliding slot, so keep Codex active-
        // gated here even though UsageFetcher supports an explicit force-anchor.
        let derived5h = try fetcher.derived5h(
            from: snapshot,
            now: now,
            requireActiveWindow: providerID == .codex
        )
        if let window = derived5h {
            try await fetcher.upsertActualWindow5h(window, UsageFetcher.dedupTolerance)
        }
        if let window = try fetcher.derived7d(from: snapshot) {
            try await fetcher.upsertActualWindow7d(window, UsageFetcher.dedupTolerance)
        }
        // No active 5h window in this snapshot: report nil rather than promoting
        // a stale row from a previous poll, so the caller falls back to reuse.
        guard let derived5h else { return nil }
        let usedPercentage = Self.usedPercentage5h(from: snapshot) ?? 0
        if usedPercentage <= 0,
           !Self.isPlausiblyTriggerAnchored(startAt: derived5h.startAt, now: now) {
            // The reported window started well before the trigger with zero
            // recorded usage: that is the provider's idle rolling boundary
            // chained onto the previous window's end, not a window this wake
            // prompt opened. Stamping it `c5hTriggered`/`exact` would show a
            // block C5h never started (the "planned 05:00, calendar shows
            // 03:10" confusion). The upsert above may have merged into a
            // previously stamped `c5hTriggered` row, so validate that row's
            // linked command against the corrected bounds. Preserve a genuine
            // earlier trigger, but force a provably stale fallback stamp back
            // to `detectedFromUsage`/`estimated`. Link the run for traceability
            // and return non-nil so the caller does NOT fall through to
            // `reuseActiveWindow`.
            NSLog("ActiveWindowResolver: \(providerID.rawValue) window [\(derived5h.startAt) … \(derived5h.endAt)] predates command \(commandRunID) with zero recorded usage; keeping it detectedFromUsage instead of promoting")
            guard var active = try await activeWindowFetch(providerID, now) else {
                return derived5h
            }
            // `activeWindowFetch` selects by coverage of `now`, so an overlapping
            // window with a different reset time can come back instead of the row
            // just upserted. Only demote the row whose bounds match this derived
            // window; leave an unrelated `c5hTriggered` window untouched.
            guard abs(active.startAt.timeIntervalSince(derived5h.startAt))
                <= UsageFetcher.dedupTolerance,
                  abs(active.endAt.timeIntervalSince(derived5h.endAt))
                <= UsageFetcher.dedupTolerance else {
                return derived5h
            }
            if active.source == .c5hTriggered {
                if active.commandRunID == nil {
                    // There is no earlier command attribution to validate or
                    // preserve. Keep the existing trigger classification and
                    // attach the current prompt as its first command link.
                    active.commandRunID = commandRunID
                    active.updatedAt = now
                    try await updateActualWindow(active)
                    return active
                }
                switch await existingTriggerAttribution(for: active) {
                case .confirmed:
                    // A previous prompt plausibly opened this provider window.
                    // The current prompt merely joined it, so retain the first
                    // trigger's source, confidence, and command link.
                    return active
                case .unknown:
                    // Missing or unreadable evidence cannot prove that the
                    // existing attribution is stale. Prefer preserving user
                    // history over a destructive, speculative demotion.
                    return active
                case .stale:
                    break
                }
            }
            var needsWrite = false
            if active.source != .detectedFromUsage || active.confidence != .estimated {
                active.source = .detectedFromUsage
                active.confidence = .estimated
                needsWrite = true
            }
            if active.commandRunID == nil {
                active.commandRunID = commandRunID
                needsWrite = true
            }
            if needsWrite {
                active.updatedAt = now
                try await updateActualWindow(active)
            }
            return active
        }
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

    private enum ExistingTriggerAttribution {
        case confirmed
        case stale
        case unknown
    }

    /// Validates an existing trigger stamp against the command that originally
    /// supplied its link, using the provider-corrected window bounds. Legacy
    /// fallback placeholders become stale when a later usage upsert moves the
    /// window start well before their linked command; a genuine earlier trigger
    /// remains plausible even when a second prompt arrives later in the window.
    private func existingTriggerAttribution(
        for window: ActualWindow5h
    ) async -> ExistingTriggerAttribution {
        guard let commandRunID = window.commandRunID else { return .unknown }
        do {
            guard let evidence = try await triggerAttributionFetch(commandRunID) else {
                return .unknown
            }
            guard evidence.providerID == window.providerID, evidence.isPrompt else {
                return .stale
            }
            let startIsNotTooFarAfterCommand = window.startAt
                <= evidence.startedAt.addingTimeInterval(Self.triggerAnchorTolerance)
            let commandPrecedesWindowEnd = evidence.startedAt < window.endAt
            guard startIsNotTooFarAfterCommand,
                  commandPrecedesWindowEnd,
                  Self.isPlausiblyTriggerAnchored(
                      startAt: window.startAt,
                      now: evidence.startedAt
                  ) else {
                return .stale
            }
            return .confirmed
        } catch {
            NSLog("ActiveWindowResolver: could not validate trigger attribution for command \(commandRunID): \(error)")
            return .unknown
        }
    }

    /// Reported 5h used percentage from the raw snapshot payload, used to tell
    /// an idle rolling boundary (0%) from a window with real consumption.
    private static func usedPercentage5h(from snapshot: UsageSnapshot) -> Double? {
        switch snapshot.providerID {
        case .claude:
            (try? ClaudeUsageStatus.parsePayload(snapshot.rawJSON))?
                .fiveHour.usedPercentage
        case .codex:
            (try? CodexUsageStatus.parseAny(snapshot.rawJSON, capturedAt: snapshot.capturedAt))?
                .fiveHourUsedPercentage
        }
    }

    /// Anchors the trigger from the provider's most recently persisted snapshot,
    /// for the case where a concurrent probe owned the lock, captured that
    /// snapshot, and persisted no window row because the provider was reporting a
    /// slot it had not opened yet. The trigger itself opens that window, so it is
    /// derived with `requireActiveWindow: false` (the same force-anchor the
    /// non-contended path uses), upserted, and then promoted through the normal
    /// reuse rules so attribution stays consistent.
    ///
    /// Returns nil when there is no snapshot, when it is too old to still
    /// describe the current boundary, when it yields no window, or when the
    /// upserted row does not cover `now`.
    private func anchorFromLatestSnapshot(
        providerID: ProviderID,
        commandRunID: UUID,
        now: Date
    ) async -> ActualWindow5h? {
        do {
            guard let snapshot = try await latestSnapshotFetch(providerID),
                  snapshot.providerID == providerID,
                  snapshot.capturedAt <= now,
                  now.timeIntervalSince(snapshot.capturedAt) <= Self.latestSnapshotAnchorHorizon else {
                return nil
            }
            guard let derived = try fetcher.derived5h(
                from: snapshot,
                now: now,
                requireActiveWindow: false
            ) else {
                return nil
            }
            try await fetcher.upsertActualWindow5h(derived, UsageFetcher.dedupTolerance)
            return try await reuseActiveWindow(
                providerID: providerID,
                commandRunID: commandRunID,
                now: now
            )
        } catch {
            NSLog("ActiveWindowResolver: anchoring \(providerID.rawValue) command \(commandRunID) from the latest snapshot failed: \(error)")
            return nil
        }
    }

    /// When a fresh snapshot cannot supply a real window (the usage CLI failed,
    /// or reported no active window), attach the trigger to an existing active
    /// window (persisted by an earlier poll) that already covers `now`, rather
    /// than fabricating a fresh `[now, +5h]` estimate. The triggered run happened
    /// inside that window, so promoting it to `c5hTriggered` keeps the calendar to
    /// one accurate row and avoids a phantom whose bounds are offset from the real
    /// window's (and therefore never merge). Promotion only applies when the
    /// window's start is plausibly trigger-anchored: a window that started well
    /// before the trigger (typically the provider's chained idle boundary) was
    /// not opened by C5h, so it keeps its source and only gains the run link.
    /// This matters because the post-trigger snapshot commonly fails with
    /// `usageRefreshAlreadyRunning` (the UI's usage polls share the probe
    /// lock), and an unconditional stamp here would re-introduce the false
    /// "C5h started a block at 03:10" record. Confidence is left untouched:
    /// with no fresh snapshot we cannot upgrade it to `exact`. Returns `nil`
    /// when no active window covers `now`, so the caller records nothing for
    /// this trigger.
    private func reuseActiveWindow(
        providerID: ProviderID,
        commandRunID: UUID,
        now: Date
    ) async throws -> ActualWindow5h? {
        guard let active = try await activeWindowFetch(providerID, now) else {
            return nil
        }
        return try await reuseActiveWindow(
            active,
            providerID: providerID,
            commandRunID: commandRunID,
            now: now
        )
    }

    /// Applies the same attribution and command-linking rules to a window
    /// returned directly by the concurrent-refresh waiter. Validate provider
    /// and coverage defensively so a polling implementation cannot accidentally
    /// hand a trigger a different provider's row or a stale boundary.
    private func reuseActiveWindow(
        _ candidate: ActualWindow5h,
        providerID: ProviderID,
        commandRunID: UUID,
        now: Date
    ) async throws -> ActualWindow5h? {
        guard candidate.providerID == providerID,
              candidate.startAt <= now,
              now < candidate.endAt else {
            return nil
        }
        var active = candidate
        if Self.isPlausiblyTriggerAnchored(startAt: active.startAt, now: now) {
            active.source = .c5hTriggered
            active.commandRunID = commandRunID
            active.updatedAt = now
            try await updateActualWindow(active)
        } else if active.commandRunID == nil {
            active.commandRunID = commandRunID
            active.updatedAt = now
            try await updateActualWindow(active)
        }
        return active
    }
}
