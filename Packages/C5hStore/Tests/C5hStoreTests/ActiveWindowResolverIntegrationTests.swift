import Foundation
import Testing
@testable import C5hCore
@testable import C5hStore

/// `ActiveWindowResolver` is defined in terms of closures, and its unit tests in
/// C5hCore wire those to in-memory stubs. Stubs cannot reproduce what the
/// repository layer does on write: `upsertByEndAt` merges by `endAt`, preserves
/// a stronger `c5hTriggered` source, and back-fills a nil `commandRunID`. Two
/// regressions reached this branch because a stub kept returning a pristine row
/// where the database would have returned a mutated one.
///
/// These tests wire the resolver to real GRDB repositories exactly as
/// `AppSchedulerDriver` does, so upsert-then-read-back behaviour is exercised.
@Suite("ActiveWindowResolver against a real database")
struct ActiveWindowResolverIntegrationTests {
    /// Trigger at half past the hour, matching the C5hCore suite's fixtures.
    private static let hourStart = Date(timeIntervalSince1970: 1_783_404_000)
    private let triggerTime = hourStart.addingTimeInterval(1800)

    // MARK: Wiring

    private struct Harness {
        let database: Database
        let actual5h: GRDBActualWindow5hRepository
        let commandRuns: GRDBCommandRunRepository
        let resolver: ActiveWindowResolver
    }

    /// Mirrors `AppSchedulerDriver.resolve`: same repositories, same closures.
    private func makeHarness(snapshot: UsageSnapshot?) async throws -> Harness {
        let database = try Database.inMemory()
        try await Seed.runIfNeeded(database: database)
        let actual5h = GRDBActualWindow5hRepository(database: database)
        let actual7d = GRDBActualWindow7dRepository(database: database)
        let usage = GRDBUsageSnapshotRepository(database: database)
        let commandRuns = GRDBCommandRunRepository(database: database)

        let fetcher = UsageFetcher(
            persistSnapshot: { try await usage.create($0) },
            upsertActualWindow5h: { try await actual5h.upsertByEndAt($0, tolerance: $1) },
            upsertActualWindow7d: { try await actual7d.upsertByEndAt($0, tolerance: $1) }
        )
        let resolver = ActiveWindowResolver(
            fetcher: fetcher,
            snapshotFetch: { _ in
                guard let snapshot else {
                    throw C5hError.usageRefreshAlreadyRunning(.claude)
                }
                return snapshot
            },
            activeWindowFetch: { providerID, now in
                try await actual5h.fetchActiveWindow(providerID: providerID, at: now)
            },
            updateActualWindow: { try await actual5h.update($0) },
            triggerAttributionFetch: { try await commandRuns.fetchAttributionEvidence(id: $0) },
            latestSnapshotFetch: { try await usage.fetchLatest(providerID: $0) }
        )
        return Harness(
            database: database,
            actual5h: actual5h,
            commandRuns: commandRuns,
            resolver: resolver
        )
    }

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

    @discardableResult
    private func recordPrompt(
        _ harness: Harness,
        id: UUID,
        startedAt: Date
    ) async throws -> UUID {
        try await harness.commandRuns.create(CommandRun(
            id: id,
            providerID: .claude,
            commandName: .prompt,
            command: "claude",
            argumentsJSON: "[]",
            startedAt: startedAt,
            status: .succeeded
        ))
        return id
    }

    // MARK: Tests

    @Test("A run's own upsert link does not demote a triggered window")
    func ownUpsertLinkDoesNotDemoteTriggeredWindow() async throws {
        // The regression the stubs hid: upsertByEndAt back-fills the nil
        // commandRunID with the run being resolved, so the row reads back
        // linked to it. Treating that as an earlier trigger validates the run
        // against itself and demotes a window with nothing to preserve.
        let chainedStart = triggerTime.addingTimeInterval(-80 * 60)
        let snapshot = makeClaudeSnapshot(
            capturedAt: triggerTime,
            windowStartAt: chainedStart,
            usedPercentage: 0
        )
        let harness = try await makeHarness(snapshot: snapshot)
        let commandRunID = UUID()
        try await recordPrompt(harness, id: commandRunID, startedAt: triggerTime)

        // A triggered row with no command link, matching the snapshot's bounds.
        try await harness.actual5h.upsertByEndAt(ActualWindow5h(
            providerID: .claude,
            startAt: chainedStart,
            source: .c5hTriggered,
            confidence: .exact
        ), tolerance: 0)

        let window = try #require(await harness.resolver.resolveTriggeredWindow(
            providerID: .claude,
            commandRunID: commandRunID,
            now: triggerTime
        ))

        #expect(window.source == .c5hTriggered)
        #expect(window.commandRunID == commandRunID)

        // Confirm against the database, not just the returned value.
        let stored = try #require(await harness.actual5h.fetchActiveWindow(
            providerID: .claude,
            at: triggerTime
        ))
        #expect(stored.source == .c5hTriggered)
        #expect(stored.commandRunID == commandRunID)
    }

    @Test("A genuinely earlier trigger still survives this run")
    func earlierTriggerSurvives() async throws {
        // The counterpart to the test above, and the reason the fix checks for
        // *this* run's id rather than skipping validation entirely: a
        // different run opened the window and its attribution is plausible, so
        // this run must neither claim nor demote it.
        //
        // The start predates this trigger, so the demote branch runs and the
        // earlier run's evidence is what decides the outcome. The earlier run
        // began just after the window opened, which makes it a plausible
        // anchor, so attribution resolves to `.confirmed`.
        let chainedStart = triggerTime.addingTimeInterval(-80 * 60)
        let earlierRunID = UUID()
        let laterRunID = UUID()
        let snapshot = makeClaudeSnapshot(
            capturedAt: triggerTime,
            windowStartAt: chainedStart,
            usedPercentage: 0
        )
        let harness = try await makeHarness(snapshot: snapshot)
        try await recordPrompt(
            harness,
            id: earlierRunID,
            startedAt: chainedStart.addingTimeInterval(60)
        )
        try await recordPrompt(harness, id: laterRunID, startedAt: triggerTime)

        var stamped = ActualWindow5h(
            providerID: .claude,
            startAt: chainedStart,
            source: .c5hTriggered,
            confidence: .exact
        )
        stamped.commandRunID = earlierRunID
        try await harness.actual5h.upsertByEndAt(stamped, tolerance: 0)

        let window = try #require(await harness.resolver.resolveTriggeredWindow(
            providerID: .claude,
            commandRunID: laterRunID,
            now: triggerTime
        ))

        #expect(window.source == .c5hTriggered)
        #expect(window.commandRunID == earlierRunID)

        let stored = try #require(await harness.actual5h.fetchActiveWindow(
            providerID: .claude,
            at: triggerTime
        ))
        #expect(stored.commandRunID == earlierRunID)
    }

    @Test("An overlapping row does not strand the derived window's link")
    func derivedWindowKeepsLinkWhenAnotherRowCoversNow() async throws {
        // `fetchActiveWindow` returns the *latest* window covering now, which
        // need not be the row just derived. When the bounds do not match, the
        // resolver returns `derived5h` and deliberately leaves the unrelated
        // row alone, so the only chance to attribute the derived row is the
        // upsert itself. Without the link on the upsert the run is stranded.
        let chainedStart = triggerTime.addingTimeInterval(-80 * 60)
        let snapshot = makeClaudeSnapshot(
            capturedAt: triggerTime,
            windowStartAt: chainedStart,
            usedPercentage: 0
        )
        let harness = try await makeHarness(snapshot: snapshot)
        let commandRunID = UUID()
        let unrelatedRunID = UUID()
        try await recordPrompt(harness, id: commandRunID, startedAt: triggerTime)

        // Starts later and ends 70 minutes away from the derived window, so it
        // wins `fetchActiveWindow` but is not matched by bounds. It is
        // `detectedFromUsage` on purpose: `upsertByEndAt`'s placeholder-collapse
        // fallback only absorbs a `c5hTriggered` row, so this stays a separate
        // row and the derived window really is inserted on its own.
        var unrelated = ActualWindow5h(
            providerID: .claude,
            startAt: triggerTime.addingTimeInterval(-10 * 60),
            source: .detectedFromUsage,
            confidence: .estimated
        )
        unrelated.commandRunID = unrelatedRunID
        try await harness.actual5h.upsertByEndAt(unrelated, tolerance: 0)

        _ = await harness.resolver.resolveTriggeredWindow(
            providerID: .claude,
            commandRunID: commandRunID,
            now: triggerTime
        )

        let windows = try await harness.actual5h.fetchWindows(
            for: DateInterval(start: chainedStart, end: triggerTime.addingTimeInterval(5 * 3600))
        )
        let derived = try #require(windows.first { $0.startAt == chainedStart })
        #expect(derived.commandRunID == commandRunID)
        // The unrelated window keeps its own attribution.
        #expect(derived.id != unrelated.id)
        let untouched = try #require(windows.first { $0.id == unrelated.id })
        #expect(untouched.commandRunID == unrelatedRunID)
        #expect(untouched.startAt == triggerTime.addingTimeInterval(-10 * 60))
    }

    @Test("The derived window is persisted with the trigger's command link")
    func derivedWindowPersistsCommandLink() async throws {
        // Attribution must reach the database, not just the returned value:
        // the demote path returns `derived5h` directly on several branches.
        let chainedStart = triggerTime.addingTimeInterval(-80 * 60)
        let snapshot = makeClaudeSnapshot(
            capturedAt: triggerTime,
            windowStartAt: chainedStart,
            usedPercentage: 0
        )
        let harness = try await makeHarness(snapshot: snapshot)
        let commandRunID = UUID()
        try await recordPrompt(harness, id: commandRunID, startedAt: triggerTime)

        let window = try #require(await harness.resolver.resolveTriggeredWindow(
            providerID: .claude,
            commandRunID: commandRunID,
            now: triggerTime
        ))
        // Zero usage on a window predating the trigger stays detectedFromUsage.
        #expect(window.source == .detectedFromUsage)

        let stored = try #require(await harness.actual5h.fetchActiveWindow(
            providerID: .claude,
            at: triggerTime
        ))
        #expect(stored.commandRunID == commandRunID)
        #expect(stored.source == .detectedFromUsage)
    }

    @Test("A fresh anchored window is promoted and linked in the database")
    func freshAnchorIsPromotedAndPersisted() async throws {
        // Hour-floored fresh anchor at 0%: the trigger genuinely opened it.
        let snapshot = makeClaudeSnapshot(
            capturedAt: triggerTime,
            windowStartAt: Self.hourStart,
            usedPercentage: 0
        )
        let harness = try await makeHarness(snapshot: snapshot)
        let commandRunID = UUID()
        try await recordPrompt(harness, id: commandRunID, startedAt: triggerTime)

        let window = try #require(await harness.resolver.resolveTriggeredWindow(
            providerID: .claude,
            commandRunID: commandRunID,
            now: triggerTime
        ))
        #expect(window.source == .c5hTriggered)

        let stored = try #require(await harness.actual5h.fetchActiveWindow(
            providerID: .claude,
            at: triggerTime
        ))
        #expect(stored.source == .c5hTriggered)
        #expect(stored.commandRunID == commandRunID)
        #expect(stored.startAt == Self.hourStart)
    }

    @Test("A concurrent poll's snapshot anchors the trigger from the database")
    func anchorsFromLatestPersistedSnapshot() async throws {
        // The contended path: the resolver's own probe fails because another
        // poll holds the lock, and that poll's snapshot was captured seconds
        // *after* the command started.
        let harness = try await makeHarness(snapshot: nil)
        let commandRunID = UUID()
        try await recordPrompt(harness, id: commandRunID, startedAt: triggerTime)

        let usage = GRDBUsageSnapshotRepository(database: harness.database)
        try await usage.create(makeClaudeSnapshot(
            capturedAt: triggerTime.addingTimeInterval(7),
            windowStartAt: Self.hourStart,
            usedPercentage: 0
        ))

        let window = try #require(await harness.resolver.resolveTriggeredWindow(
            providerID: .claude,
            commandRunID: commandRunID,
            now: triggerTime
        ))
        #expect(window.startAt == Self.hourStart)
        #expect(window.commandRunID == commandRunID)

        let stored = try #require(await harness.actual5h.fetchActiveWindow(
            providerID: .claude,
            at: triggerTime
        ))
        #expect(stored.commandRunID == commandRunID)
    }
}
