import Foundation
import Testing
@testable import C5hCore

@Suite("ActiveWindowResolver")
struct ActiveWindowResolverTests {
    /// Captures what the resolver writes so assertions can inspect upserts and
    /// promotions without a database.
    actor Recorder {
        var upserted5h: [ActualWindow5h] = []
        var updated: [ActualWindow5h] = []
        func addUpsert(_ window: ActualWindow5h) { upserted5h.append(window) }
        func addUpdate(_ window: ActualWindow5h) { updated.append(window) }
    }

    private func makeFetcher(recorder: Recorder) -> UsageFetcher {
        UsageFetcher(
            persistSnapshot: { _ in },
            upsertActualWindow5h: { window, _ in await recorder.addUpsert(window) },
            upsertActualWindow7d: { _, _ in }
        )
    }

    @Test("Writes nothing when the snapshot fails and no active window can be reused")
    func writesNothingWhenNoRealWindowAndNoneToReuse() async throws {
        let recorder = Recorder()
        let triggerTime = Date(timeIntervalSince1970: 1_000_000)
        let commandRunID = UUID()
        let resolver = ActiveWindowResolver(
            fetcher: makeFetcher(recorder: recorder),
            snapshotFetch: { _ in throw C5hError.processLaunchFailed("app-server down") },
            activeWindowFetch: { _, _ in nil },
            updateActualWindow: { window in await recorder.addUpdate(window) }
        )

        let result = await resolver.resolveTriggeredWindow(
            providerID: .codex,
            commandRunID: commandRunID,
            now: triggerTime
        )

        // No fresh window and nothing to reuse: the resolver records nothing
        // rather than pinning a phantom `[now, +5h]` block.
        #expect(result == nil)
        let upserts = await recorder.upserted5h
        #expect(upserts.isEmpty)
        let updates = await recorder.updated
        #expect(updates.isEmpty)
    }

    @Test("Writes nothing for a Codex synthetic slot when no active window can be reused")
    func writesNothingForCodexSyntheticSlotWithNoActiveWindow() async throws {
        let recorder = Recorder()
        // `codex app-server` returns resetsAt = capturedAt + 5h before any real
        // window anchors, so derived5h is nil and there is no real window to
        // anchor or reuse.
        let triggerTime = Date(timeIntervalSince1970: 1_779_408_036)
        let syntheticResetsAt = Int(triggerTime.addingTimeInterval(18_000).timeIntervalSince1970)
        let commandRunID = UUID()
        let snapshot = UsageSnapshot(
            providerID: .codex,
            capturedAt: triggerTime,
            rawJSON: """
            {"rateLimits":{"primary":{"usedPercent":1,"windowDurationMins":300,"resetsAt":\(syntheticResetsAt)},"secondary":{"usedPercent":30,"windowDurationMins":10080,"resetsAt":1779838110},"planType":"plus"}}
            """,
            normalizedJSON: "{}"
        )
        let resolver = ActiveWindowResolver(
            fetcher: makeFetcher(recorder: recorder),
            snapshotFetch: { _ in snapshot },
            activeWindowFetch: { _, _ in nil },
            updateActualWindow: { window in await recorder.addUpdate(window) }
        )

        let result = await resolver.resolveTriggeredWindow(
            providerID: .codex,
            commandRunID: commandRunID,
            now: triggerTime
        )

        #expect(result == nil)
        let updates = await recorder.updated
        #expect(updates.isEmpty)
    }

    @Test("Reuses the active window when the snapshot reports no usable window")
    func reusesActiveWindowWhenSnapshotReportsNoWindow() async throws {
        let recorder = Recorder()
        // The fresh snapshot succeeds but carries only a synthetic Codex slot
        // (derived5h is nil), yet a real window detected earlier already covers
        // the trigger. The run must attach to that real window, not spawn a
        // phantom `[now, +5h]` block beside it. (Regression: the overlapping
        // duplicate windows bug.) The window started 50 minutes before the
        // trigger, well before its hour floor, so C5h did not open it: the
        // source stays detectedFromUsage and only the run link is written.
        let triggerTime = Date(timeIntervalSince1970: 1_779_408_036)
        let syntheticResetsAt = Int(triggerTime.addingTimeInterval(18_000).timeIntervalSince1970)
        let commandRunID = UUID()
        let snapshot = UsageSnapshot(
            providerID: .codex,
            capturedAt: triggerTime,
            rawJSON: """
            {"rateLimits":{"primary":{"usedPercent":1,"windowDurationMins":300,"resetsAt":\(syntheticResetsAt)},"secondary":{"usedPercent":30,"windowDurationMins":10080,"resetsAt":1779838110},"planType":"plus"}}
            """,
            normalizedJSON: "{}"
        )
        let existing = ActualWindow5h(
            providerID: .codex,
            startAt: triggerTime.addingTimeInterval(-3000),
            source: .detectedFromUsage,
            confidence: .estimated
        )
        let resolver = ActiveWindowResolver(
            fetcher: makeFetcher(recorder: recorder),
            snapshotFetch: { _ in snapshot },
            activeWindowFetch: { _, _ in existing },
            updateActualWindow: { window in await recorder.addUpdate(window) }
        )

        let result = await resolver.resolveTriggeredWindow(
            providerID: .codex,
            commandRunID: commandRunID,
            now: triggerTime
        )

        let window = try #require(result)
        #expect(window.id == existing.id)
        #expect(window.source == .detectedFromUsage)
        #expect(window.commandRunID == commandRunID)
        #expect(window.startAt == existing.startAt)

        let updates = await recorder.updated
        #expect(updates.count == 1)
        let upserts = await recorder.upserted5h
        #expect(upserts.isEmpty)
    }

    @Test("Reuses the active window covering now when the usage fetch fails")
    func reusesActiveWindowWhenSnapshotFails() async throws {
        let recorder = Recorder()
        let triggerTime = Date(timeIntervalSince1970: 1_000_000)
        let commandRunID = UUID()
        // An earlier detected poll left a window that still covers the trigger;
        // the run lands mid-window, so there is no new window to anchor.
        let existing = ActualWindow5h(
            providerID: .claude,
            startAt: triggerTime.addingTimeInterval(-3000),
            source: .detectedFromUsage,
            confidence: .estimated
        )
        let resolver = ActiveWindowResolver(
            fetcher: makeFetcher(recorder: recorder),
            snapshotFetch: { _ in throw C5hError.processLaunchFailed("usage CLI timed out") },
            activeWindowFetch: { _, _ in existing },
            updateActualWindow: { window in await recorder.addUpdate(window) }
        )

        let result = await resolver.resolveTriggeredWindow(
            providerID: .claude,
            commandRunID: commandRunID,
            now: triggerTime
        )

        let window = try #require(result)
        // The existing window is reused (same id), not a new pinned placeholder.
        #expect(window.id == existing.id)
        #expect(window.source == .c5hTriggered)
        #expect(window.commandRunID == commandRunID)
        // Confidence is left untouched: no fresh snapshot to confirm exact bounds.
        #expect(window.confidence == .estimated)
        #expect(window.startAt == existing.startAt)

        let updates = await recorder.updated
        #expect(updates.count == 1)
        let upserts = await recorder.upserted5h
        #expect(upserts.isEmpty)
    }

    @Test("Promotes the real active window to exact when Codex reports an anchored window")
    func promotesRealWindowToExact() async throws {
        let recorder = Recorder()
        let capturedAt = Date(timeIntervalSince1970: 1_779_438_857)
        let anchoredResetsAt = 1_779_455_535 // ~16678s ahead, so the window has aged into a real one
        let commandRunID = UUID()
        let snapshot = UsageSnapshot(
            providerID: .codex,
            capturedAt: capturedAt,
            rawJSON: """
            {"rateLimits":{"primary":{"usedPercent":1,"windowDurationMins":300,"resetsAt":\(anchoredResetsAt)},"secondary":{"usedPercent":30,"windowDurationMins":10080,"resetsAt":1779838110},"planType":"plus"}}
            """,
            normalizedJSON: "{}"
        )
        let existing = ActualWindow5h(
            providerID: .codex,
            startAt: capturedAt.addingTimeInterval(-3600),
            source: .detectedFromUsage,
            confidence: .estimated
        )
        let resolver = ActiveWindowResolver(
            fetcher: makeFetcher(recorder: recorder),
            snapshotFetch: { _ in snapshot },
            activeWindowFetch: { _, _ in existing },
            updateActualWindow: { window in await recorder.addUpdate(window) }
        )

        let result = await resolver.resolveTriggeredWindow(
            providerID: .codex,
            commandRunID: commandRunID,
            now: capturedAt
        )

        let window = try #require(result)
        #expect(window.source == .c5hTriggered)
        #expect(window.confidence == .exact)
        #expect(window.commandRunID == commandRunID)
        #expect(window.id == existing.id)

        let updates = await recorder.updated
        #expect(updates.count == 1)
    }

    // MARK: Chained-boundary attribution

    /// An epoch exactly on a UTC hour, so hour-floor math in the tests is exact.
    private static let hourStart = Date(timeIntervalSince1970: 1_783_404_000)

    private func makeClaudeSnapshot(
        capturedAt: Date,
        windowStartAt: Date,
        usedPercentage: Double
    ) -> UsageSnapshot {
        let resetsAt = Int(windowStartAt.addingTimeInterval(18_000).timeIntervalSince1970)
        return UsageSnapshot(
            providerID: .claude,
            capturedAt: capturedAt,
            rawJSON: """
            {"rate_limits":{"five_hour":{"used_percentage":\(usedPercentage),"resets_at":\(resetsAt)}}}
            """,
            normalizedJSON: "{}"
        )
    }

    @Test("Demotes a chained Claude boundary with zero usage instead of promoting it")
    func demotesChainedClaudeBoundaryWithZeroUsage() async throws {
        let recorder = Recorder()
        // Trigger at half past; the reported window started 80 minutes earlier
        // (50 minutes before the hour floor): the provider's idle boundary
        // chained onto the previous window's end, which this trigger cannot
        // have opened. (The incident: prompt 02:30Z, boundary 01:10Z, 0% used.)
        let triggerTime = Self.hourStart.addingTimeInterval(1800)
        let chainedStart = triggerTime.addingTimeInterval(-80 * 60)
        let commandRunID = UUID()
        let snapshot = makeClaudeSnapshot(
            capturedAt: triggerTime,
            windowStartAt: chainedStart,
            usedPercentage: 0
        )
        let existing = ActualWindow5h(
            providerID: .claude,
            startAt: chainedStart,
            source: .detectedFromUsage,
            confidence: .estimated
        )
        let resolver = ActiveWindowResolver(
            fetcher: makeFetcher(recorder: recorder),
            snapshotFetch: { _ in snapshot },
            activeWindowFetch: { _, _ in existing },
            updateActualWindow: { window in await recorder.addUpdate(window) }
        )

        let result = await resolver.resolveTriggeredWindow(
            providerID: .claude,
            commandRunID: commandRunID,
            now: triggerTime
        )

        let window = try #require(result)
        #expect(window.id == existing.id)
        #expect(window.source == .detectedFromUsage)
        #expect(window.confidence == .estimated)
        // The run is still linked for traceability.
        #expect(window.commandRunID == commandRunID)

        // Guard the fall-through trap: nothing may re-stamp the chained window
        // as c5hTriggered (a nil return would reach reuseActiveWindow, which
        // does exactly that).
        let updates = await recorder.updated
        #expect(updates.allSatisfy { $0.source != .c5hTriggered })
        #expect(updates.count == 1)
    }

    @Test("Demote path does not overwrite an existing command run link")
    func demotePathKeepsExistingCommandRunLink() async throws {
        let recorder = Recorder()
        let triggerTime = Self.hourStart.addingTimeInterval(1800)
        let chainedStart = triggerTime.addingTimeInterval(-80 * 60)
        let earlierRunID = UUID()
        var existing = ActualWindow5h(
            providerID: .claude,
            startAt: chainedStart,
            source: .detectedFromUsage,
            confidence: .estimated
        )
        existing.commandRunID = earlierRunID
        let snapshot = makeClaudeSnapshot(
            capturedAt: triggerTime,
            windowStartAt: chainedStart,
            usedPercentage: 0
        )
        let resolver = ActiveWindowResolver(
            fetcher: makeFetcher(recorder: recorder),
            snapshotFetch: { _ in snapshot },
            activeWindowFetch: { [existing] _, _ in existing },
            updateActualWindow: { window in await recorder.addUpdate(window) }
        )

        let result = await resolver.resolveTriggeredWindow(
            providerID: .claude,
            commandRunID: UUID(),
            now: triggerTime
        )

        let window = try #require(result)
        #expect(window.commandRunID == earlierRunID)
        let updates = await recorder.updated
        #expect(updates.isEmpty)
    }

    @Test("Promotes an hour-floored fresh anchor even at zero usage")
    func promotesHourFlooredFreshAnchorAtZeroUsage() async throws {
        let recorder = Recorder()
        // A wake prompt at 30 minutes past the hour whose window is reported
        // as starting at the top of that hour: exactly how Claude anchors a
        // fresh window the trigger itself opened. Usage may still read 0%
        // (a tiny wake prompt rounds down), so zero usage alone must not
        // block promotion.
        let triggerTime = Self.hourStart.addingTimeInterval(1802)
        let commandRunID = UUID()
        let snapshot = makeClaudeSnapshot(
            capturedAt: triggerTime,
            windowStartAt: Self.hourStart,
            usedPercentage: 0
        )
        let existing = ActualWindow5h(
            providerID: .claude,
            startAt: Self.hourStart,
            source: .detectedFromUsage,
            confidence: .estimated
        )
        let resolver = ActiveWindowResolver(
            fetcher: makeFetcher(recorder: recorder),
            snapshotFetch: { _ in snapshot },
            activeWindowFetch: { _, _ in existing },
            updateActualWindow: { window in await recorder.addUpdate(window) }
        )

        let result = await resolver.resolveTriggeredWindow(
            providerID: .claude,
            commandRunID: commandRunID,
            now: triggerTime
        )

        let window = try #require(result)
        #expect(window.source == .c5hTriggered)
        #expect(window.confidence == .exact)
        #expect(window.commandRunID == commandRunID)
    }

    @Test("Promotes a stale-start window when usage is nonzero")
    func promotesStaleStartWindowWithNonzeroUsage() async throws {
        let recorder = Recorder()
        // Real consumption in the reported window means the trigger joined a
        // genuinely active window: existing promote semantics apply.
        let triggerTime = Self.hourStart.addingTimeInterval(1800)
        let commandRunID = UUID()
        let snapshot = makeClaudeSnapshot(
            capturedAt: triggerTime,
            windowStartAt: triggerTime.addingTimeInterval(-80 * 60),
            usedPercentage: 12
        )
        let existing = ActualWindow5h(
            providerID: .claude,
            startAt: triggerTime.addingTimeInterval(-80 * 60),
            source: .detectedFromUsage,
            confidence: .estimated
        )
        let resolver = ActiveWindowResolver(
            fetcher: makeFetcher(recorder: recorder),
            snapshotFetch: { _ in snapshot },
            activeWindowFetch: { _, _ in existing },
            updateActualWindow: { window in await recorder.addUpdate(window) }
        )

        let result = await resolver.resolveTriggeredWindow(
            providerID: .claude,
            commandRunID: commandRunID,
            now: triggerTime
        )

        let window = try #require(result)
        #expect(window.source == .c5hTriggered)
        #expect(window.confidence == .exact)
    }

    @Test("Demote path resets a previously stamped c5hTriggered row")
    func demotePathResetsPreviouslyStampedRow() async throws {
        let recorder = Recorder()
        // Regression: upsertByEndAt preserves source=c5hTriggered and upgrades
        // confidence when a detectedFromUsage upsert merges into an already
        // stamped row (e.g. stamped by an earlier trigger's reuse fallback).
        // The demote branch must force the row back rather than trust the
        // read-back state.
        let triggerTime = Self.hourStart.addingTimeInterval(1800)
        let chainedStart = triggerTime.addingTimeInterval(-80 * 60)
        let earlierRunID = UUID()
        var stamped = ActualWindow5h(
            providerID: .claude,
            startAt: chainedStart,
            source: .c5hTriggered,
            confidence: .exact
        )
        stamped.commandRunID = earlierRunID
        let snapshot = makeClaudeSnapshot(
            capturedAt: triggerTime,
            windowStartAt: chainedStart,
            usedPercentage: 0
        )
        let resolver = ActiveWindowResolver(
            fetcher: makeFetcher(recorder: recorder),
            snapshotFetch: { _ in snapshot },
            activeWindowFetch: { [stamped] _, _ in stamped },
            updateActualWindow: { window in await recorder.addUpdate(window) }
        )

        let result = await resolver.resolveTriggeredWindow(
            providerID: .claude,
            commandRunID: UUID(),
            now: triggerTime
        )

        let window = try #require(result)
        #expect(window.source == .detectedFromUsage)
        #expect(window.confidence == .estimated)
        #expect(window.commandRunID == earlierRunID)
        let updates = await recorder.updated
        #expect(updates.count == 1)
        #expect(updates.first?.source == .detectedFromUsage)
    }

    @Test("Reuse fallback does not stamp a window that predates the trigger")
    func reuseFallbackDoesNotStampStaleBoundary() async throws {
        let recorder = Recorder()
        // The post-trigger snapshot fails (e.g. usage probe lock contention);
        // the only window covering now is the chained idle boundary from 80
        // minutes ago. Attach the run, but do not claim C5h opened it.
        let triggerTime = Self.hourStart.addingTimeInterval(1800)
        let chainedStart = triggerTime.addingTimeInterval(-80 * 60)
        let commandRunID = UUID()
        let existing = ActualWindow5h(
            providerID: .claude,
            startAt: chainedStart,
            source: .detectedFromUsage,
            confidence: .estimated
        )
        let resolver = ActiveWindowResolver(
            fetcher: makeFetcher(recorder: recorder),
            snapshotFetch: { _ in throw C5hError.processLaunchFailed("usage CLI timed out") },
            activeWindowFetch: { _, _ in existing },
            updateActualWindow: { window in await recorder.addUpdate(window) }
        )

        let result = await resolver.resolveTriggeredWindow(
            providerID: .claude,
            commandRunID: commandRunID,
            now: triggerTime
        )

        let window = try #require(result)
        #expect(window.id == existing.id)
        #expect(window.source == .detectedFromUsage)
        #expect(window.confidence == .estimated)
        #expect(window.commandRunID == commandRunID)
        let updates = await recorder.updated
        #expect(updates.allSatisfy { $0.source != .c5hTriggered })
    }

    @Test("Trigger-anchor tolerance boundaries")
    func triggerAnchorToleranceBoundaries() {
        let now = Self.hourStart.addingTimeInterval(1800)
        let threshold = Self.hourStart.addingTimeInterval(-ActiveWindowResolver.triggerAnchorTolerance)
        #expect(ActiveWindowResolver.isPlausiblyTriggerAnchored(startAt: threshold, now: now))
        #expect(ActiveWindowResolver.isPlausiblyTriggerAnchored(
            startAt: threshold.addingTimeInterval(-1),
            now: now
        ) == false)
        // A start after the trigger (later in the hour) is trivially plausible.
        #expect(ActiveWindowResolver.isPlausiblyTriggerAnchored(startAt: now, now: now))
    }
}

@Suite("CodexAppServerClient")
struct CodexAppServerClientTests {
    @Test("Matches JSON-RPC ids whether numeric or string")
    func matchesNumericAndStringIds() {
        #expect(CodexAppServerClient.idMatches(1, 1))
        #expect(CodexAppServerClient.idMatches("1", 1))
        #expect(CodexAppServerClient.idMatches(2, 2))
        #expect(!CodexAppServerClient.idMatches(2, 1))
        #expect(!CodexAppServerClient.idMatches("2", 1))
        #expect(!CodexAppServerClient.idMatches(nil, 1))
    }
}
