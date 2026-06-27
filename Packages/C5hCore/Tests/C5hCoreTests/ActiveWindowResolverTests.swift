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
        // duplicate windows bug.)
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
        #expect(window.source == .c5hTriggered)
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
