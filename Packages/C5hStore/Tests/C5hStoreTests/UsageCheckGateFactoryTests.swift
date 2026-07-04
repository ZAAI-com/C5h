import Foundation
import Testing
@testable import C5hCore
@testable import C5hStore

@Suite("UsageCheckGate factory")
struct UsageCheckGateFactoryTests {
    @Test("Pending planned windows must overlap now when idle checking is disabled")
    func pendingPlannedWindowsMustOverlapNow() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let settings = GRDBAppSettingsRepository(database: db)
        let plannedRepo = GRDBPlannedWindowRepository(database: db)
        let actualRepo = GRDBActualWindow5hRepository(database: db)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
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
            plannedWindowRepository: plannedRepo
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
        let now = Date(timeIntervalSince1970: 1_800_000_000)
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
            plannedWindowRepository: plannedRepo
        )

        #expect(await gate.shouldCheck(providerID: .claude, now: now))

        let intervals = await plannedRepo.fetchWindowIntervals()
        #expect(intervals.count == 1)
        #expect(intervals.first?.start == now)
        #expect(intervals.first?.duration == 1)
        #expect(await plannedRepo.fetchAllCallCount() == 0)
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
