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

    @Test("Pins an estimated triggered window to the trigger time when usage fetch fails")
    func synthesizesFallbackWhenSnapshotFails() async throws {
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

        let window = try #require(result)
        #expect(window.source == .c5hTriggered)
        #expect(window.confidence == .estimated)
        #expect(window.commandRunID == commandRunID)
        #expect(window.startAt == triggerTime)
        #expect(window.durationSeconds == 5 * 3600)

        let upserts = await recorder.upserted5h
        #expect(upserts.count == 1)
        let updates = await recorder.updated
        #expect(updates.isEmpty)
    }

    @Test("Pins an estimated triggered window when Codex reports a synthetic slot")
    func synthesizesFallbackForCodexSyntheticSlot() async throws {
        let recorder = Recorder()
        // `codex app-server` returns resetsAt = capturedAt + 5h before any real
        // window anchors, so derived5h is nil and the resolver must fall back.
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
            activeWindowFetch: { _, _ in Issue.record("should not promote a synthetic slot"); return nil },
            updateActualWindow: { window in await recorder.addUpdate(window) }
        )

        let result = await resolver.resolveTriggeredWindow(
            providerID: .codex,
            commandRunID: commandRunID,
            now: triggerTime
        )

        let window = try #require(result)
        #expect(window.source == .c5hTriggered)
        #expect(window.confidence == .estimated)
        #expect(window.startAt == triggerTime)
        let updates = await recorder.updated
        #expect(updates.isEmpty)
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
