import Foundation
import Testing
@testable import C5hCore
@testable import C5hStore

@Suite("UsageCheckGate factory")
struct UsageCheckGateFactoryTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Pending planned windows must overlap now when idle checking is disabled")
    func pendingPlannedWindowsMustOverlapNow() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let settings = GRDBAppSettingsRepository(database: db)
        let plannedRepo = GRDBPlannedWindowRepository(database: db)
        let actualRepo = GRDBActualWindow5hRepository(database: db)
        try await settings.set(AppSettingsKeys.checkUsageWhenIdle(for: .claude), value: false)

        try await plannedRepo.create(PlannedWindow(
            providerID: .claude,
            startAt: now.addingTimeInterval(-10 * 3600),
            status: .scheduled
        ))
        try await plannedRepo.create(PlannedWindow(
            providerID: .claude,
            startAt: now.addingTimeInterval(10 * 3600),
            status: .scheduled
        ))

        let gate = UsageCheckGate.make(
            appSettings: settings,
            actual5hRepository: actualRepo,
            plannedWindowRepository: plannedRepo,
            usageSnapshotRepository: GRDBUsageSnapshotRepository(database: db),
            localActivityDetector: Self.emptyDetector()
        )
        #expect(await gate.shouldCheck(providerID: .claude, now: now) == false)

        try await plannedRepo.create(PlannedWindow(
            providerID: .claude,
            startAt: now.addingTimeInterval(-60),
            status: .scheduled
        ))
        #expect(await gate.shouldCheck(providerID: .claude, now: now))
    }

    @Test("Pending planned lookup uses a targeted overlap query")
    func pendingPlannedLookupUsesTargetedQuery() async throws {
        let plannedRepo = RecordingPlannedWindowRepository(windows: [
            PlannedWindow(
                providerID: .claude,
                startAt: now.addingTimeInterval(-60),
                status: .scheduled
            )
        ])
        let gate = UsageCheckGate.make(
            appSettings: StaticAppSettingsRepository(idleCheckEnabled: false),
            actual5hRepository: EmptyActualWindow5hRepository(),
            plannedWindowRepository: plannedRepo,
            usageSnapshotRepository: EmptyUsageSnapshotRepository(),
            localActivityDetector: Self.emptyDetector()
        )

        #expect(await gate.shouldCheck(providerID: .claude, now: now))

        let intervals = await plannedRepo.fetchWindowIntervals()
        #expect(intervals.count == 1)
        #expect(intervals.first?.start == now)
        #expect(intervals.first?.duration == 1)
        #expect(await plannedRepo.fetchAllCallCount() == 0)
    }

    @Test("Claude with idle checking on probes only after fresh local activity")
    func claudeIdleOnRequiresFreshLocalActivity() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let settings = GRDBAppSettingsRepository(database: db)
        try await settings.set(AppSettingsKeys.checkUsageWhenIdle(for: .claude), value: true)
        let projects = try makeProjectsDirectory()
        defer { removeDirectory(projects) }

        let gate = UsageCheckGate.make(
            appSettings: settings,
            actual5hRepository: GRDBActualWindow5hRepository(database: db),
            plannedWindowRepository: GRDBPlannedWindowRepository(database: db),
            usageSnapshotRepository: GRDBUsageSnapshotRepository(database: db),
            localActivityDetector: ClaudeLocalActivityDetector(
                projectsDirectory: projects,
                excludedProjectPaths: []
            )
        )

        // Regression test for 24/7 window chaining: idle setting alone must
        // not open the gate for Claude's quota-consuming probe.
        #expect(await gate.shouldCheck(providerID: .claude, now: now) == false)

        try makeTranscript(
            in: projects,
            project: "-Users-m-Some-Project",
            name: "session.jsonl",
            modifiedAt: now.addingTimeInterval(-60)
        )
        #expect(await gate.shouldCheck(providerID: .claude, now: now))
    }

    @Test("Claude ignores local activity older than the last recorded window end")
    func claudeIgnoresActivityOlderThanRecordedWindowEnd() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let settings = GRDBAppSettingsRepository(database: db)
        try await settings.set(AppSettingsKeys.checkUsageWhenIdle(for: .claude), value: true)
        let actualRepo = GRDBActualWindow5hRepository(database: db)
        let projects = try makeProjectsDirectory()
        defer { removeDirectory(projects) }

        // A recorded window that ended 10 minutes ago (within the lookback).
        let windowEnd = now.addingTimeInterval(-600)
        try await actualRepo.create(ActualWindow5h(
            providerID: .claude,
            startAt: windowEnd.addingTimeInterval(-5 * 3600),
            source: .detectedFromUsage,
            confidence: .estimated
        ))

        let gate = UsageCheckGate.make(
            appSettings: settings,
            actual5hRepository: actualRepo,
            plannedWindowRepository: GRDBPlannedWindowRepository(database: db),
            usageSnapshotRepository: GRDBUsageSnapshotRepository(database: db),
            localActivityDetector: ClaudeLocalActivityDetector(
                projectsDirectory: projects,
                excludedProjectPaths: []
            )
        )

        // Activity from inside the closed window must not reopen probing.
        try makeTranscript(
            in: projects,
            project: "-Users-m-Some-Project",
            name: "inside-window.jsonl",
            modifiedAt: windowEnd.addingTimeInterval(-60)
        )
        #expect(await gate.shouldCheck(providerID: .claude, now: now) == false)

        // Activity after the window end means a new window is open.
        try makeTranscript(
            in: projects,
            project: "-Users-m-Some-Project",
            name: "after-window.jsonl",
            modifiedAt: windowEnd.addingTimeInterval(60)
        )
        #expect(await gate.shouldCheck(providerID: .claude, now: now))
    }

    @Test("Claude ignores local activity older than the lookback")
    func claudeIgnoresActivityOlderThanLookback() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let settings = GRDBAppSettingsRepository(database: db)
        try await settings.set(AppSettingsKeys.checkUsageWhenIdle(for: .claude), value: true)
        let projects = try makeProjectsDirectory()
        defer { removeDirectory(projects) }

        // Default refresh interval is 300s, so the lookback floor is 900s.
        try makeTranscript(
            in: projects,
            project: "-Users-m-Some-Project",
            name: "stale.jsonl",
            modifiedAt: now.addingTimeInterval(-1000)
        )

        let gate = UsageCheckGate.make(
            appSettings: settings,
            actual5hRepository: GRDBActualWindow5hRepository(database: db),
            plannedWindowRepository: GRDBPlannedWindowRepository(database: db),
            usageSnapshotRepository: GRDBUsageSnapshotRepository(database: db),
            localActivityDetector: ClaudeLocalActivityDetector(
                projectsDirectory: projects,
                excludedProjectPaths: []
            )
        )
        #expect(await gate.shouldCheck(providerID: .claude, now: now) == false)
    }

    @Test("Codex with idle checking on never consults the local activity detector")
    func codexIdleOnDoesNotTouchDetector() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let settings = GRDBAppSettingsRepository(database: db)
        try await settings.set(AppSettingsKeys.checkUsageWhenIdle(for: .codex), value: true)

        let gate = UsageCheckGate.make(
            appSettings: settings,
            actual5hRepository: GRDBActualWindow5hRepository(database: db),
            plannedWindowRepository: GRDBPlannedWindowRepository(database: db),
            usageSnapshotRepository: GRDBUsageSnapshotRepository(database: db),
            localActivityDetector: Self.emptyDetector()
        )
        #expect(await gate.shouldCheck(providerID: .codex, now: now))
    }

    @Test("A Claude window ending within the probe margin is not active; a Codex one is")
    func claudeWindowEndingWithinMarginIsNotActive() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let settings = GRDBAppSettingsRepository(database: db)
        try await settings.set(AppSettingsKeys.checkUsageWhenIdle(for: .claude), value: false)
        try await settings.set(AppSettingsKeys.checkUsageWhenIdle(for: .codex), value: false)
        let actualRepo = GRDBActualWindow5hRepository(database: db)

        // Both windows end 30s from now, inside the 90s consuming-probe margin.
        for providerID in [ProviderID.claude, .codex] {
            try await actualRepo.create(ActualWindow5h(
                providerID: providerID,
                startAt: now.addingTimeInterval(30 - 5 * 3600),
                source: .detectedFromUsage,
                confidence: .estimated
            ))
        }

        let gate = UsageCheckGate.make(
            appSettings: settings,
            actual5hRepository: actualRepo,
            plannedWindowRepository: GRDBPlannedWindowRepository(database: db),
            usageSnapshotRepository: GRDBUsageSnapshotRepository(database: db),
            localActivityDetector: Self.emptyDetector()
        )
        #expect(await gate.shouldCheck(providerID: .claude, now: now) == false)
        #expect(await gate.shouldCheck(providerID: .codex, now: now))
    }

    @Test("Claude is believed active from the latest snapshot's window end")
    func claudeBelievedActiveFromLatestSnapshot() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let settings = GRDBAppSettingsRepository(database: db)
        try await settings.set(AppSettingsKeys.checkUsageWhenIdle(for: .claude), value: false)
        let snapshotRepo = GRDBUsageSnapshotRepository(database: db)

        let gate = UsageCheckGate.make(
            appSettings: settings,
            actual5hRepository: GRDBActualWindow5hRepository(database: db),
            plannedWindowRepository: GRDBPlannedWindowRepository(database: db),
            usageSnapshotRepository: snapshotRepo,
            localActivityDetector: Self.emptyDetector()
        )

        // A window whose usage rounds to 0% never produced a recorded row, but
        // the snapshot still reports its end an hour out: believed open.
        try await snapshotRepo.create(makeSnapshot(
            capturedAt: now.addingTimeInterval(-300),
            windowEndsAt: now.addingTimeInterval(3600)
        ))
        #expect(await gate.shouldCheck(providerID: .claude, now: now))

        // A newer snapshot whose window end falls inside the probe margin must
        // not count as active.
        try await snapshotRepo.create(makeSnapshot(
            capturedAt: now.addingTimeInterval(-60),
            windowEndsAt: now.addingTimeInterval(30)
        ))
        #expect(await gate.shouldCheck(providerID: .claude, now: now) == false)
    }

    @Test("An upcoming planned window suppresses Claude probing despite strong evidence")
    func upcomingPlannedWindowWithinHorizonSuppressesClaude() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let settings = GRDBAppSettingsRepository(database: db)
        try await settings.set(AppSettingsKeys.checkUsageWhenIdle(for: .claude), value: true)
        let plannedRepo = GRDBPlannedWindowRepository(database: db)
        let snapshotRepo = GRDBUsageSnapshotRepository(database: db)
        let projects = try makeProjectsDirectory()
        defer { removeDirectory(projects) }

        // Strongest pro-probe evidence: fresh local activity AND a snapshot
        // that believes a window is open.
        try makeTranscript(
            in: projects,
            project: "-Users-m-Some-Project",
            name: "fresh.jsonl",
            modifiedAt: now.addingTimeInterval(-60)
        )
        try await snapshotRepo.create(makeSnapshot(
            capturedAt: now.addingTimeInterval(-300),
            windowEndsAt: now.addingTimeInterval(3600)
        ))

        let gate = UsageCheckGate.make(
            appSettings: settings,
            actual5hRepository: GRDBActualWindow5hRepository(database: db),
            plannedWindowRepository: plannedRepo,
            usageSnapshotRepository: snapshotRepo,
            localActivityDetector: ClaudeLocalActivityDetector(
                projectsDirectory: projects,
                excludedProjectPaths: []
            )
        )
        #expect(await gate.shouldCheck(providerID: .claude, now: now))

        // A planned window 2h out puts us inside the quiet period.
        try await plannedRepo.create(PlannedWindow(
            providerID: .claude,
            startAt: now.addingTimeInterval(2 * 3600),
            status: .scheduled
        ))
        #expect(await gate.shouldCheck(providerID: .claude, now: now) == false)
    }

    @Test("A planned window at the horizon boundary does not suppress")
    func plannedWindowAtHorizonBoundaryDoesNotSuppress() async throws {
        // Exactly at the horizon: the overlap query is half-open on start_at,
        // so this window is outside the quiet period and the believed-active
        // snapshot keeps the gate open.
        let gate = try await makeQuietPeriodGate(
            plannedWindow: PlannedWindow(
                providerID: .claude,
                startAt: now.addingTimeInterval(UsageCheckGate.preWindowQuietHorizon),
                status: .scheduled
            )
        )
        #expect(await gate.shouldCheck(providerID: .claude, now: now))
    }

    @Test("A terminal planned window inside the horizon does not suppress")
    func terminalPlannedWindowDoesNotSuppress() async throws {
        let gate = try await makeQuietPeriodGate(
            plannedWindow: PlannedWindow(
                providerID: .claude,
                startAt: now.addingTimeInterval(2 * 3600),
                status: .cancelled
            )
        )
        #expect(await gate.shouldCheck(providerID: .claude, now: now))
    }

    /// Gate over one planned window plus a believed-active snapshot (window end
    /// an hour out), with idle checking off, so `shouldCheck` is true unless the
    /// quiet period suppresses it.
    private func makeQuietPeriodGate(plannedWindow: PlannedWindow) async throws -> UsageCheckGate {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let settings = GRDBAppSettingsRepository(database: db)
        try await settings.set(AppSettingsKeys.checkUsageWhenIdle(for: .claude), value: false)
        let plannedRepo = GRDBPlannedWindowRepository(database: db)
        let snapshotRepo = GRDBUsageSnapshotRepository(database: db)

        try await snapshotRepo.create(makeSnapshot(
            capturedAt: now.addingTimeInterval(-300),
            windowEndsAt: now.addingTimeInterval(3600)
        ))
        try await plannedRepo.create(plannedWindow)

        return UsageCheckGate.make(
            appSettings: settings,
            actual5hRepository: GRDBActualWindow5hRepository(database: db),
            plannedWindowRepository: plannedRepo,
            usageSnapshotRepository: snapshotRepo,
            localActivityDetector: Self.emptyDetector()
        )
    }

    @Test("An upcoming planned window does not suppress Codex's read-only probe")
    func upcomingPlannedWindowDoesNotSuppressCodex() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let settings = GRDBAppSettingsRepository(database: db)
        try await settings.set(AppSettingsKeys.checkUsageWhenIdle(for: .codex), value: true)
        let plannedRepo = GRDBPlannedWindowRepository(database: db)

        try await plannedRepo.create(PlannedWindow(
            providerID: .codex,
            startAt: now.addingTimeInterval(2 * 3600),
            status: .scheduled
        ))

        let gate = UsageCheckGate.make(
            appSettings: settings,
            actual5hRepository: GRDBActualWindow5hRepository(database: db),
            plannedWindowRepository: plannedRepo,
            usageSnapshotRepository: GRDBUsageSnapshotRepository(database: db),
            localActivityDetector: Self.emptyDetector()
        )
        #expect(await gate.shouldCheck(providerID: .codex, now: now))
    }

    private static func emptyDetector() -> ClaudeLocalActivityDetector {
        ClaudeLocalActivityDetector(
            projectsDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("c5h-tests-missing-\(UUID().uuidString)", isDirectory: true),
            excludedProjectPaths: []
        )
    }

    private func makeSnapshot(capturedAt: Date, windowEndsAt: Date) -> UsageSnapshot {
        let normalized = NormalizedUsage(
            providerID: .claude,
            capturedAt: capturedAt,
            windowStartedAt: windowEndsAt.addingTimeInterval(-5 * 3600),
            windowEndsAt: windowEndsAt,
            usedPercentage: 0
        )
        return UsageSnapshot(
            providerID: .claude,
            capturedAt: capturedAt,
            rawJSON: "{}",
            normalizedJSON: UsageNormalizer.encode(normalized)
        )
    }

    private func makeProjectsDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("c5h-tests-projects-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeTranscript(
        in projects: URL,
        project: String,
        name: String,
        modifiedAt: Date
    ) throws {
        let directory = projects.appendingPathComponent(project, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(name)
        try Data("{}\n".utf8).write(to: file)
        try FileManager.default.setAttributes(
            [.modificationDate: modifiedAt],
            ofItemAtPath: file.path
        )
    }

    private func removeDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

private struct StaticAppSettingsRepository: AppSettingsRepository {
    var idleCheckEnabled: Bool

    func get<T: Decodable & Sendable>(_ key: String, as type: T.Type) async throws -> T? {
        if type == Bool.self {
            return idleCheckEnabled as? T
        }
        return nil
    }

    func set<T: Encodable & Sendable>(_ key: String, value: T) async throws {}

    func remove(_ key: String) async throws {}
}

private struct EmptyActualWindow5hRepository: ActualWindow5hRepository {
    func fetchAll() async throws -> [ActualWindow5h] { [] }

    func fetchWindows(for interval: DateInterval) async throws -> [ActualWindow5h] { [] }

    func create(_ window: ActualWindow5h) async throws {}

    func update(_ window: ActualWindow5h) async throws {}

    func upsertByEndAt(_ window: ActualWindow5h, tolerance: TimeInterval) async throws {}
}

private struct EmptyUsageSnapshotRepository: UsageSnapshotRepository {
    func create(_ snapshot: UsageSnapshot) async throws {}

    func fetchLatest(providerID: ProviderID) async throws -> UsageSnapshot? { nil }

    func fetchInRange(providerID: ProviderID, interval: DateInterval) async throws -> [UsageSnapshot] { [] }
}

private actor RecordingPlannedWindowRepository: PlannedWindowRepository {
    private let windows: [PlannedWindow]
    private var fetchAllCount = 0
    private var intervals: [DateInterval] = []

    init(windows: [PlannedWindow]) {
        self.windows = windows
    }

    func fetchAll() async throws -> [PlannedWindow] {
        fetchAllCount += 1
        return windows
    }

    func fetchWindows(for interval: DateInterval) async throws -> [PlannedWindow] {
        intervals.append(interval)
        return windows
    }

    func fetch(id: UUID) async throws -> PlannedWindow? {
        windows.first { $0.id == id }
    }

    func create(_ window: PlannedWindow) async throws {}

    func update(_ window: PlannedWindow) async throws {}

    func delete(id: UUID) async throws {}

    func deleteWithPendingPromptCleanup(id: UUID) async throws {}

    func fetchAllCallCount() -> Int {
        fetchAllCount
    }

    func fetchWindowIntervals() -> [DateInterval] {
        intervals
    }
}
